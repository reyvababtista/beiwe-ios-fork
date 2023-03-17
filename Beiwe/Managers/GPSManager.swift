import CoreLocation
import Darwin
import Foundation
import PromiseKit

/// For some unfathomable, incomprehensible reason, all logic for all sensors leads to the GPS manager.
// It may be the case that the GPS updates are how the app stays open (there is disabled logic to record when the app vas opened that checks
// for the presense of some location service *stuff* over in AppEventManager), in which case the best guess for this pile of CS nightmares
// is that Keary thought he would need to hook everything into those GPS details.

// TODO: what happens if GPS is disabled on a study? does that matter? we need to test that.  

class GPSManager: NSObject, CLLocationManagerDelegate, DataServiceProtocol {
    let locationManager = CLLocationManager()
    var lastLocations: [CLLocation]?
    var isCollectingGps: Bool = false
    var dataCollectionServices: [DataServiceStatus] = []
    var gpsStore: DataStorage?
    var areServicesRunning = false
    static let headers = ["timestamp", "latitude", "longitude", "altitude", "accuracy"]
    var isDeferringUpdates = false
    var nextSurveyUpdate: TimeInterval = 0, nextServiceDate: TimeInterval = 0
    var timer: Timer?
    var enableGpsFuzzing: Bool = false
    var fuzzGpsLatitudeOffset: Double = 0.0
    var fuzzGpsLongitudeOffset: Double = 0.0

    func gpsAllowed() -> Bool {
        return CLLocationManager.locationServicesEnabled() && CLLocationManager.authorizationStatus() == .authorizedAlways
    }

    func startGpsAndTimer() -> Bool {
        self.locationManager.delegate = self
        self.locationManager.activityType = CLActivityType.other
        if #available(iOS 9.0, *) {
            locationManager.allowsBackgroundLocationUpdates = true
        } else {
            // Fallback on earlier versions
        }
        self.locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        self.locationManager.distanceFilter = 99999
        self.locationManager.requestAlwaysAuthorization()
        self.locationManager.pausesLocationUpdatesAutomatically = false
        self.locationManager.startUpdatingLocation()
        self.locationManager.startMonitoringSignificantLocationChanges()

        if !self.gpsAllowed() {
            return false
        }

        self.areServicesRunning = true
        self.startPollTimer(1.0)

        return true
    }

    func stopAndClear() -> Promise<Void> {
        self.locationManager.stopUpdatingLocation()
        self.areServicesRunning = false
        self.clearPollTimer()
        var promise = Promise()
        for dataStatus in self.dataCollectionServices {
            // use .done because not returning anything
            promise = promise.done(on: DispatchQueue.global(qos: .default)) { _ in
                dataStatus.handler.finishCollecting().then(on: DispatchQueue.global(qos: .default)) {
                    // need to explicitly state return type
                    _ -> Promise<Void> in
                    print("Returned from finishCollecting")
                    return Promise()

                }.catch(on: DispatchQueue.global(qos: .default)) {
                    _ in print("err from finish collecting")
                }
            }
        }

        self.dataCollectionServices.removeAll()
        return promise
    }

    func dispatchToServices() -> TimeInterval {
        let currentDate = Date().timeIntervalSince1970
        var nextServiceDate = currentDate + (60 * 60)

        for dataStatus in self.dataCollectionServices {
            if let nextToggleTime = dataStatus.nextToggleTime {
                var serviceDate = nextToggleTime.timeIntervalSince1970
                if serviceDate <= currentDate {
                    if dataStatus.currentlyOn {
                        dataStatus.handler.pauseCollecting()
                        dataStatus.currentlyOn = false
                        dataStatus.nextToggleTime = Date(timeIntervalSince1970: currentDate + dataStatus.offDurationSeconds)
                    } else {
                        dataStatus.handler.startCollecting()
                        dataStatus.currentlyOn = true
                        /* If there is no off time, we run forever... */
                        if dataStatus.offDurationSeconds == 0 {
                            dataStatus.nextToggleTime = nil
                        } else {
                            dataStatus.nextToggleTime = Date(timeIntervalSince1970: currentDate + dataStatus.onDurationSeconds)
                        }
                    }
                    serviceDate = dataStatus.nextToggleTime?.timeIntervalSince1970 ?? DBL_MAX
                }
                nextServiceDate = min(nextServiceDate, serviceDate)
            }
        }
        return nextServiceDate
    }

    @objc func pollServices() {
        log.info("Polling...")
        self.clearPollTimer()
        AppEventManager.sharedInstance.logAppEvent(event: "poll_service", msg: "Polling service")
        if !self.areServicesRunning {
            return
        }

        self.nextServiceDate = self.dispatchToServices()

        let currentTime = Date().timeIntervalSince1970
        StudyManager.sharedInstance.periodicNetworkTransfers()

        if currentTime > self.nextSurveyUpdate {
            self.nextSurveyUpdate = StudyManager.sharedInstance.updateActiveSurveys()
        }

        self.setTimerForService()
    }

    func setTimerForService() {
        self.nextServiceDate = min(self.nextSurveyUpdate, self.nextServiceDate)
        let currentTime = Date().timeIntervalSince1970
        let nextServiceSeconds = max(nextServiceDate - currentTime, 1.0)
        self.startPollTimer(nextServiceSeconds)
    }

    func clearPollTimer() {
        if let timer = timer {
            timer.invalidate()
            self.timer = nil
        }
    }

    func resetNextSurveyUpdate(_ time: Double) {
        self.nextSurveyUpdate = time
        if self.nextSurveyUpdate < self.nextServiceDate {
            self.setTimerForService()
        }
    }

    func startPollTimer(_ seconds: Double) {
        self.clearPollTimer()
        self.timer = Timer.scheduledTimer(timeInterval: seconds, target: self, selector: #selector(self.pollServices), userInfo: nil, repeats: false)
        log.info("Timer set for: \(seconds)")
        AppEventManager.sharedInstance.logAppEvent(event: "set_timer", msg: "Set timer for \(seconds) seconds", d1: String(seconds))
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if !self.areServicesRunning {
            return
        }

        if self.isCollectingGps {
            self.recordGpsData(manager, locations: locations)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?) {
        self.isDeferringUpdates = false
    }

    func recordGpsData(_ manager: CLLocationManager, locations: [CLLocation]) {
        // print("Record locations: \(locations)");
        for loc in locations {
            var data: [String] = []

            //     static let headers = [ "timestamp", "latitude", "longitude", "altitude", "accuracy", "vert_accuracy"];
            var lat = loc.coordinate.latitude
            var lng = loc.coordinate.longitude
            if self.enableGpsFuzzing {
                lat = lat + self.fuzzGpsLatitudeOffset
                lng = ((lng + self.fuzzGpsLongitudeOffset + 180.0).truncatingRemainder(dividingBy: 360.0)) - 180.0
            }
            data.append(String(Int64(loc.timestamp.timeIntervalSince1970 * 1000)))
            data.append(String(lat))
            data.append(String(lng))
            data.append(String(loc.altitude))
            data.append(String(loc.horizontalAccuracy))
            self.gpsStore?.store(data)
        }
    }

    // the core function that enables every sensor manager (DataServiceProtocols)
    func addDataService(_ on: Int, off: Int, handler: DataServiceProtocol) {
        let dataServiceStatus = DataServiceStatus(onDurationSeconds: on, offDurationSeconds: off, handler: handler)
        if handler.initCollecting() {
            self.dataCollectionServices.append(dataServiceStatus)
        }
    }

    func addDataService(_ handler: DataServiceProtocol) {
        self.addDataService(1, off: 0, handler: handler)
    }

    /* Data service protocol */

    func initCollecting() -> Bool {
        guard self.gpsAllowed() else {
            log.error("GPS not enabled.  Not initializing collection")
            return false
        }
        self.gpsStore = DataStorageManager.sharedInstance.createStore("gps", headers: GPSManager.headers)
        self.isCollectingGps = false
        return true
    }

    func startCollecting() {
        log.info("Turning GPS collection on")
        AppEventManager.sharedInstance.logAppEvent(event: "gps_on", msg: "GPS collection on")
        self.isCollectingGps = true
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager.distanceFilter = kCLDistanceFilterNone
    }

    func pauseCollecting() {
        log.info("Pausing GPS collection")
        AppEventManager.sharedInstance.logAppEvent(event: "gps_off", msg: "GPS collection off")
        self.isCollectingGps = false
        self.locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        self.locationManager.distanceFilter = 99999
        self.gpsStore?.flush()
    }

    func finishCollecting() -> Promise<Void> {
        self.pauseCollecting()
        self.isCollectingGps = false
        self.gpsStore = nil
        return DataStorageManager.sharedInstance.closeStore("gps")
    }
}
