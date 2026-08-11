import Foundation

struct AppLaunchOptions: Equatable {
    static let uiTestingArgument = "--ui-testing"

    let isUITesting: Bool

    init(arguments: [String]) {
        isUITesting = arguments.contains(Self.uiTestingArgument)
    }

    static var current: AppLaunchOptions {
        AppLaunchOptions(arguments: ProcessInfo.processInfo.arguments)
    }
}
