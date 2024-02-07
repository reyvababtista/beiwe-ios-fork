import Darwin
import Foundation
import PromiseKit

/// For some unfathomable, incomprehensible reason, this logic was attached to the GpsManager
// It may be the case that the GPS updates are how the app stays open (there is disabled logic to record when the app vas opened that checks
// for the presense of some location service *stuff* over in AppEventManager), in which case my best guess for that old, _terrible_ factoring
// is that Keary thought he would need to hook everything into those GPS details.

/// this class is not a data recording class, it is a manager for the timers that run on the app as a whole.
class TimerManager {
    // state
    var dataCollectionServices: [DataServiceStatus] = []
    var areServicesRunning = false
    
    // timer stuff () the app ~only keeps track of the next timer event to occur, and updates it accordingly.  (I don't know why it is spread across 2 variables.)
    var timer: Timer = Timer()
    var nextSurveyUpdate: Date = Date(timeIntervalSince1970: 0)
    var nextDataServicesCheck: Date = Date(timeIntervalSince1970: 0)
    var nextHeartbeat: Date = Date(timeIntervalSince1970: 0)
    
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
        // print("TimerManager.start()")
        self.areServicesRunning = true
        self.startPollTimer(1.5)  // this value is purely to differentiate from a +1.0 seconds value for clarity when debugging.
    }
    
    /// stops timers for everything
    func stop() {
        self.areServicesRunning = false
        self.clearPollTimer()
        // call finishCollecting on every collection service in dataCollectionServices
        for dataStatus in self.dataCollectionServices {
            dataStatus.dataService.finishCollecting()
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
    func runDataCollectionServicesToggleLogic() -> Date {
        // print("ToggleLogic")
        // get time at start of call
        let now = Date().timeIntervalSince1970
        var next_toggle_check = now + (10 * 60)  // default is a ten minute timer
        
        if now > self.nextHeartbeat.timeIntervalSince1970 {
            StudyManager.sharedInstance.heartbeat("Timer logic")
            self.nextHeartbeat = Date(timeIntervalSince1970: now + Constants.HEARTBEAT_INTERVAL)
        }
        
        // for every data service get its nextToggleTime, turn it on or off as appropriate,
        // set state as appropriate, update nextToggleTime.
        for dataStatus in self.dataCollectionServices {
            // print("ToggleLogic - timer check for \(dataStatus.dataService)")
            
            // 1 - get the toggle time from the DataServiceStatus - this value is set to current time at initialization, e.g. it always starts "in the past".
            if var toggleTime = dataStatus.nextToggleTime?.timeIntervalSince1970 {
                // print("ToggleLogic - \(dataStatus.dataService) - toggletime: \(smartformat(toggleTime))")
                
                // 2 - if that time is in the past, toggle.
                if toggleTime <= now {
                    // print("ToggleLogic - \(dataStatus.dataService) - was in the past, time to toggle.")
                    
                    // 2a - toggle off if on, update .nextToggleTime
                    if dataStatus.currentlyOn {
                        // print("ToggleLogic - \(dataStatus.dataService) - it was on, toggling off.")
                        dataStatus.dataService.pauseCollecting()
                        dataStatus.currentlyOn = false
                        dataStatus.nextToggleTime = Date(timeIntervalSince1970: now + dataStatus.offDurationSeconds)
                        // print("ToggleLogic - \(dataStatus.dataService) - next toggle time: \(smartformat(dataStatus.nextToggleTime!.timeIntervalSince1970))")
                        
                    // 2b - toggle on if off, update .nextToggleTime
                    } else {
                        // print("ToggleLogic - \(dataStatus.dataService) - it was off, toggling on.")
                        dataStatus.dataService.startCollecting()
                        dataStatus.currentlyOn = true
                        
                        // If there is no off time, we run forever... (some things don't need to be turned off?)
                        if dataStatus.offDurationSeconds == 0 {
                            dataStatus.nextToggleTime = nil
                            // print("ToggleLogic - \(dataStatus.dataService) - no off time, runs forever.")
                        } else {
                            dataStatus.nextToggleTime = Date(timeIntervalSince1970: now + dataStatus.onDurationSeconds)
                            // print("ToggleLogic - \(dataStatus.dataService) - next toggle time: \(smartformat(dataStatus.nextToggleTime!.timeIntervalSince1970))")
                        }
                    }
                    
                    // update local variable from nextToggleTime because it may have changed
                    toggleTime = dataStatus.nextToggleTime?.timeIntervalSince1970 ?? Double.greatestFiniteMagnitude
                }
                
                // As we iterate over all the DataServiceStatuses we look for the soonest event time to trigger
                if toggleTime < next_toggle_check {
                    next_toggle_check = toggleTime
                    // print("ToggleLogic - next_toggle_check set to \(smartformat(next_toggle_check))")
                }
            }
            // print("")
        }
        // print("=========== next_toggle_check determined to be \(smartformat(next_toggle_check)) (in \(next_toggle_check - now) seconds) ==========")
        return Date(timeIntervalSince1970: next_toggle_check)
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
        self.nextDataServicesCheck = self.runDataCollectionServicesToggleLogic()
        
        let now = Date() // from before the network tasks execute
        
        // conditionally runs any network operations, handles reachability
        StudyManager.sharedInstance.periodicNetworkTransfers()

        // run update survey logic
        // FIXME: this logic provides an incorrect timestamp, or at least it assumes that the correct time to set is for one week from now, hardcoded.
        if self.nextSurveyUpdate < now {
            StudyManager.sharedInstance.updateActiveSurveys()
            // this is just the survey update timer 10 minutes is excessively short so is probably fine, I think.
            self.nextSurveyUpdate = ten_minutes_from_now()
        }
        
        // update timer
        self.setTheNextPolltimer()
    }

    func ten_minutes_from_now() -> Date {
        // this is a placeholder?
        return Date(timeIntervalSince1970: Date().timeIntervalSince1970 + (10 * 60))  // I guess the default is a ten minute timer?
    }
    
    /// set timer for the next survey update event? - called only from StudyManager
    // func resetNextSurveyUpdate(_ time: Double) {
    //     self.nextSurveyUpdate = time
    //     if self.nextSurveyUpdate < self.nextDataServicesCheck {
    //         self.setTheNextPolltimer()
    //     }
    // }

    /// set a timer
    func setTheNextPolltimer() {
        let now_seconds = Date().timeIntervalSince1970
        let nextSurveyUpdate_seconds = self.nextSurveyUpdate.timeIntervalSince1970
        let nextDataServicesCheck_seconds = self.nextDataServicesCheck.timeIntervalSince1970
        // get whichever is soonest, get the number of seconds between then and now.
        let next_seconds = min(nextSurveyUpdate_seconds, nextDataServicesCheck_seconds) - now_seconds
        // print("now: \(smartformat(now_seconds))")
        // print("nextSurveyUpdate: \(smartformat(self.nextSurveyUpdate)), (\(nextSurveyUpdate_seconds - now_seconds) seconds)")
        // print("nextServicesCheck: \(smartformat(self.nextDataServicesCheck)), (\(nextDataServicesCheck_seconds - now_seconds) seconds)")
        // print("self.nextSettingsUpdate: \(self.nextSettingsUpdate), \(now - self.nextSettingsUpdate)")
        self.startPollTimer(next_seconds)
    }

    /// start the poll timer - called in start (1.5 seconds), and in setTheNextPolltimer.
    func startPollTimer(_ seconds: Double) {
        self.clearPollTimer()
        self.timer = Timer.scheduledTimer(
            timeInterval: seconds, target: self, selector: #selector(self.pollServices), userInfo: nil, repeats: false
        )
        // print("Timer set for: \(seconds)")
        AppEventManager.sharedInstance.logAppEvent(event: "set_timer", msg: "Set timer for \(seconds) seconds", d1: String(seconds))
    }
}
