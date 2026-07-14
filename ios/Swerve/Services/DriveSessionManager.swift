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
    @Published private(set) var statusMessage = "Ready when you are"
    @Published private(set) var lastScore: DrivingScore?

    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private var timer: Timer?
    private var startDate: Date?
    private var previousLocation: CLLocation?
    private var lastCourse: CLLocationDirection?
    private var distanceMeters: CLLocationDistance = 0
    private var topSpeed: CLLocationSpeed = 0
    private var events: [DrivingEvent] = []
    private var lastEventAt: [DrivingEventKind: Date] = [:]

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

        lastScore = DrivingScore(
            score: makeScore(duration: duration),
            duration: duration,
            distanceMeters: distanceMeters,
            topSpeedMetersPerSecond: topSpeed,
            events: events,
            motionSamples: motionSamples
        )
        statusMessage = motionSamples == 0
            ? "No motion samples received — try a physical iPhone."
            : "Drive saved on this device"
    }

    private func resetCurrentDrive() {
        elapsed = 0
        currentSpeedMetersPerSecond = 0
        motionSamples = 0
        previousLocation = nil
        lastCourse = nil
        distanceMeters = 0
        topSpeed = 0
        events = []
        lastEventAt = [:]
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
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion, self.isRecording else { return }
            self.record(motion: motion)
        }
    }

    private func record(motion: CMDeviceMotion) {
        motionSamples += 1

        // `userAcceleration` removes gravity. A large horizontal spike normally
        // means the phone moved abruptly; it is kept separate from GPS-derived
        // braking/acceleration so we do not overstate confidence.
        let acceleration = motion.userAcceleration
        let horizontalG = hypot(acceleration.x, acceleration.y)
        if horizontalG >= 0.48 {
            addEvent(.phoneMovement, cooldown: 3)
        }
    }

    private func record(location: CLLocation) {
        guard location.horizontalAccuracy >= 0 else { return }
        let speed = max(location.speed, 0)
        currentSpeedMetersPerSecond = speed
        topSpeed = max(topSpeed, speed)

        if let previousLocation {
            let time = location.timestamp.timeIntervalSince(previousLocation.timestamp)
            if time > 0.35, time < 10 {
                distanceMeters += location.distance(from: previousLocation)
                let acceleration = (speed - max(previousLocation.speed, 0)) / time
                if acceleration <= -3.2 {
                    addEvent(.hardBrake, cooldown: 4)
                } else if acceleration >= 2.8 {
                    addEvent(.rapidAcceleration, cooldown: 4)
                }

                if speed >= 5, location.course >= 0, let lastCourse {
                    let courseChange = abs(normalizedAngle(location.course - lastCourse))
                    if courseChange / time >= 28 {
                        addEvent(.sharpCorner, cooldown: 5)
                    }
                }
            }
        }

        previousLocation = location
        if location.course >= 0 { lastCourse = location.course }
    }

    private func normalizedAngle(_ degrees: CLLocationDirection) -> CLLocationDirection {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped > 180 ? wrapped - 360 : (wrapped < -180 ? wrapped + 360 : wrapped)
    }

    private func addEvent(_ kind: DrivingEventKind, cooldown: TimeInterval) {
        let now = Date()
        if let lastEvent = lastEventAt[kind], now.timeIntervalSince(lastEvent) < cooldown { return }
        lastEventAt[kind] = now
        events.append(DrivingEvent(kind: kind, timestamp: now))
    }

    private func makeScore(duration: TimeInterval) -> Int {
        let penalties = events.reduce(into: 0) { total, event in
            switch event.kind {
            case .hardBrake:
                total += 8
            case .rapidAcceleration:
                total += 6
            case .sharpCorner:
                total += 6
            case .phoneMovement:
                total += 3
            }
        }
        // A very short recording is deliberately conservative: it has too little
        // context to claim a high-confidence driving assessment.
        let shortDrivePenalty = duration < 60 ? 8 : 0
        return max(20, min(100, 100 - penalties - shortDrivePenalty))
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
