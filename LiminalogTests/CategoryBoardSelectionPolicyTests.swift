import Foundation
import Testing
@testable import Liminalog

@Suite("Category board selection policy")
struct CategoryBoardSelectionPolicyTests {
    @Test("A valid persisted board restores as the visible selection")
    func validPersistedBoardRestores() {
        let first = UUID()
        let persisted = UUID()

        let restoration = CategoryBoardSelectionPolicy.restore(
            storedID: persisted,
            availableIDs: [first, persisted]
        )

        #expect(restoration.selectedID == persisted)
    }

    @Test("A missing or stale persisted board selects the first available fallback")
    func staleSelectionUsesFallback() {
        let fallback = UUID()
        let stale = UUID()
        let restoration = CategoryBoardSelectionPolicy.restore(
            storedID: stale,
            availableIDs: [fallback, UUID()]
        )

        #expect(restoration.selectedID == fallback)
    }

    @Test("Only a settled board different from the last commit is eligible")
    func repeatedSelectionIsIgnoredButReturningLaterCommits() throws {
        let first = UUID()
        let second = UUID()

        #expect(CategoryBoardSelectionPolicy.commitCandidate(
            selectedID: first,
            lastCommittedID: first
        ) == nil)

        let secondCommit = try #require(CategoryBoardSelectionPolicy.commitCandidate(
            selectedID: second,
            lastCommittedID: first
        ))
        #expect(secondCommit == second)
        #expect(CategoryBoardSelectionPolicy.commitCandidate(
            selectedID: first,
            lastCommittedID: secondCommit
        ) == first)
    }

    @Test("No board never requests an external commit")
    func emptyBoardListDoesNotCommit() {
        let restoration = CategoryBoardSelectionPolicy.restore(
            storedID: UUID(),
            availableIDs: []
        )

        #expect(restoration.selectedID == nil)
        #expect(CategoryBoardSelectionPolicy.commitCandidate(
            selectedID: restoration.selectedID,
            lastCommittedID: nil
        ) == nil)
    }

    @Test("A cached ID suppresses republishing only when its external snapshot matches")
    func publishedCacheMustBeConsistent() {
        let selected = UUID()

        #expect(CategoryBoardSelectionPolicy.validatedPublishedID(
            cachedID: selected,
            snapshotID: selected
        ) == selected)
        #expect(CategoryBoardSelectionPolicy.validatedPublishedID(
            cachedID: selected,
            snapshotID: nil
        ) == nil)
        #expect(CategoryBoardSelectionPolicy.validatedPublishedID(
            cachedID: selected,
            snapshotID: UUID()
        ) == nil)
    }

    @Test("Rapid intermediate pages collapse to one settled external commit")
    @MainActor
    func rapidSelectionsCommitOnlyTheLatest() async throws {
        let first = UUID()
        let intermediate = UUID()
        let settled = UUID()
        let scheduler = CategoryBoardSelectionScheduler(
            lastCommittedID: first,
            delayNanoseconds: 10_000_000
        )
        var appliedIDs: [UUID] = []

        scheduler.schedule(intermediate) { id in
            appliedIDs.append(id)
            return true
        }
        scheduler.schedule(settled) { id in
            appliedIDs.append(id)
            return true
        }

        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(appliedIDs == [settled])

        scheduler.schedule(settled) { id in
            appliedIDs.append(id)
            return true
        }
        try await Task.sleep(nanoseconds: 80_000_000)
        #expect(appliedIDs == [settled])
    }

    @Test("A failed external commit remains retryable")
    @MainActor
    func failedCommitCanRetry() async throws {
        let initial = UUID()
        let selected = UUID()
        let scheduler = CategoryBoardSelectionScheduler(
            lastCommittedID: initial,
            delayNanoseconds: 20_000_000
        )
        var attempts = 0

        scheduler.schedule(selected) { _ in
            attempts += 1
            return false
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        scheduler.schedule(selected) { _ in
            attempts += 1
            return true
        }
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(attempts == 2)
        #expect(scheduler.lastCommittedID == selected)
    }
}
