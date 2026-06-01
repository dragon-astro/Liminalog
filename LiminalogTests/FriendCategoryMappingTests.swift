import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
struct FriendCategoryMappingTests {
    @Test
    func modelAllowsMultipleMyCategoriesToMapToOneFriendCategory() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let friend = Friend(displayName: "Mika", status: .accepted)
        let study = Category(name: "勉強", colorHex: "#2F80ED", icon: "book.fill")
        let english = Category(name: "英語", colorHex: "#2F80ED", icon: "text.book.closed.fill")
        let friendCategoryID = UUID()

        context.insert(friend)
        context.insert(study)
        context.insert(english)
        context.insert(FriendCategoryMapping(friend: friend, myCategoryID: study.id, friendCategoryID: friendCategoryID))
        context.insert(FriendCategoryMapping(friend: friend, myCategoryID: english.id, friendCategoryID: friendCategoryID))
        try context.save()

        let mappings = try context.fetch(FetchDescriptor<FriendCategoryMapping>())

        #expect(mappings.count == 2)
        #expect(Set(mappings.map(\.myCategoryID)) == [study.id, english.id])
        #expect(Set(mappings.map(\.friendCategoryID)) == [friendCategoryID])
        #expect(mappings.map(\.useUnifiedColor) == [true, true])
    }

    @Test
    func sharedSnapshotsExposeCategoryDescriptorsWhenCategoryIDIsPresent() {
        let calendar = Calendar.japanese
        let start = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!
        let studyID = UUID()
        let restID = UUID()
        let plan = FriendSharedPlanSnapshot(
            categoryID: studyID,
            title: "ゼミ",
            startTime: start,
            endTime: calendar.date(byAdding: .hour, value: 1, to: start)!,
            categoryTitle: "勉強",
            categoryIconName: "book.fill",
            categoryColorHex: "#2F80ED"
        )
        let redactedPlan = FriendSharedPlanSnapshot(
            title: "予定あり",
            startTime: start,
            endTime: calendar.date(byAdding: .hour, value: 1, to: start)!,
            categoryTitle: "",
            categoryIconName: "calendar",
            categoryColorHex: "#8E8E93"
        )
        let activity = FriendSharedActivitySnapshot(
            categoryID: restID,
            title: "休憩",
            startTime: start,
            endTime: calendar.date(byAdding: .hour, value: 1, to: start)!,
            categoryTitle: "休憩",
            categoryIconName: "cup.and.saucer.fill",
            categoryColorHex: "#27AE60"
        )

        let descriptors = FriendCategoryMappingResolver.descriptors(
            plans: [redactedPlan, plan],
            activities: [activity]
        )

        #expect(Set(descriptors.map(\.id)) == Set([studyID, restID]))
        #expect(Set(descriptors.map(\.title)) == Set(["勉強", "休憩"]))
    }

    @Test
    func defaultMappingsMatchOnlyDefaultCategoriesByNameAndRespectExistingMappings() {
        let friend = Friend(displayName: "Mika", status: .accepted)
        let study = Category(name: "勉強", colorHex: "#2F80ED", icon: "book.fill", isDefault: true)
        let rest = Category(name: "休憩", colorHex: "#27AE60", icon: "cup.and.saucer.fill", isDefault: true)
        let custom = Category(name: "英語", colorHex: "#2F80ED", icon: "text.book.closed.fill", isDefault: false)
        let remoteStudyID = UUID()
        let remoteRestID = UUID()
        let remoteEnglishID = UUID()
        let existingRestMapping = FriendCategoryMapping(
            friend: friend,
            myCategoryID: rest.id,
            friendCategoryID: remoteRestID,
            useUnifiedColor: false
        )

        let mappings = FriendCategoryMappingResolver.defaultMappings(
            friend: friend,
            myCategories: [custom, rest, study],
            friendCategories: [
                FriendSharedCategoryDescriptor(id: remoteEnglishID, title: "英語"),
                FriendSharedCategoryDescriptor(id: remoteStudyID, title: "勉強"),
                FriendSharedCategoryDescriptor(id: remoteRestID, title: "休憩")
            ],
            existingMappings: [existingRestMapping]
        )

        #expect(mappings.count == 1)
        #expect(mappings[0].friend === friend)
        #expect(mappings[0].myCategoryID == study.id)
        #expect(mappings[0].friendCategoryID == remoteStudyID)
        #expect(mappings[0].useUnifiedColor)
    }
}
