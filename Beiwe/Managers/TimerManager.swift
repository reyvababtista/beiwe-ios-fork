import Darwin
import Foundation
import PromiseKit

/// For some unfathomable, incomprehensible reason, this logic was attached to the GpsManager
// It may be the case that the GPS updates are how the app stays open (there is disabled logic to record when the app vas opened that checks
// for the presense of some location service *stuff* over in AppEventManager), in which case my best guess for that old, _terrible_ factoring
// is that Keary thought he would need to hook everything into those GPS details.

/// this class is not a data recording class, it is a manager for the timers that run on the app as a whole.
class TimerManager {
    // a queue for potentially long running
    let globalQueue = DispatchQueue.global(qos: .default)
    
    // state
    var dataCollectionServices: [DataServiceStatus] = []
    var areServicesRunning = false
    
    // timer stuff () the app ~only keeps track of the next timer event to occur, and updates it accordingly.  (I don't know why it is spread across 2 variables.)
    var timer: Timer = Timer()
    var nextSurveyUpdate: TimeInterval = 0
    var nextServiceDate: TimeInterval = 0
    var nextSettingsUpdate: TimeInterval = 0
    
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
    
    ///
    /// Timer control
    ///
    
    /// enables the timer
    func start() {
        self.areServicesRunning = true
        self.startPollTimer(1.0)
    }
    
    /// stops timers for everything
    func stop() {
        self.areServicesRunning = false
        self.clearPollTimer()
        var promise = Promise()  // there is No Way that these operations take time, this use of a promise architecture is garbage.
        
        // call finishCollecting on every collection service in dataCollectionServices
        for dataStatus in self.dataCollectionServices {
            // use .done because not returning anything - wutchutalkinbout Tuck, we return an empty promise!
            promise = promise.done(on: globalQueue) { (_: ()) in  // this is a very stupid type declaration, _ is an unused Void-returning callable that takes no arguments.
                dataStatus.handler.finishCollecting().then(on: self.globalQueue) { (_: Void) -> Promise<Void> in  // need to explicitly state return type
                    return Promise()
                }.catch(on: DispatchQueue.global(qos: .default)) { _ in
                    print("err from finish collecting")
                }
            }
        }
        
        self.dataCollectionServices.removeAll()  // clear out the registered services entirely
    }
    
    /// used in unregistering
    func clear() {
        self.dataCollectionServices = []
    }
    
    /// clear a poll timer safely
    func clearPollTimer() {
        self.timer.invalidate()
        self.timer = Timer()  // clear out the old timer object, make a new one
    }
    
    /// Starts or stops every data service, returns the time interval until the next event.
    /// called in self.pollServices, which assigns to self
    func dispatchToServices() -> TimeInterval {
        // get time at start of call
        let now = Date().timeIntervalSince1970
        var nextServiceDate = now + (60 * 60)

        // for every data service get its nextToggleTime, turn it on or off as appropriate,
        // set state as appropriate, update nextToggleTime.
        for dataStatus in self.dataCollectionServices {
            if let nextToggleTime = dataStatus.nextToggleTime {
                var serviceDate = nextToggleTime.timeIntervalSince1970
                if serviceDate <= now {
                    if dataStatus.currentlyOn {
                        dataStatus.handler.pauseCollecting() // stops recording
                        dataStatus.currentlyOn = false
                        dataStatus.nextToggleTime = Date(timeIntervalSince1970: now + dataStatus.offDurationSeconds)
                    } else {
                        dataStatus.handler.startCollecting() // start recording
                        dataStatus.currentlyOn = true
                        // If there is no off time, we run forever...
                        if dataStatus.offDurationSeconds == 0 {
                            dataStatus.nextToggleTime = nil
                        } else {
                            dataStatus.nextToggleTime = Date(timeIntervalSince1970: now + dataStatus.onDurationSeconds)
                        }
                    }
                    serviceDate = dataStatus.nextToggleTime?.timeIntervalSince1970 ?? Double.greatestFiniteMagnitude
                }
                // As we iterate over all the DataServiceStatuses we look for the soonest event time to trigger
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
        // log.info("Polling...")
        self.clearPollTimer()
        AppEventManager.sharedInstance.logAppEvent(event: "poll_service", msg: "Polling service") // probably pointless
        // return early if services should not be running
        if !self.areServicesRunning {
            return
        }

        /// set the next service date (its a timeInterval object) to the next event time
        self.nextServiceDate = self.dispatchToServices()
        let now = Date().timeIntervalSince1970 // from before the network tasks execute
        
        // conditionally runs any network operations, handles reachability
        StudyManager.sharedInstance.periodicNetworkTransfers()

        // run update survey logic
        if now > self.nextSurveyUpdate {
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
        let now = Date().timeIntervalSince1970
        // next time minus current time = the time interval until target moment; at least 1 second tho.e
        let nextServiceSeconds = max(nextServiceDate - now, 1.0)
        self.startPollTimer(nextServiceSeconds)
    }

    // called in start (1 second), and in setTimerForService ()
    /// start the poll timer?
    func startPollTimer(_ seconds: Double) {
        self.clearPollTimer()
        self.timer = Timer.scheduledTimer(timeInterval: seconds, target: self, selector: #selector(self.pollServices), userInfo: nil, repeats: false)
        log.info("Timer set for: \(seconds)")
        AppEventManager.sharedInstance.logAppEvent(event: "set_timer", msg: "Set timer for \(seconds) seconds", d1: String(seconds))
    }
}
