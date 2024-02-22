import BackgroundTasks

func scheduleRefreshHeartbeat() {
    print("scheduling refresh heartbeat")
    let request = BGAppRefreshTaskRequest(identifier: BACKGROUND_TASK_NAME_HEARTBEAT_BGREFRESH)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 10)
    do {
        try BGTaskScheduler.shared.submit(request)
    } catch {
        // fatalError("Could not schedule app refresh: \(error)")
    }
}

func scheduleProcessingHeartbeat() {
    print("scheduling processing heartbeat")
    let request = BGProcessingTaskRequest(identifier: BACKGROUND_TASK_NAME_HEARTBEAT_BGPROCESSING)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 10)
    request.requiresExternalPower = false
    request.requiresNetworkConnectivity = true
    do {
        try BGTaskScheduler.shared.submit(request)
    } catch {
        // fatalError("Could not schedule app processing: \(error)")
    }
}

@available(iOS 17.0, *)
func scheduleHealthHeartbeat() {
    print("scheduling health heartbeat")
    let request = BGHealthResearchTaskRequest(identifier: BACKGROUND_TASK_NAME_HEARTBEAT_BGHEALTH)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 10)
    request.requiresExternalPower = false
    request.requiresNetworkConnectivity = true
    request.protectionTypeOfRequiredData = "junk"
    do {
        try BGTaskScheduler.shared.submit(request)
    } catch {
        // fatalError("Could not schedule app health processing: \(error)")
    }
}

func scheduleAllHeartbeats() {
    scheduleRefreshHeartbeat()
    scheduleProcessingHeartbeat()
    if #available(iOS 17.0, *) {
        scheduleHealthHeartbeat()
    }
}

// Counts the outstanding background tasks (unclear if this includes any currently running background tasks.)
func countBackgroundTasks() -> String {
    var info: [String] = []
    
    BGTaskScheduler.shared.getPendingTaskRequests { (taskRequests: [BGTaskRequest]) in
        print("There are \(taskRequests.count) BGTaskRequests outstanding right now:")
        for request in taskRequests {
            if let refresh_task_request = request as? BGAppRefreshTaskRequest {
                print("\t BGAppRefreshTaskRequest - ", request.identifier, request.earliestBeginDate!)
                info.append("BGAppRefreshTaskRequest \(request.identifier):\(request.earliestBeginDate!)")
            }
            if let processing_task_request = request as? BGProcessingTaskRequest {
                print("\t BGProcessingTaskRequest - ", request.identifier, request.earliestBeginDate!,
                      "external power:", processing_task_request.requiresExternalPower,
                      "requires network:", processing_task_request.requiresNetworkConnectivity)
                info.append("BGProcessingTaskRequest \(request.identifier):\(request.earliestBeginDate!)")
            }
            // the background health tasks DO NOT SHOW UP. This is not a version-gating bug, I tested it THOROUGHLY,
            // it's either another bug or they are hidden and are not visible to the getPendingTaskRequests function.
            if #available(iOS 17.0, *) {
                if let health_task_request = request as? BGHealthResearchTaskRequest {
                    print("\t BGHealthResearchTaskRequest - ", request.identifier, request.earliestBeginDate!)
                    info.append("BGHealthResearchTaskRequest \(request.identifier):\(request.earliestBeginDate!)")
                }
            }
        }
    }
    print(info.joined(separator: ","))
    return info.joined(separator: ",")
}

func handleHeartbeatRefresh(task: BGAppRefreshTask) {
    print("BGAppRefreshTask - the handler is getting called \(dateFormatLocal(Date()))")
    StudyManager.sharedInstance.heartbeat("BGAppRefreshTask - \(countBackgroundTasks())")
    scheduleRefreshHeartbeat()
}

func handleHeartbeatProcessing(task: BGProcessingTask) {
    print("BGProcessingTask - the handler is getting called \(dateFormatLocal(Date()))")
    StudyManager.sharedInstance.heartbeat("BGProcessingTask - \(countBackgroundTasks())")
    scheduleProcessingHeartbeat()
}

@available(iOS 17.0, *)
func handleHeartbeatHealth(task: BGHealthResearchTask) {
    print("BGHealthResearchTask - the handler is getting called \(dateFormatLocal(Date()))")
    StudyManager.sharedInstance.heartbeat("BGHealthResearchTask - \(countBackgroundTasks())")
    scheduleHealthHeartbeat()
}

// /The "org.beiwe.heartbeat" target function
// func handleHeartbeatBG(task: BGHealthResearchTask) {
// func handleHeartbeatBG(task: BGAppRefreshTask) {
//     print("handleHeartbeatBG - the handler is getting called")
//     // this is the function that gets called from the "org.beiwe.heartbeat" BGTaskScheduler.shared.register closure
//     // run?
//     StudyManager.sharedInstance.heartbeat()
//     // schedule again?
//
//     scheduleHeartbeat()
//
//     // Create an operation that performs the main part of the background task.
//
//     // I guess the exception handler should... call the scheduler???
//     task.expirationHandler = {
//         // self.scheduleHeartbeat()
//         print("the task expired what the fuck?")
//         fatalError("The task expired?")
//     }
//
//     let heartbeat_operation = HeartbeatOperation()
//     let a_fucking_operation_queue = OperationQueue()
//     a_fucking_operation_queue.name = BACKGROUND_TASK_NAME_HEARTBEAT
//
//     // Inform the system that the background task is complete when the operation completes.
//     // this wants a boolean, we have no knowledge of whether sending the heartbeat worked because it is itself asynchronous?
//     heartbeat_operation.completionBlock = {
//         task.setTaskCompleted(success: !heartbeat_operation.isCancelled)
//         // we are going to explode
//         fatalError("heartbeat operation completion block or some bullshit")
//         // print("heartbeat operation completion block or some bullshit")
//     }
//
//     Start the operation.
//     a_fucking_operation_queue.addOperation(heartbeat_operation)
//
//     no examples online use the schedule queue thing
//     a_fucking_operation_queue.schedule(Date(timeIntervalSinceNow: 10))
// // }
