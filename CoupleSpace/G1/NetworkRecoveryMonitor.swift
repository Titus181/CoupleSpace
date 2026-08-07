import Combine
import Network

enum NetworkReachabilityState: Equatable {
    case unknown
    case unavailable
    case available
}

struct NetworkRecoveryTriggerPolicy {
    static func shouldRecover(
        previous: NetworkReachabilityState,
        current: NetworkReachabilityState
    ) -> Bool {
        previous == .unavailable && current == .available
    }
}

@MainActor
final class NetworkRecoveryMonitor: ObservableObject {
    @Published private(set) var state: NetworkReachabilityState = .unknown

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.titus.CoupleSpace.w1-network-recovery")
    private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            let nextState: NetworkReachabilityState = path.status == .satisfied
                ? .available
                : .unavailable
            Task { @MainActor [weak self] in
                self?.state = nextState
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
