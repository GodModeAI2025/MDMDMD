import Foundation

public enum AttachmentAudit {
    /// Root is the caller's owning LibraryStore.directory, never a destination
    /// parsed from Markdown. Work is sequential and each validated payload is
    /// discarded before the next file (existing maximum32MiB/raster limits).
    public static func inspect(libraryID: UUID, snapshot: LibrarySnapshot, mediaRoot: URL) async throws -> AttachmentInventory {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            guard mediaRoot.isFileURL else { throw LibraryError.invalidAttachment }
            let inventory = try AttachmentInventory(libraryID: libraryID, snapshot: snapshot, checkingCancellation: true)
            var statuses: [UUID: AttachmentStorageStatus] = [:]
            for entry in inventory.entries {
                try Task.checkCancellation()
                guard entry.storageStatus == .notChecked, let metadata = entry.metadata else { continue }
                do {
                    _ = try MediaValidation.read(metadata, root: mediaRoot)
                    statuses[entry.id] = .verified
                } catch {
                    let validationFailed = (error as? LibraryError) == .invalidAttachment
                    let error = error as NSError
                    let missing = (error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code))
                        || (error.domain == NSPOSIXErrorDomain && error.code == 2)
                    if validationFailed {
                        statuses[entry.id] = .invalidFile
                    } else {
                        statuses[entry.id] = missing ? .missingFile : .unavailableFile
                    }
                }
                try Task.checkCancellation()
            }
            try Task.checkCancellation()
            return inventory.applyingStatuses(statuses)
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: { worker.cancel() }
    }
}
