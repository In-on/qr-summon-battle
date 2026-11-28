import UIKit
import AppTrackingTransparency
import GoogleMobileAds
import UserMessagingPlatform

/// AdMob のリワード広告。ゲームの window.QRAd.show() から呼ばれる。
/// 広告ユニットはボタンごとに分ける：
///   "st"  … スタミナ+5   （Info.plist の QRRewardedAdUnitID）
///   "box" … 携帯品BOX    （Info.plist の QRRewardedBoxAdUnitID。無ければ "st" と同じ）
/// 起動時に ①同意フォーム（EEA/英国など必要な地域のみ）②ATT（トラッキング許可）③SDK初期化 の順に行う。
@MainActor
final class AdBridge: NSObject, FullScreenContentDelegate {
    private static let testRewardedID = "ca-app-pub-3940256099942544/1712485313"

    private func adUnitID(for kind: String) -> String {
        func read(_ key: String) -> String {
            let v = (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
            return v.trimmingCharacters(in: .whitespaces)
        }
        let st = read("QRRewardedAdUnitID")
        let box = read("QRRewardedBoxAdUnitID")
        let id = (kind == "box" && !box.isEmpty) ? box : st
        return id.isEmpty ? Self.testRewardedID : id
    }
    private func normalized(_ kind: String) -> String { kind == "box" ? "box" : "st" }

    private var ads: [String: RewardedAd] = [:]
    private var loading = Set<String>()
    private var ready = false
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
        await load("st")
        await load("box")
    }

    private func load(_ rawKind: String) async {
        let kind = normalized(rawKind)
        guard ready, ads[kind] == nil, !loading.contains(kind) else { return }
        loading.insert(kind)
        defer { loading.remove(kind) }
        do {
            let ad = try await RewardedAd.load(with: adUnitID(for: kind), request: Request())
            ad.fullScreenContentDelegate = self
            ads[kind] = ad
        } catch {
            ads[kind] = nil
        }
    }

    /// 最後まで見て報酬を得たら true
    func showRewarded(kind rawKind: String, from vc: UIViewController) async -> Bool {
        let kind = normalized(rawKind)
        if ads[kind] == nil { await load(kind) }
        guard let ad = ads.removeValue(forKey: kind) else { return false }
        earned = false
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            dismissed = c
            ad.present(from: vc) { [weak self] in self?.earned = true }
        }
        let result = earned
        Task { await self.load(kind) }   // 次の広告を先読み
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
