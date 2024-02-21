// common protocol used by Managers
protocol DataServiceProtocol {
    func initCollecting() -> Bool
    func startCollecting()
    func pauseCollecting()
    func finishCollecting()
    func createNewFile()
    
    // Only some data streams benefit from collecting writes and flushing them, each
    // data service is expected to handle this manually. (Was factored into data storage itself,
    // it was really bad and would lose data.) Classes need to explain themselves.
    func flush()
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
