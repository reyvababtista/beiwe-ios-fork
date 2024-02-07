// common protocol used by Managers
protocol DataServiceProtocol {
    func initCollecting() -> Bool
    func startCollecting()
    func pauseCollecting()
    func finishCollecting()
}

// defined class that is only used in TimerManager
class DataServiceStatus {
    let onDurationSeconds: Double
    let offDurationSeconds: Double
    var currentlyOn: Bool
    var nextToggleTime: Date? // don't think this needs to be optional, probably would need to replace with 0?
    let dataService: DataServiceProtocol

    init(onDurationSeconds: Int, offDurationSeconds: Int, dataService: DataServiceProtocol) {
        self.onDurationSeconds = Double(onDurationSeconds)
        self.offDurationSeconds = Double(offDurationSeconds)
        self.dataService = dataService
        self.currentlyOn = false
        self.nextToggleTime = Date()
    }
}
