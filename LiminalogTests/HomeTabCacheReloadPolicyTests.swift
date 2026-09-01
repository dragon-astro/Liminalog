import Testing
@testable import Liminalog

@Suite("Home tab cache reload policy")
struct HomeTabCacheReloadPolicyTests {
    @Test("初回表示は再取得する")
    func firstPresentationReloads() {
        #expect(HomeTabCacheReloadPolicy.shouldReload(
            loadedContentRevision: nil,
            currentContentRevision: 3,
            loadedExternalRefreshRevision: 0,
            currentExternalRefreshRevision: 0
        ))
    }

    @Test("同じデータ版の再表示は再取得しない")
    func warmPresentationReusesCache() {
        #expect(!HomeTabCacheReloadPolicy.shouldReload(
            loadedContentRevision: 3,
            currentContentRevision: 3,
            loadedExternalRefreshRevision: 2,
            currentExternalRefreshRevision: 2
        ))
    }

    @Test("ローカル更新後は再取得する")
    func localRevisionReloads() {
        #expect(HomeTabCacheReloadPolicy.shouldReload(
            loadedContentRevision: 3,
            currentContentRevision: 4,
            loadedExternalRefreshRevision: 2,
            currentExternalRefreshRevision: 2
        ))
    }

    @Test("Cloud更新後は再取得する")
    func remoteRevisionReloads() {
        #expect(HomeTabCacheReloadPolicy.shouldReload(
            loadedContentRevision: 3,
            currentContentRevision: 3,
            loadedExternalRefreshRevision: 2,
            currentExternalRefreshRevision: 3
        ))
    }
}
