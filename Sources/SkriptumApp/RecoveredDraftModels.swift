import Foundation
#if canImport(SkriptumCore)
import SkriptumCore
#endif

typealias RecoveredDraft = RecoveryRecord<WritingPage>
extension RecoveryRecord where Value == WritingPage {
    var page: WritingPage { value }
}
