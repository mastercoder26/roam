import CoreLocation
import CoreMotion
import Combine
import Foundation

@MainActor
final class DriveSessionManager: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var currentSpeedMetersPerSecond: CLLocationSpeed = 0
    @Published private(set) var motionSamples = 0
    @Published private(set) var acceptedLocationSamples = 0
    @Published private(set) var rejectedLocationSamples = 0
    @Published private(set) var currentHorizontalAccelerationG = 0.0
    @Published private(set) var statusMessage = "Ready when you are"
    @Published private(set) var lastScore: DrivingScore?

    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private var timer: Timer?
    private var startDate: Date?
    private var previousLocation: CLLocation?
    private var distanceMeters: CLLocationDistance = 0
    private var topSpeed: CLLocationSpeed = 0
    private var events: [DrivingEvent] = []
    private var lastEventAt: [DrivingEventKind: Date] = [:]
    private var recentMotionSamples: [DriveMotionSample] = []

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .automotiveNavigation
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5
    }

    func startDrive() {
        guard !isRecording else { return }

        resetCurrentDrive()
        isRecording = true
        startDate = Date()
        statusMessage = "Recording this drive"
        startElapsedTimer()
        startMotionUpdates()

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            statusMessage = "Location access is off — motion will still be recorded"
        @unknown default:
            statusMessage = "Waiting for location permission"
        }
    }

    func endDrive() {
        guard isRecording else { return }
        let duration = Date().timeIntervalSince(startDate ?? Date())
        isRecording = false
        timer?.invalidate()
        timer = nil
        motionManager.stopDeviceMotionUpdates()
        locationManager.stopUpdatingLocation()
        currentSpeedMetersPerSecond = 0

        let result = DriveScoringEngine.score(
            duration: duration,
            distanceMeters: distanceMeters,
            events: events,
            acceptedLocationSamples: acceptedLocationSamples,
            rejectedLocationSamples: rejectedLocationSamples,
            motionSamples: motionSamples
        )
        lastScore = DrivingScore(
            score: result.score,
            duration: duration,
            distanceMeters: distanceMeters,
            topSpeedMetersPerSecond: topSpeed,
            events: events,
            motionSamples: motionSamples,
            dataQuality: result.quality
        )
        statusMessage = motionSamples == 0
            ? "No motion samples received — try a physical iPhone."
            : "Drive saved on this device"
    }

    private func resetCurrentDrive() {
        elapsed = 0
        currentSpeedMetersPerSecond = 0
        motionSamples = 0
        acceptedLocationSamples = 0
        rejectedLocationSamples = 0
        currentHorizontalAccelerationG = 0
        previousLocation = nil
        distanceMeters = 0
        topSpeed = 0
        events = []
        lastEventAt = [:]
        recentMotionSamples = []
    }

    private func startElapsedTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let startDate = self.startDate else { return }
            self.elapsed = Date().timeIntervalSince(startDate)
        }
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            statusMessage = "Motion data is unavailable on this device"
            return
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / 20.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion, self.isRecording else { return }
            self.record(motion: motion)
        }
    }

    private func record(motion: CMDeviceMotion) {
        motionSamples += 1

        // `userAcceleration` removes gravity. Transform it into a vertical-Z
        // reference frame before measuring horizontal force so phone orientation
        // does not change the reading.
        let acceleration = motion.userAcceleration
        let matrix = motion.attitude.rotationMatrix
        let worldX = matrix.m11 * acceleration.x + matrix.m12 * acceleration.y + matrix.m13 * acceleration.z
        let worldY = matrix.m21 * acceleration.x + matrix.m22 * acceleration.y + matrix.m23 * acceleration.z
        let horizontalG = hypot(worldX, worldY)
        currentHorizontalAccelerationG = horizontalG

        recentMotionSamples.append(
            DriveMotionSample(timestamp: Date(), horizontalAccelerationG: horizontalG)
        )
        recentMotionSamples.removeAll { Date().timeIntervalSince($0.timestamp) > 2 }

        if DriveScoringEngine.shouldFlagPhoneMovement(horizontalG) {
            addEvent(.phoneMovement, source: .deviceMotion, cooldown: 3)
        }
    }

    private func record(location: CLLocation) {
        let sample = DriveLocationSample(
            timestamp: location.timestamp,
            speedMetersPerSecond: location.speed,
            courseDegrees: location.course >= 0 ? location.course : nil,
            horizontalAccuracyMeters: location.horizontalAccuracy
        )

        guard DriveScoringEngine.accepts(sample) else {
            rejectedLocationSamples += 1
            return
        }

        acceptedLocationSamples += 1
        let speed = max(location.speed, 0)
        currentSpeedMetersPerSecond = speed
        topSpeed = max(topSpeed, speed)

        if let previousLocation {
            let time = location.timestamp.timeIntervalSince(previousLocation.timestamp)
            if time >= DriveScoringEngine.minimumSampleGap, time <= DriveScoringEngine.maximumSampleGap {
                distanceMeters += location.distance(from: previousLocation)
                let previousSample = DriveLocationSample(
                    timestamp: previousLocation.timestamp,
                    speedMetersPerSecond: previousLocation.speed,
                    courseDegrees: previousLocation.course >= 0 ? previousLocation.course : nil,
                    horizontalAccuracyMeters: previousLocation.horizontalAccuracy
                )
                let nearbyMotion = recentMotionSamples
                    .filter { abs($0.timestamp.timeIntervalSince(location.timestamp)) <= 1 }
                    .map(\.horizontalAccelerationG)
                    .max()
                for event in DriveScoringEngine.detectEvents(
                    previous: previousSample,
                    current: sample,
                    nearbyMotionG: nearbyMotion
                ) {
                    let cooldown: TimeInterval = event.kind == .sharpCorner ? 5 : 4
                    addEvent(event.kind, source: event.source, cooldown: cooldown)
                }
            }
        }

        previousLocation = location
    }

    private func addEvent(_ kind: DrivingEventKind, source: DrivingEventSource, cooldown: TimeInterval) {
        let now = Date()
        if let lastEvent = lastEventAt[kind], now.timeIntervalSince(lastEvent) < cooldown { return }
        lastEventAt[kind] = now
        events.append(DrivingEvent(kind: kind, timestamp: now, source: source))
    }
}

extension DriveSessionManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self, self.isRecording else { return }
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.startUpdatingLocation()
                self.statusMessage = "Recording this drive"
            case .denied, .restricted:
                self.statusMessage = "Location access is off — motion will still be recorded"
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            self?.record(location: location)
        }
    }
}
