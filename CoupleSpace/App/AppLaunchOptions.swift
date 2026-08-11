import Foundation

struct AppLaunchOptions: Equatable {
    static let uiTestingArgument = "--ui-testing"
    static let pairingUITestingArgument = "--ui-testing-pairing"

    let isUITesting: Bool
    let isPairingUITesting: Bool

    init(arguments: [String]) {
        isUITesting = arguments.contains(Self.uiTestingArgument)
        isPairingUITesting = arguments.contains(Self.pairingUITestingArgument)
    }

    static var current: AppLaunchOptions {
        AppLaunchOptions(arguments: ProcessInfo.processInfo.arguments)
    }
}
