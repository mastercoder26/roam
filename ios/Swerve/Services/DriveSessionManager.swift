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
    @Published private(set) var recordedDrives: [RecordedDrive] = []
    @Published private(set) var queuedPracticeRoute: PlannedRouteContext?
    /// A distinct presentation event for the root view. The queued context
    /// remains available until the driver explicitly starts or cancels it.
    @Published private(set) var practiceRoutePresentationRequest: UUID?

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
    private var routePoints: [DriveRoutePoint] = []
    private var latestCoordinate: DriveCoordinate?
    private var activePracticeRoute: PlannedRouteContext?
    // The encoded route is deliberately memory-only. Saved drives receive the
    // privacy-safe context plus a local overlap result, never an address,
    // polyline, or other planned-route geometry.
    private var queuedPracticeRoutePolyline: String?
    private var activePracticeRoutePolyline: String?
    private let historyKey = "recorded-drives-v1"

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .automotiveNavigation
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5
        locationManager.pausesLocationUpdatesAutomatically = false
        loadRecordedDrives()
    }

    func startDrive() {
        guard !isRecording else { return }

        // Copy the context into the recording before removing it from the
        // pre-drive queue. Starting remains entirely manual; this only tags
        // the resulting local record after the driver chooses to begin.
        activePracticeRoute = queuedPracticeRoute
        activePracticeRoutePolyline = queuedPracticeRoutePolyline
        queuedPracticeRoute = nil
        queuedPracticeRoutePolyline = nil
        resetCurrentDrive()
        isRecording = true
        startDate = Date()
        statusMessage = "Recording this drive"
        startElapsedTimer()
        startMotionUpdates()

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways:
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.startUpdatingLocation()
        case .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
            // A manual drive should keep recording after the user locks the
            // phone. iOS presents the additional permission only after the
            // user has already started a drive.
            locationManager.requestAlwaysAuthorization()
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
        locationManager.allowsBackgroundLocationUpdates = false
        currentSpeedMetersPerSecond = 0

        let result = DriveScoringEngine.score(
            duration: duration,
            distanceMeters: distanceMeters,
            events: events,
            acceptedLocationSamples: acceptedLocationSamples,
            rejectedLocationSamples: rejectedLocationSamples,
            motionSamples: motionSamples
        )
        let score = DrivingScore(
            score: result.score,
            duration: duration,
            distanceMeters: distanceMeters,
            topSpeedMetersPerSecond: topSpeed,
            events: events,
            motionSamples: motionSamples,
            dataQuality: result.quality
        )
        lastScore = score
        let persistedPracticeRoute = activePracticeRoute.map { context in
            let routeMatched = activePracticeRoutePolyline.map {
                DriverReadinessEngine.matchesPlannedPracticeRoute(
                    plannedPolyline: $0,
                    recordedRoute: routePoints
                )
            } ?? false
            return PlannedRouteContext(
                id: context.id,
                createdAt: context.createdAt,
                routeDemands: context.routeDemands,
                recordedRouteMatched: routeMatched
            )
        }
        let practiceRouteWasVerified = persistedPracticeRoute?.recordedRouteMatched
        let drive = RecordedDrive(
            startedAt: startDate ?? Date(),
            score: score,
            route: routePoints,
            plannedRouteContext: persistedPracticeRoute
        )
        recordedDrives.insert(drive, at: 0)
        // Keep storage bounded while retaining a useful recent history.
        recordedDrives = Array(recordedDrives.prefix(50))
        saveRecordedDrives()
        if motionSamples == 0 {
            statusMessage = "No motion samples received — try a physical iPhone."
        } else if practiceRouteWasVerified == true {
            statusMessage = "Drive saved — planned-route overlap verified on this device"
        } else if practiceRouteWasVerified == false {
            statusMessage = "Drive saved — planned-route overlap could not be verified from GPS"
        } else {
            statusMessage = "Drive saved on this device"
        }
        activePracticeRoute = nil
        activePracticeRoutePolyline = nil
    }

    /// Queues a locally generated route context for the next manually started
    /// drive. The route geometry stays in memory solely to verify GPS overlap
    /// when the drive ends; this deliberately never calls `startDrive()`.
    func queuePlannedPracticeRoute(_ route: ScoredRoute) {
        guard !isRecording else { return }
        queuedPracticeRoute = PlannedRouteContext(routeDemands: route.routeDemands ?? [])
        queuedPracticeRoutePolyline = route.polyline
        practiceRoutePresentationRequest = UUID()
    }

    /// Cancels a pre-drive route tag without affecting any saved drive.
    func clearPlannedPracticeRoute() {
        guard !isRecording else { return }
        queuedPracticeRoute = nil
        queuedPracticeRoutePolyline = nil
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
        routePoints = []
        latestCoordinate = nil
    }

    private func startElapsedTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let startDate = self.startDate else { return }
                self.elapsed = Date().timeIntervalSince(startDate)
            }
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
            addEvent(.phoneMovement, timestamp: Date(), coordinate: latestCoordinate, source: .deviceMotion, cooldown: 3)
        }
    }

    private func record(location: CLLocation) {
        let sample = DriveLocationSample(
            timestamp: location.timestamp,
            speedMetersPerSecond: location.speed,
            courseDegrees: location.course >= 0 ? location.course : nil,
            courseAccuracyDegrees: location.courseAccuracy >= 0 ? location.courseAccuracy : nil,
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
        let routePoint = DriveRoutePoint(timestamp: location.timestamp, coordinate: DriveCoordinate(location.coordinate), speedMetersPerSecond: speed)

        if let previousLocation {
            let time = location.timestamp.timeIntervalSince(previousLocation.timestamp)
            if time >= DriveScoringEngine.minimumSampleGap, time <= DriveScoringEngine.maximumSampleGap {
                let previousSample = DriveLocationSample(
                    timestamp: previousLocation.timestamp,
                    speedMetersPerSecond: previousLocation.speed,
                    courseDegrees: previousLocation.course >= 0 ? previousLocation.course : nil,
                    courseAccuracyDegrees: previousLocation.courseAccuracy >= 0 ? previousLocation.courseAccuracy : nil,
                    horizontalAccuracyMeters: previousLocation.horizontalAccuracy
                )
                let distance = location.distance(from: previousLocation)
                guard DriveScoringEngine.isPlausibleTransition(
                    previous: previousSample,
                    current: sample,
                    distanceMeters: distance
                ) else {
                    rejectedLocationSamples += 1
                    return
                }
                distanceMeters += distance
                appendRoutePoint(routePoint)
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
                    addEvent(event.kind, timestamp: location.timestamp, coordinate: routePoint.coordinate, source: event.source, cooldown: cooldown)
                }
            } else if time > DriveScoringEngine.maximumSampleGap {
                // Resume the route after a long background gap without drawing
                // a synthetic straight line or deriving a false acceleration.
                appendRoutePoint(routePoint)
            }
        } else {
            appendRoutePoint(routePoint)
        }

        previousLocation = location
        latestCoordinate = routePoint.coordinate
    }

    private func appendRoutePoint(_ point: DriveRoutePoint) {
        // One point per ~5 m from CLLocation plus a time-based escape hatch is
        // enough to draw a faithful route without unbounded storage.
        if let last = routePoints.last,
           point.timestamp.timeIntervalSince(last.timestamp) < 1,
           CLLocation(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
                .distance(from: CLLocation(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude)) < 5 {
            return
        }
        routePoints.append(point)
    }

    private func addEvent(_ kind: DrivingEventKind, timestamp: Date, coordinate: DriveCoordinate?, source: DrivingEventSource, cooldown: TimeInterval) {
        if let lastEvent = lastEventAt[kind], timestamp.timeIntervalSince(lastEvent) < cooldown { return }
        lastEventAt[kind] = timestamp
        events.append(DrivingEvent(kind: kind, timestamp: timestamp, source: source, coordinate: coordinate))
    }

    private func loadRecordedDrives() {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else { return }
        recordedDrives = (try? JSONDecoder().decode([RecordedDrive].self, from: data)) ?? []
    }

    private func saveRecordedDrives() {
        guard let data = try? JSONEncoder().encode(recordedDrives) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }
}

extension DriveSessionManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self, self.isRecording else { return }
            switch manager.authorizationStatus {
            case .authorizedAlways:
                manager.allowsBackgroundLocationUpdates = true
                manager.startUpdatingLocation()
                self.statusMessage = "Recording this drive"
            case .authorizedWhenInUse:
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

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard self?.isRecording == true else { return }
            self?.statusMessage = "Location update failed — motion recording continues"
        }
    }
}
