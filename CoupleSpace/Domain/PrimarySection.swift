import Foundation

enum PrimarySection: String, CaseIterable, Hashable {
    case today
    case conversation
    case us

    static let defaultSelection = PrimarySection.today
}
