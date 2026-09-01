import Testing
@testable import Liminalog

struct CalendarTabCacheRefreshPolicyTests {
    @Test
    func loadsVisibleRangeImmediatelyWhenNoPageDataHasBeenBuilt() {
        #expect(CalendarTabCacheRefreshPolicy.plan(
            hasCachedPageData: false,
            loadedContentRevision: nil,
            currentContentRevision: 0,
            requiresExternalRefresh: false
        ) == .immediateVisibleRange)
    }

    @Test
    func refreshesOnlyCurrentMonthAfterPresentationWhenRevisionIsUnchanged() {
        #expect(CalendarTabCacheRefreshPolicy.plan(
            hasCachedPageData: true,
            loadedContentRevision: 12,
            currentContentRevision: 12,
            requiresExternalRefresh: false
        ) == .deferredCurrentMonth)
    }

    @Test
    func refreshesVisibleRangeAfterPresentationWhenTimelineContentChanged() {
        #expect(CalendarTabCacheRefreshPolicy.plan(
            hasCachedPageData: true,
            loadedContentRevision: 12,
            currentContentRevision: 13,
            requiresExternalRefresh: false
        ) == .deferredVisibleRange)
    }

    @Test
    func refreshesVisibleRangeAfterPresentationForExternalChange() {
        #expect(CalendarTabCacheRefreshPolicy.plan(
            hasCachedPageData: true,
            loadedContentRevision: 12,
            currentContentRevision: 12,
            requiresExternalRefresh: true
        ) == .deferredVisibleRange)
    }
}
