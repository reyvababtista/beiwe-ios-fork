import PromiseKit

// common protocol used by Managers
protocol DataServiceProtocol {
    func initCollecting() -> Bool
    func startCollecting()
    func pauseCollecting()
    func finishCollecting() -> Promise<Void>
}

// defined class that is only used in TimerManager
class DataServiceStatus {
    let onDurationSeconds: Double
    let offDurationSeconds: Double
    var currentlyOn: Bool
    var nextToggleTime: Date?
    let dataService: DataServiceProtocol

    init(onDurationSeconds: Int, offDurationSeconds: Int, handler: DataServiceProtocol) {
        self.onDurationSeconds = Double(onDurationSeconds)
        self.offDurationSeconds = Double(offDurationSeconds)
        self.dataService = handler
        self.currentlyOn = false
        self.nextToggleTime = Date()
    }
}
