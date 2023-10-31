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
    var nextServicesCheck: TimeInterval = 0
    
    /// a core function that enables many sensor managers (DataServiceProtocols)
    func addDataService(on_duration: Int, off_duration: Int, dataService: DataServiceProtocol) {
        let dataServiceStatus = DataServiceStatus(
            onDurationSeconds: on_duration, offDurationSeconds: off_duration, dataService: dataService
        )
        if dataService.initCollecting() {
            self.dataCollectionServices.append(dataServiceStatus)
        }
    }
    
    /// a core function that enables the other half of the data services (data streams with no timers)
    func addDataService(_ dataService: DataServiceProtocol) {
        self.addDataService(on_duration: 1, off_duration: 0, dataService: dataService)
    }
    
    ///
    /// Timer control
    ///
    
    /// enables the timer
    func start() {
        self.areServicesRunning = true
        self.startPollTimer(1.5)  // this value is purely to differentiate from a +1.0 seconds value for clarity in debugging purposes.
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
                dataStatus.dataService.finishCollecting().then(on: self.globalQueue) { (_: Void) -> Promise<Void> in  // need to explicitly state return type
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
        var returned_next_service_check = now + (10 * 60)  // default is a ten minute timer
        
        // for every data service get its nextToggleTime, turn it on or off as appropriate,
        // set state as appropriate, update nextToggleTime.
        for dataStatus in self.dataCollectionServices {
            if var possible_time = dataStatus.nextToggleTime?.timeIntervalSince1970 {  // get toggle time
                if possible_time <= now {  // if its in the past, toggle!
                    if dataStatus.currentlyOn {  // toggle it off
                        dataStatus.dataService.pauseCollecting()
                        dataStatus.currentlyOn = false
                        dataStatus.nextToggleTime = Date(timeIntervalSince1970: now + dataStatus.offDurationSeconds)
                    } else {  // toggle it on
                        dataStatus.dataService.startCollecting()
                        dataStatus.currentlyOn = true
                        // If there is no off time, we run forever... (some things don't need to be turned off?)
                        if dataStatus.offDurationSeconds == 0 {
                            dataStatus.nextToggleTime = nil
                        } else {
                            dataStatus.nextToggleTime = Date(timeIntervalSince1970: now + dataStatus.onDurationSeconds)
                        }
                    }
                    // get that toggle time again (it might have changed)
                    possible_time = dataStatus.nextToggleTime?.timeIntervalSince1970 ?? Double.greatestFiniteMagnitude
                }
                // As we iterate over all the DataServiceStatuses we look for the soonest event time to trigger
                returned_next_service_check = min(returned_next_service_check, possible_time)
            }
        }
        return returned_next_service_check
    }

    ///
    /// Timers
    ///
    
    /// runs StudyManaager.periodicNetworkTransfers, sets next survey update, starts another timer.
    @objc func pollServices() {

        self.clearPollTimer()
        AppEventManager.sharedInstance.logAppEvent(event: "poll_service", msg: "Polling service") // probably pointless
        
        // return early if services are not running (should not be running)
        if !self.areServicesRunning {
            return
        }

        /// set the next service date (its a timeInterval object) to the next event time
        self.nextServicesCheck = self.runDataCollectionServicesToggleLogic()
        let now = Date().timeIntervalSince1970 // from before the network tasks execute
        
        // conditionally runs any network operations, handles reachability
        StudyManager.sharedInstance.periodicNetworkTransfers()

        // run update survey logic
        // FIXME: this logic provides an incorrect timestamp, or at least it assumes that the correct time to set is for one week from now, hardcoded.
        if now > self.nextSurveyUpdate {
            StudyManager.sharedInstance.updateActiveSurveys()
            // this is just the survey update timer 10 minutes is excessively short so is probably fine, I think.
            self.nextSurveyUpdate = ten_minutes_from_now()
        }
        
        // update timer
        self.setNextPolltimer()
    }

    func ten_minutes_from_now() -> TimeInterval {
        // this is a placeholder?
        return Date().timeIntervalSince1970 + (10 * 60)  // I guess the default is a ten minute timer?
    }
    
    /// set timer for the next survey update event? - called only from StudyManager
    func resetNextSurveyUpdate(_ time: Double) {
        self.nextSurveyUpdate = time
        if self.nextSurveyUpdate < self.nextServicesCheck {
            self.setNextPolltimer()
        }
    }

    /// set a timer
    func setNextPolltimer() {
        self.nextServicesCheck = min(self.nextSurveyUpdate, self.nextServicesCheck)
        
        let now = Date().timeIntervalSince1970
        // next time minus current time = the time interval until target moment; at least 1 second to be safe
        let nextServiceCheckSafe = max(self.nextServicesCheck - now, 1.0)
        // print("now: \(now)")
        // print("self.nextSurveyUpdate: \(self.nextSurveyUpdate), \(now - self.nextSurveyUpdate)")
        // print("self.nextServicesCheck: \(self.nextServicesCheck), \(now - self.nextServicesCheck)")
        // print("self.nextSettingsUpdate: \(self.nextSettingsUpdate), \(now - self.nextSettingsUpdate)")
        self.startPollTimer(nextServiceCheckSafe)
    }

    /// start the poll timer - called in start (1.5 seconds), and in setNextPolltimer.
    func startPollTimer(_ seconds: Double) {
        self.clearPollTimer()
        self.timer = Timer.scheduledTimer(timeInterval: seconds, target: self, selector: #selector(self.pollServices), userInfo: nil, repeats: false)
        // print("Timer set for: \(seconds)")
        AppEventManager.sharedInstance.logAppEvent(event: "set_timer", msg: "Set timer for \(seconds) seconds", d1: String(seconds))
    }
}
