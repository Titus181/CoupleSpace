import Foundation

struct AppLaunchOptions: Equatable {
    static let uiTestingArgument = "--ui-testing"
    static let pairingUITestingArgument = "--ui-testing-pairing"
    static let formalUnpairingUITestingArgument = "--ui-testing-formal-unpairing"

    let isUITesting: Bool
    let isPairingUITesting: Bool
    let isFormalUnpairingUITesting: Bool

    init(arguments: [String]) {
        isUITesting = arguments.contains(Self.uiTestingArgument)
        isPairingUITesting = arguments.contains(Self.pairingUITestingArgument)
        isFormalUnpairingUITesting = arguments.contains(Self.formalUnpairingUITestingArgument)
    }

    static var current: AppLaunchOptions {
        AppLaunchOptions(arguments: ProcessInfo.processInfo.arguments)
    }
}
