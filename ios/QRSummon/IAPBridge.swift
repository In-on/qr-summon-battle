import Foundation
import StoreKit

/// StoreKit 2 でアプリ内課金を行う。
/// 商品：
///   premium30d … プレミアムパス30日（非更新サブスクリプション・期限はゲーム側で管理）
///   dia10 / dia20 / dia40 … ダイヤ（消耗型）
///
/// 二重付与・付与もれを防ぐしくみ：
/// 1. Apple の署名を確認できた（verified）購入だけを「買えた」としてゲームに渡す
/// 2. ゲームが付与し終えてから finish（取引の完了）する
/// 3. 付与済みの取引IDは JS 側（localStorage）にも記録し、同じ取引が再び届いても付与しない
/// 4. 付与前にアプリが落ちた購入は、次回起動時に Transaction.unfinished から1回だけ渡す
@MainActor
final class IAPBridge {
    enum IAPError: LocalizedError {
        case productNotFound(String)
        var errorDescription: String? {
            switch self {
            case .productNotFound(let id): return "商品が見つかりません: \(id)"
            }
        }
    }

    var onDeliver: (([[String: String]]) -> Void)?

    private var products: [String: Product] = [:]
    private var held: [UInt64: Transaction] = [:]   // ゲームへ渡したが、まだ finish していない取引
    private var updatesTask: Task<Void, Never>?

    func start() {
        // 「承認と購入のリクエスト」（ファミリー共有）や、購入途中で中断されたものが、あとから届く
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let t) = result else { continue }
                await MainActor.run {
                    guard let self else { return }
                    if t.revocationDate != nil { Task { await t.finish() }; return }
                    if self.held[t.id] != nil { return }    // すでにゲームへ渡している
                    self.held[t.id] = t
                    self.onDeliver?([["pid": t.productID, "tx": String(t.id)]])
                }
            }
        }
    }

    private func product(_ id: String) async throws -> Product {
        if let p = products[id] { return p }
        for p in try await Product.products(for: [id]) { products[p.id] = p }
        guard let p = products[id] else { throw IAPError.productNotFound(id) }
        return p
    }

    /// 戻り値: { ok: Bool, tx?: String, reason?: String }
    func buy(productID: String) async throws -> [String: Any] {
        let p = try await product(productID)
        switch try await p.purchase() {
        case .success(let verification):
            switch verification {
            case .verified(let t):
                held[t.id] = t
                return ["ok": true, "tx": String(t.id)]
            case .unverified(let t, _):
                // Apple の署名が確認できない購入は付与しない
                await t.finish()
                return ["ok": false, "reason": "unverified"]
            }
        case .pending:
            return ["ok": false, "reason": "pending"]   // 承認されたら Transaction.updates で届く
        case .userCancelled:
            return ["ok": false, "reason": "cancelled"]
        @unknown default:
            return ["ok": false, "reason": "unknown"]
        }
    }

    /// ゲームが付与し終えたら呼ばれる
    func finish(transactionID: String) async {
        guard let id = UInt64(transactionID) else { return }
        if let t = held.removeValue(forKey: id) {
            await t.finish()
            return
        }
        for await result in Transaction.unfinished {
            if case .verified(let t) = result, t.id == id { await t.finish() }
        }
    }

    static let premiumID = (Bundle.main.object(forInfoDictionaryKey: "QRPremiumProductID") as? String) ?? "premium30d"

    /// 購入の復元：premium30d（非更新サブスクリプション）の、返金されていない取引の購入日時（ミリ秒）の一覧。
    /// - sync: true のときは App Store と同期してから調べる（別の端末での購入も取り込む。Apple ID の確認が出ることがある）。
    ///         起動時の自動復元では false（ダイアログを出さない）。
    func premiumPurchaseDates(sync: Bool) async -> [Double] {
        if sync { try? await AppStore.sync() }
        var dates: [Double] = []
        for await result in Transaction.all {
            guard case .verified(let t) = result,
                  t.productID == Self.premiumID,
                  t.revocationDate == nil else { continue }
            dates.append((t.purchaseDate.timeIntervalSince1970 * 1000).rounded())
        }
        return dates.sorted()
    }

    /// 前回、付与の途中で終わってしまった購入（起動時に JS から問い合わせる）
    func pendingDeliveries() async -> [[String: String]] {
        var out: [[String: String]] = []
        for await result in Transaction.unfinished {
            switch result {
            case .verified(let t):
                if t.revocationDate != nil { await t.finish(); continue }
                if held[t.id] != nil { continue }
                held[t.id] = t
                out.append(["pid": t.productID, "tx": String(t.id)])
            case .unverified(let t, _):
                await t.finish()
            }
        }
        return out
    }
}
