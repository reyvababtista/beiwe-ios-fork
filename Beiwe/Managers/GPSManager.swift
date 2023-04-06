import CoreLocation
import Darwin
import Foundation
import PromiseKit

let gps_headers = [
    "timestamp",
    "latitude",
    "longitude",
    "altitude",
    "accuracy",
]

/// The GPS Manager.  Note that GPS is a critical component of the app being able to stay persistent
class GPSManager: NSObject, CLLocationManagerDelegate, DataServiceProtocol {
    // Location
    let locationManager = CLLocationManager()
    var lastLocations: [CLLocation]?

    // settings
    var enableGpsFuzzing: Bool = false
    var fuzzGpsLatitudeOffset: Double = 0.0
    var fuzzGpsLongitudeOffset: Double = 0.0

    // State
    var isCollectingGps: Bool = false
    var isDeferringUpdates = false  // this doesn't seem to do anything in this subclass of CLLocationManagerDelegate, and also isn't part of the superclass.  unclear purpose.

    // gps storage
    var gpsStore: DataStorage?

    /// checks gps permission - IDE warning about UI unresponsiveness appears to never be an issue.
    func gpsAllowed() -> Bool {
        return CLLocationManager.locationServicesEnabled() && CLLocationManager.authorizationStatus() == .authorizedAlways
    }

    /// starts GPS
    func startGps() {
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
    }
    
    /// stops the location manager from receiving updates
    func stopGps() {
        self.locationManager.stopUpdatingLocation()
    }
 
    /// this misnamed function records a single location datapoint but safely - this is an overridden function afaik
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if self.isCollectingGps && StudyManager.sharedInstance.timerManager.areServicesRunning {
            self.recordGpsData(manager, locations: locations)
        }
    }

    /// this misnamed function sets self.isDeferringUpdates to false? literally never called... (part of a superclass)
    func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?) {
        self.isDeferringUpdates = false
    }

    /// records a single line of data to the gps csv, implements gps fuzzing
    func recordGpsData(_ manager: CLLocationManager, locations: [CLLocation]) {
        // print("Record locations: \(locations)")
        for loc in locations {
            var data: [String] = []
            var lat = loc.coordinate.latitude
            var lng = loc.coordinate.longitude
            if self.enableGpsFuzzing {
                lat = lat + self.fuzzGpsLatitudeOffset
                lng = ((lng + self.fuzzGpsLongitudeOffset + 180.0).truncatingRemainder(dividingBy: 360.0)) - 180.0
            }
            // header order is timestamp, latitude, longitude, altitude, accuracy, vert_accuracy
            data.append(String(Int64(loc.timestamp.timeIntervalSince1970 * 1000)))
            data.append(String(lat))
            data.append(String(lng))
            data.append(String(loc.altitude))
            data.append(String(loc.horizontalAccuracy))
            self.gpsStore?.store(data)
        }
    }

    /* Data service protocol */

    /// init collecting
    func initCollecting() -> Bool {
        guard self.gpsAllowed() else {
            log.error("GPS not enabled.  Not initializing collection")
            return false
        }
        self.gpsStore = DataStorageManager.sharedInstance.createStore("gps", headers: gps_headers)
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
