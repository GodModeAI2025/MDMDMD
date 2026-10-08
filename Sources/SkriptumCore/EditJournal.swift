import Foundation

struct EditJournal: Codable {
    var token: UUID
    var baseline: Page
    var current: Page
}
