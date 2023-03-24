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
    // csv data stream headers
    static let headers = ["timestamp", "latitude", "longitude", "altitude", "accuracy"]

    // Location
    let locationManager = CLLocationManager()
    var lastLocations: [CLLocation]?

    // settings
    var enableGpsFuzzing: Bool = false
    var fuzzGpsLatitudeOffset: Double = 0.0
    var fuzzGpsLongitudeOffset: Double = 0.0

    // State
    var isCollectingGps: Bool = false
    var areServicesRunning = false
    var isDeferringUpdates = false

    // gps storage
    var gpsStore: DataStorage?

    // timers.... what? why is thiis
    var timer: Timer?
    var nextSurveyUpdate: TimeInterval = 0
    var nextServiceDate: TimeInterval = 0

    // um, insanity? (this is where all the data services, e.g. sensors/code-that-defines-data-streams, are stuck)
    var dataCollectionServices: [DataServiceStatus] = []

    /// checks gps permission - IDE warning about UI unresponsiveness appears to never be an issue.
    func gpsAllowed() -> Bool {
        return CLLocationManager.locationServicesEnabled() && CLLocationManager.authorizationStatus() == .authorizedAlways
    }

    /// starts GPS stuff
    func startGpsAndTimer() {
        self.locationManager.delegate = self // assigns this instance of the class as the gps delegate class
        self.locationManager.activityType = CLActivityType.other // most permissive I think
        self.locationManager.allowsBackgroundLocationUpdates = true // does not require app be in foreground
        self.locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers // loose accuracy?
        self.locationManager.distanceFilter = 99999 // value in meters - "Pass in kCLDistanceFilterNone to be notified of all movements"
        self.locationManager.requestAlwaysAuthorization()
        self.locationManager.pausesLocationUpdatesAutomatically = false

        // start!
        self.locationManager.startUpdatingLocation()
        self.locationManager.startMonitoringSignificantLocationChanges()

        // well this has been sitting here for over 7 years as not-the-first-line of the function, so let's leave it?
        if !self.gpsAllowed() {
            return
        }

        // app state
        self.areServicesRunning = true
        self.startPollTimer(1.0)
    }

    /// stops _all_ data services, including the gps data, but only non-gps stuff is done in a promise. 🙄
    func stopAndClear() -> Promise<Void> {
        let globalQueue = DispatchQueue.global(qos: .default)
        
        // disable location updates, clear poll timer, update state
        self.locationManager.stopUpdatingLocation()
        self.areServicesRunning = false
        self.clearPollTimer()
        var promise = Promise()
        
        // call finishCollecting on every collection service in dataCollectionServices
        for dataStatus in self.dataCollectionServices {
            // use .done because not returning anything - wutchutalkinbout Tuck, we return an empty promise!
            promise = promise.done(on: globalQueue) { _ in
                dataStatus.handler.finishCollecting().then(on: globalQueue) { _ -> Promise<Void> in  // need to explicitly state return type
                    print("Returned from finishCollecting")
                    return Promise()
                }.catch(on: DispatchQueue.global(qos: .default)) { _ in
                    print("err from finish collecting")
                }
            }
        }
        // clear out the data services entirely
        self.dataCollectionServices.removeAll()
        return promise
    }

    /// Starts or stops every data service, returns the time interval until the next event.
    /// called in self.pollServices
    func dispatchToServices() -> TimeInterval {
        // get time at start of call
        let currentDate = Date().timeIntervalSince1970
        var nextServiceDate = currentDate + (60 * 60)

        // for every data service get its nextToggleTime, turn it on or off as appropriate,
        // set state as appropriate, update nextToggleTime.
        for dataStatus in self.dataCollectionServices {
            if let nextToggleTime = dataStatus.nextToggleTime {
                var serviceDate = nextToggleTime.timeIntervalSince1970
                if serviceDate <= currentDate {
                    if dataStatus.currentlyOn {
                        dataStatus.handler.pauseCollecting() // stops recording
                        dataStatus.currentlyOn = false
                        dataStatus.nextToggleTime = Date(timeIntervalSince1970: currentDate + dataStatus.offDurationSeconds)
                    } else {
                        dataStatus.handler.startCollecting() // start recording
                        dataStatus.currentlyOn = true
                        // If there is no off time, we run forever...
                        if dataStatus.offDurationSeconds == 0 {
                            dataStatus.nextToggleTime = nil
                        } else {
                            dataStatus.nextToggleTime = Date(timeIntervalSince1970: currentDate + dataStatus.onDurationSeconds)
                        }
                    }
                    serviceDate = dataStatus.nextToggleTime?.timeIntervalSince1970 ?? DBL_MAX
                }
                // nextServiceDate to soonest of nextServiceDate, serviceDate
                nextServiceDate = min(nextServiceDate, serviceDate)
            }
        }
        return nextServiceDate
    }

    ///
    /// Timers
    ///
    
    /// runs StudyManaager.periodicNetworkTransfers, sets next survey update, starts another timer.
    @objc func pollServices() {
        log.info("Polling...")
        self.clearPollTimer() // purpose unclear?
        AppEventManager.sharedInstance.logAppEvent(event: "poll_service", msg: "Polling service") // probably pointless
        // return early if services are not renning
        if !self.areServicesRunning {
            return
        }

        /// set the next service date (its a timeInterval object) to the next event time
        self.nextServiceDate = self.dispatchToServices()
        let currentTime = Date().timeIntervalSince1970 // from before the network tasks execute
        StudyManager.sharedInstance.periodicNetworkTransfers()

        // run update survey logic
        if currentTime > self.nextSurveyUpdate {
            self.nextSurveyUpdate = StudyManager.sharedInstance.updateActiveSurveys()
        }
        self.setTimerForService()
    }

    /// set timer for the next survey update event? - called only from StudyManager
    func resetNextSurveyUpdate(_ time: Double) {
        self.nextSurveyUpdate = time
        if self.nextSurveyUpdate < self.nextServiceDate {
            self.setTimerForService()
        }
    }

    /// set a timer
    func setTimerForService() {
        self.nextServiceDate = min(self.nextSurveyUpdate, self.nextServiceDate)
        let currentTime = Date().timeIntervalSince1970
        let nextServiceSeconds = max(nextServiceDate - currentTime, 1.0)
        self.startPollTimer(nextServiceSeconds)
    }

    // The poll timer is started in startGpsAndTimer at 1 second, and used in setTimerForService
    /// start the poll timer?
    func startPollTimer(_ seconds: Double) {
        self.clearPollTimer()
        self.timer = Timer.scheduledTimer(timeInterval: seconds, target: self, selector: #selector(self.pollServices), userInfo: nil, repeats: false)
        log.info("Timer set for: \(seconds)")
        AppEventManager.sharedInstance.logAppEvent(event: "set_timer", msg: "Set timer for \(seconds) seconds", d1: String(seconds))
    }

    /// clear a poll timer safely
    func clearPollTimer() {
        if let timer = timer {
            timer.invalidate()
            self.timer = nil
        }
    }

    //
    // GPS datapoints
    //

    /// records a single location datapoint but safely - this is an overridden function afaik
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if !self.areServicesRunning {
            return
        }
    
        if self.isCollectingGps {
            self.recordGpsData(manager, locations: locations)
        }
    }

    /// sets self.isDeferringUpdates to false? literally never called... (part of a superclass)
    func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?) {
        self.isDeferringUpdates = false
    }

    /// records a single line of data to the gps csv, implements gps fuzzing
    func recordGpsData(_ manager: CLLocationManager, locations: [CLLocation]) {
        // print("Record locations: \(locations)")
        for loc in locations {
            var data: [String] = []

            // static let headers = [ "timestamp", "latitude", "longitude", "altitude", "accuracy", "vert_accuracy"]
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

    /// a core function that enables many sensor managers (DataServiceProtocols)
    func addDataService(on_duration: Int, off_duration: Int, handler: DataServiceProtocol) {
        let dataServiceStatus = DataServiceStatus(
            onDurationSeconds: on_duration, offDurationSeconds: off_duration, handler: handler
        )
        if handler.initCollecting() {
            self.dataCollectionServices.append(dataServiceStatus)
        }
    }

    /// a core function that enables the other half of the data services (data streams)
    func addDataService(_ handler: DataServiceProtocol) {
        self.addDataService(on_duration: 1, off_duration: 0, handler: handler)
    }

    /* Data service protocol */

    /// init collecting
    func initCollecting() -> Bool {
        guard self.gpsAllowed() else {
            log.error("GPS not enabled.  Not initializing collection")
            return false
        }
        self.gpsStore = DataStorageManager.sharedInstance.createStore("gps", headers: GPSManager.headers)
        self.isCollectingGps = false
        return true
    }

    /// start collecting
    func startCollecting() {
        log.info("Turning GPS collection on")
        AppEventManager.sharedInstance.logAppEvent(event: "gps_on", msg: "GPS collection on")
        self.isCollectingGps = true
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager.distanceFilter = kCLDistanceFilterNone
    }

    /// stop collecting
    func pauseCollecting() {
        log.info("Pausing GPS collection")
        AppEventManager.sharedInstance.logAppEvent(event: "gps_off", msg: "GPS collection off")
        self.isCollectingGps = false
        self.locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        self.locationManager.distanceFilter = 99999
    }

    /// only called in self.stopAndClear
    func finishCollecting() -> Promise<Void> {
        self.pauseCollecting()
        self.isCollectingGps = false
        self.gpsStore = nil
        return DataStorageManager.sharedInstance.closeStore("gps")
    }
}
