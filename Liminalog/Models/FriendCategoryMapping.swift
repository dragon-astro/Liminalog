import Foundation
import SwiftData

@Model
final class FriendCategoryMapping {
    var id: UUID = UUID()
    @Relationship(deleteRule: .nullify)
    var friend: Friend?
    var myCategoryID: UUID = UUID()
    var friendCategoryID: UUID = UUID()
    var useUnifiedColor: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}

    init(
        friend: Friend? = nil,
        myCategoryID: UUID,
        friendCategoryID: UUID,
        useUnifiedColor: Bool = true,
        now: Date = Date()
    ) {
        self.id = UUID()
        self.friend = friend
        self.myCategoryID = myCategoryID
        self.friendCategoryID = friendCategoryID
        self.useUnifiedColor = useUnifiedColor
        self.createdAt = now
        self.updatedAt = now
    }
}

struct FriendSharedCategoryDescriptor: Hashable {
    var id: UUID
    var title: String
    var iconName: String
    var colorHex: String

    init(id: UUID, title: String, iconName: String = "", colorHex: String = "") {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.colorHex = colorHex
    }
}

enum FriendCategoryMappingResolver {
    static func descriptors(
        plans: [FriendSharedPlanSnapshot],
        activities: [FriendSharedActivitySnapshot]
    ) -> [FriendSharedCategoryDescriptor] {
        var descriptorsByID: [UUID: FriendSharedCategoryDescriptor] = [:]

        for plan in plans {
            guard let categoryID = plan.categoryID,
                  !plan.categoryTitle.isEmpty
            else { continue }
            descriptorsByID[categoryID] = FriendSharedCategoryDescriptor(
                id: categoryID,
                title: plan.categoryTitle,
                iconName: plan.categoryIconName,
                colorHex: plan.categoryColorHex
            )
        }

        for activity in activities {
            guard let categoryID = activity.categoryID else { continue }
            descriptorsByID[categoryID] = FriendSharedCategoryDescriptor(
                id: categoryID,
                title: activity.categoryTitle,
                iconName: activity.categoryIconName,
                colorHex: activity.categoryColorHex
            )
        }

        return descriptorsByID.values.sorted {
            let left = normalizedCategoryName($0.title)
            let right = normalizedCategoryName($1.title)
            if left == right {
                return $0.id.uuidString < $1.id.uuidString
            }
            return left < right
        }
    }

    static func defaultMappings(
        friend: Friend?,
        myCategories: [Category],
        friendCategories: [FriendSharedCategoryDescriptor],
        existingMappings: [FriendCategoryMapping] = [],
        now: Date = Date()
    ) -> [FriendCategoryMapping] {
        let defaultMyCategoriesByName = myCategories
            .filter(\.isDefault)
            .reduce(into: [String: Category]()) { categoriesByName, category in
                categoriesByName[normalizedCategoryName(category.name), default: category] = category
            }
        var mappedMyCategoryIDs = Set(existingMappings.map(\.myCategoryID))
        var mappedFriendCategoryIDs = Set(existingMappings.map(\.friendCategoryID))
        var mappings: [FriendCategoryMapping] = []

        for friendCategory in friendCategories {
            guard let myCategory = defaultMyCategoriesByName[normalizedCategoryName(friendCategory.title)],
                  !mappedMyCategoryIDs.contains(myCategory.id),
                  !mappedFriendCategoryIDs.contains(friendCategory.id)
            else { continue }

            mappings.append(
                FriendCategoryMapping(
                    friend: friend,
                    myCategoryID: myCategory.id,
                    friendCategoryID: friendCategory.id,
                    useUnifiedColor: true,
                    now: now
                )
            )
            mappedMyCategoryIDs.insert(myCategory.id)
            mappedFriendCategoryIDs.insert(friendCategory.id)
        }

        return mappings
    }

    private static func normalizedCategoryName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}
