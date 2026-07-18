import Foundation

struct CategoryBoardSelectionPolicy {
    struct Restoration: Equatable {
        let selectedID: UUID?
    }

    static func restore(
        storedID: UUID?,
        availableIDs: [UUID]
    ) -> Restoration {
        guard !availableIDs.isEmpty else {
            return Restoration(selectedID: nil)
        }

        if let storedID, availableIDs.contains(storedID) {
            return Restoration(selectedID: storedID)
        }

        return Restoration(selectedID: availableIDs[0])
    }

    static func commitCandidate(
        selectedID: UUID?,
        lastCommittedID: UUID?
    ) -> UUID? {
        guard let selectedID, selectedID != lastCommittedID else { return nil }
        return selectedID
    }

    static func validatedPublishedID(
        cachedID: UUID?,
        snapshotID: UUID?
    ) -> UUID? {
        guard cachedID == snapshotID else { return nil }
        return cachedID
    }
}

@MainActor
final class CategoryBoardSelectionScheduler {
    private let delayNanoseconds: UInt64
    private var pendingTask: Task<Void, Never>?
    private(set) var lastCommittedID: UUID?

    init(
        lastCommittedID: UUID?,
        delayNanoseconds: UInt64 = 350_000_000
    ) {
        self.lastCommittedID = lastCommittedID
        self.delayNanoseconds = delayNanoseconds
    }

    func schedule(
        _ selectedID: UUID?,
        apply: @escaping @MainActor (UUID) -> Bool
    ) {
        pendingTask?.cancel()
        guard let candidate = CategoryBoardSelectionPolicy.commitCandidate(
            selectedID: selectedID,
            lastCommittedID: lastCommittedID
        ) else {
            pendingTask = nil
            return
        }

        pendingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.delayNanoseconds)
            guard !Task.isCancelled else { return }
            guard apply(candidate) else { return }
            lastCommittedID = candidate
            pendingTask = nil
        }
    }
}
