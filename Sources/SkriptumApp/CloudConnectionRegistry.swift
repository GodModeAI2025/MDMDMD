import Foundation
#if canImport(SkriptumCore)
import SkriptumCore
#endif

/// These errors concern local metadata lifecycle, never authenticated server rights.
enum CloudConnectionRegistryError: Error, Equatable { case invalidCapacity, capacity, invalidated, staleTicket, wrongScope, bindingConflict }

@MainActor final class CloudConnectionHandle {
    let locator: OwnedLibraryLocator
    fileprivate let registryID: UUID
    fileprivate let incarnation: UUID
    fileprivate let generation: UUID
    fileprivate let value: CloudLibraryBinding
    fileprivate init(registryID: UUID, incarnation: UUID, generation: UUID, value: CloudLibraryBinding) {
        self.registryID = registryID; self.incarnation = incarnation; self.generation = generation
        self.value = value; locator = value.locator
    }
}

struct CloudConnectionTicket: Sendable {
    fileprivate let id: UUID
    fileprivate let registryID: UUID
    fileprivate let incarnation: UUID
    fileprivate let generation: UUID
    fileprivate let value: CloudLibraryBinding
    fileprivate let expected: CloudLibraryBinding?
    fileprivate init(registryID: UUID, incarnation: UUID, generation: UUID, value: CloudLibraryBinding, expected: CloudLibraryBinding?) {
        id = UUID(); self.registryID = registryID; self.incarnation = incarnation
        self.generation = generation; self.value = value; self.expected = expected
    }
}

/// Validated nonsecret binding selection only. It owns no client or credential,
/// performs no network operation and never means logged-in cloud admission.
@MainActor final class CloudConnectionRegistry {
    private final class Slot {
        let incarnation = UUID()
        var generation = UUID()
        var binding: CloudLibraryBinding?
        var invalidated = false
        weak var handle: CloudConnectionHandle?
        var pending: [UUID: CloudConnectionTicket] = [:]
    }
    private let registryID = UUID()
    private let capacity: Int
    private var slots: [OwnedLibraryLocator: Slot] = [:]
    init(capacity: Int = 64) throws {
        guard (1...64).contains(capacity) else { throw CloudConnectionRegistryError.invalidCapacity }
        self.capacity = capacity
    }
    private func prune() {
        // Retained old tickets cannot match a recreated slot's new incarnation.
        // Retiring metadata never restores a credential or server authorization.
        slots = slots.filter { $0.value.handle != nil || !$0.value.pending.isEmpty }
    }
    private func slot(for locator: OwnedLibraryLocator) throws -> Slot {
        prune()
        if let slot = slots[locator] { return slot }
        guard slots.count < capacity else { throw CloudConnectionRegistryError.capacity }
        let slot = Slot(); slots[locator] = slot; return slot
    }
    private func handle(for value: CloudLibraryBinding, slot: Slot) -> CloudConnectionHandle {
        if let existing = slot.handle, existing.generation == slot.generation, existing.value == value { return existing }
        let handle = CloudConnectionHandle(registryID: registryID, incarnation: slot.incarnation, generation: slot.generation, value: value)
        slot.handle = handle; return handle
    }
    /// Explicit cold metadata read only, using its exact owned locator.
    func restore(_ repository: CloudLibraryBindingRepository) throws -> CloudConnectionHandle? {
        prune()
        if slots[repository.locator]?.invalidated == true { throw CloudConnectionRegistryError.invalidated }
        guard let value = try repository.load() else { return nil }
        try value.validate()
        guard value.locator == repository.locator else { throw CloudConnectionRegistryError.wrongScope }
        let slot = try slot(for: repository.locator)
        guard slot.binding == nil || slot.binding == value else { throw CloudConnectionRegistryError.bindingConflict }
        slot.binding = value
        return handle(for: value, slot: slot)
    }
    func binding(for handle: CloudConnectionHandle) throws -> CloudLibraryBinding {
        guard handle.registryID == registryID, let slot = slots[handle.locator],
              slot.incarnation == handle.incarnation, slot.generation == handle.generation,
              !slot.invalidated, slot.binding == handle.value else { throw CloudConnectionRegistryError.invalidated }
        return handle.value
    }
    /// Caller must independently obtain authenticated remote readback. This
    /// ticket does not authenticate or create a connection by itself.
    func begin(_ value: CloudLibraryBinding, replacing expected: CloudLibraryBinding?) throws -> CloudConnectionTicket {
        try value.validate()
        if let expected {
            try expected.validate()
            guard expected.locator == value.locator else { throw CloudConnectionRegistryError.wrongScope }
        }
        prune()
        guard slots.values.reduce(0, { $0 + $1.pending.count }) < capacity else { throw CloudConnectionRegistryError.capacity }
        let slot = try slot(for: value.locator)
        guard slot.binding == nil || slot.binding == expected else { throw CloudConnectionRegistryError.bindingConflict }
        let ticket = CloudConnectionTicket(registryID: registryID, incarnation: slot.incarnation, generation: slot.generation, value: value, expected: expected)
        slot.pending[ticket.id] = ticket
        return ticket
    }
    func complete(_ ticket: CloudConnectionTicket, repository: CloudLibraryBindingRepository) throws -> CloudConnectionHandle {
        guard ticket.registryID == registryID, let slot = slots[ticket.value.locator],
              slot.incarnation == ticket.incarnation, slot.generation == ticket.generation,
              slot.pending[ticket.id] != nil else { throw CloudConnectionRegistryError.staleTicket }
        guard repository.locator == ticket.value.locator else { throw CloudConnectionRegistryError.wrongScope }
        // Synchronous MainActor transaction: invalidation cannot interleave with
        // verification, authoritative disk CAS and metadata publication.
        try repository.save(ticket.value, replacing: ticket.expected)
        slot.pending.removeValue(forKey: ticket.id)
        if slot.invalidated || (slot.binding != nil && slot.binding != ticket.value) {
            slot.generation = UUID(); slot.pending.removeAll()
        }
        slot.invalidated = false; slot.binding = ticket.value
        return handle(for: ticket.value, slot: slot)
    }
    func cancel(_ ticket: CloudConnectionTicket) {
        guard ticket.registryID == registryID, let slot = slots[ticket.value.locator], slot.incarnation == ticket.incarnation else { return }
        slot.pending.removeValue(forKey: ticket.id)
        prune()
    }
    func invalidate(_ locator: OwnedLibraryLocator) {
        guard let slot = slots[locator] else { return }
        slot.generation = UUID(); slot.invalidated = true; slot.pending.removeAll()
        // Keep weak reference until scenes release it, so those handles remain
        // visibly revoked; no unbounded strong cache or tombstone retention.
    }
    /// Synchronous local fencing only; later Keychain/server work is separate.
    @discardableResult func invalidateAll(origin: String, profileID: String, accountID: UUID) -> [OwnedLibraryLocator] {
        var matched: [OwnedLibraryLocator] = []
        for (locator, slot) in slots {
            let matches: (CloudLibraryBinding) -> Bool = {
                $0.origin.utf8.elementsEqual(origin.utf8) && $0.profileID.utf8.elementsEqual(profileID.utf8) && $0.accountID == accountID
            }
            if slot.binding.map(matches) == true {
                invalidate(locator); matched.append(locator)
            } else {
                let ids = slot.pending.filter { matches($0.value.value) }.keys
                if !ids.isEmpty {
                    for id in ids { slot.pending.removeValue(forKey: id) }
                    matched.append(locator)
                }
            }
        }
        return matched
    }
}
