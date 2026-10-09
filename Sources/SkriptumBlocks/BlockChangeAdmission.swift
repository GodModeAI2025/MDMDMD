import Foundation
#if canImport(SkriptumCore)
import SkriptumCore
#endif

enum BlockChangeAdmission {
    static func acceptsMarkdown(event: String, current: String) -> Bool { event.utf8.elementsEqual(current.utf8) }
    static func acceptsBlocks(event: [Block], canonical: [Block]?) -> Bool {
        guard let canonical else { return true }
        return event.count == canonical.count && zip(event, canonical).allSatisfy { $0.id == $1.id && $0.markdown.utf8.elementsEqual($1.markdown.utf8) }
    }
}
