import UIKit
import AppTrackingTransparency
import GoogleMobileAds
import UserMessagingPlatform

/// AdMob のリワード広告。ゲームの window.QRAd.show() から呼ばれる。
/// 起動時に ①同意フォーム（EEA/英国など必要な地域のみ）②ATT（トラッキング許可）③SDK初期化 の順に行う。
@MainActor
final class AdBridge: NSObject, FullScreenContentDelegate {
    private static let testRewardedID = "ca-app-pub-3940256099942544/1712485313"
    private var adUnitID: String {
        let id = (Bundle.main.object(forInfoDictionaryKey: "QRRewardedAdUnitID") as? String) ?? ""
        return id.isEmpty ? Self.testRewardedID : id
    }

    private var rewarded: RewardedAd?
    private var ready = false
    private var loading = false
    private var earned = false
    private var dismissed: CheckedContinuation<Void, Never>?

    func prepare(from vc: UIViewController) async {
        // ① 同意情報の更新（毎回の起動で呼ぶ）
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) { _ in c.resume() }
        }
        try? await ConsentForm.loadAndPresentIfRequired(from: vc)

        // ② ATT（まだ選んでいない人にだけ表示される）
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }

        // ③ 広告SDKの初期化
        guard ConsentInformation.shared.canRequestAds else { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            MobileAds.shared.start { _ in c.resume() }
        }
        ready = true
        await load()
    }

    private func load() async {
        guard ready, rewarded == nil, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let ad = try await RewardedAd.load(with: adUnitID, request: Request())
            ad.fullScreenContentDelegate = self
            rewarded = ad
        } catch {
            rewarded = nil
        }
    }

    /// 最後まで見て報酬を得たら true
    func showRewarded(from vc: UIViewController) async -> Bool {
        if rewarded == nil { await load() }
        guard let ad = rewarded else { return false }
        rewarded = nil
        earned = false
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            dismissed = c
            ad.present(from: vc) { [weak self] in self?.earned = true }
        }
        let result = earned
        Task { await self.load() }   // 次の広告を先読み
        return result
    }

    private func finishPresentation() {
        dismissed?.resume()
        dismissed = nil
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in self.finishPresentation() }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in self.finishPresentation() }
    }
}
