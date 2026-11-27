# QR召喚バトル：iPhoneアプリ化の引き継ぎメモ

このメモは Claude Code に作業をお願いするためのものです。リポジトリのいちばん上に置いてあります。

## オーナーについて
- やりとりは**日本語**でお願いします。専門用語はできるだけ使わず、短く説明してください。
- オーナーは **Mac を持っていません**。iPhone とブラウザだけで作業します。
- GitHub へは**ブラウザからファイルをアップロード**して更新しています。
- 大きな変更の前には、何をするかを一言説明してから進めてください。

## ゲームの今の状態（v11.52）
- 本体は `index.html` の1ファイルです（約2.7MB）。画像・音・3Dモデルの多くを中に埋め込んでいます。
- そのほかのファイル：
  - `models1〜5.js`・`avatar_m.js`・`avatar_f.js`：3Dモデル
  - `lib/`：three.js・GLTFLoader・jsQR・ZXing・supabase-js・フォント
  - `privacy.html`・`terms.html`・`tokusho.html`・`shikin.html`：規約などのページ
- 今は GitHub Pages（https://in-on.github.io/qr-summon-battle/）で公開しています。
- 画面は横向き専用です。縦に持ったときは、`applyOrient()` が body を90度回して横向きにします。
- **ゲームの中身は書き直さないでください。** Capacitor などの入れ物（WebView）に入れる形でお願いします。

## 決まっていること
- **バンドルID**：`com.qrsummon.battle`（Apple Developerで登録済み、または登録予定）
- **ホーム画面に出す名前**：`QR召喚バトル`（Info.plist の `CFBundleDisplayName`。App Store上の名前と同じ）
- アプリ名：QR召喚バトル
- Apple Developer Program（個人）登録済み。有料アプリの契約・口座・税務情報も有効。

## やってほしいこと
1. **iOSアプリにする**
   - Capacitor（または WKWebView）で iOS アプリにします。バンドルIDは `com.qrsummon.battle` です。
   - `index.html`・`lib/`・`models*.js`・`avatar_*.js` などは、アプリの中に同梱してください（GitHub Pages から読み込む形にはしない）。
   - 横向き固定にします。
2. **クラウドでビルドする（Macなし）**
   - `codemagic.yaml` を作ります。
   - 自動署名（App Store Connect APIキー）でビルドし、TestFlight に自動で上げます。
3. **User-Agent**
   - WebView の User-Agent の最後に `QRSummonApp` を付けてください。
   - ゲームは `isApp()` でこれを見て、アプリ版かどうかを判断します。
4. **課金（StoreKit）**
   - ゲームは `window.QRIAP.buy(商品ID)` を呼び、`Promise<boolean>` を受け取ります（買えたら true）。
   - 商品は次の4つです。
     - `premium30d`：プレミアムパス・30日・480円（**非更新サブスクリプション**。期限はゲーム側で管理）
     - `dia10`：ダイヤ10個・300円
     - `dia20`：ダイヤ20個・500円
     - `dia40`：ダイヤ40個・900円
   - Appleの購入記録を確認してから true を返してください。
   - 同じ購入で2回ダイヤが増えないようにしてください（取引を必ず完了させ、未完了の取引が次回起動時に二重で渡らないようにする）。
   - **購入の復元（必須）**：`window.QRIAP.restore()` を用意し、`Promise<number[]>` を返してください。
     - 中身は、`premium30d` の有効な（返金されていない）取引の購入日時（ミリ秒）の一覧です（StoreKit 2 の `Transaction.all` などから取得）。
     - ゲームはこれを `window.QRPremRestore(一覧)` で受け取り、購入日から30日ずつ足して有効期限を計算します。プレミアムパス画面に「購入を復元する」が出ます。
     - アプリ起動時にも自動で `window.QRPremRestore(一覧)` を呼んでください（機種変更・再インストールでもパスが戻るように）。
5. **広告（AdMob リワード広告）**
   - ゲームは `window.QRAd.show()` を呼び、`Promise<boolean>` を受け取ります（最後まで見たら true）。
   - 使い道は、1日1回の「スタミナ+5」と「携帯品BOX」です。
   - AdMob のIDはまだないので、**Googleのテスト用ID**で作り、あとで差し替えやすくしてください。
   - ATT（トラッキング許可）と、SKAdNetwork の設定もお願いします。
6. **App Store 審査の確認**
   - 引っかかりそうな点を洗い出して直してください。
   - ガイドライン4.2（Webを包んだだけのアプリに見えないか）
   - プライバシー（プライバシー情報の申告内容、データ削除）
   - 外部での決済がないか
   - ガチャの確率表示（下の「確率」を参照）
7. **オーナー向けの手順書**
   - iPhone とブラウザだけでできる手順書を作ってください。
   - App Store Connect：アプリの登録、課金商品の作成、APIキーの作成、スクリーンショットのサイズ、審査メモの書き方
   - Codemagic の設定
   - TestFlight でのテスト
   - AdMob：登録、アプリの追加（未公開として）、公開後のストア連携、app-ads.txt の置き場所
     - app-ads.txt は、`in-on.github.io` という別のリポジトリを作って、そのいちばん上に置く必要があります。

## 確率（ゲーム内の設定）
- **エフェクトガチャ**：全8種、どれも12.5%（ダイヤ10個で1回）。ゲーム内にも「全8種 各12.5%」と表示しています。
  - 演出は、どのエフェクトが出ても同じ「虹の最高演出」です（`GX`）。レア度の★は表示していません。
- **QR召喚**：UR 2%（`UR_RATE=.02`）、SR 5%（`SR_RATE=.05`）、ほかはN。
  - 召喚画面に確率の表示があるか確認してください。なければ追加をお願いします。

## サーバー（Supabase）
- URL と公開用キー（publishable key）は `index.html` の `SB_URL`・`SB_KEY` にあります。
- 表（ゲーム側からは読むだけ。RLS確認済み）
  - `qr_gifts`：プレゼント
  - `qr_news`：お知らせ
  - `qr_config`：スイッチ
    - `friend_busy`：true にするとフレンド対戦が「混み合っています」になる
    - `web_closed`：true にするとブラウザ版が閉じる。note に App Store のURLを入れると「App Store で見る」ボタンが出る
- 関数（RPC）
  - `qr_now`：サーバーの時刻（ログインボーナスなどの不正防止に使用）
  - `qr_move_*`：引き継ぎ
  - `qr_rank_put`・`qr_rank_board`：ランキング（今はオフ）
- フレンド対戦は Realtime（broadcast）を使います。ホストが1秒に10回、状態を送ります。

## 大事なスイッチ（index.html の中）
| 名前 | 今の値 | 意味 |
|---|---|---|
| `RK_ON` | false | ランキング・シーズン。審査に通ってからオンにする予定 |
| `AD_TEST` | false | 公開用。アプリ版では `QRAd.show()` を使う |
| `CHG_TEST` | false | 公開用 |
| `GACHA_OPEN` | true | エフェクトガチャ |

## 気をつけてほしいこと
- **Web版（GitHub Pages）を壊さないでください。** 規約ページの公開と、アプリ公開までのWeb版として使います。
- **引き継ぎ**はアプリ版どうしだけです。
  - Web版では発行も受け取りもできません。
  - アプリで発行したデータには `xfFrom:'app'` を付け、受け取るときにこれがないデータははじきます。
- **時刻**は `gNow()`（サーバー時刻）で判定しています。ログインボーナス・広告・クエスト・召喚回数・週末ボーナス・スタミナ・プレミアムパスの期限です。
- **アプリ公開後**は、`qr_config` の `web_closed` を true にしてブラウザ版を閉じる予定です。
- 規約・プライバシーポリシー・特商法のページは、App Store Connect に登録するURLとして使います。
  - https://in-on.github.io/qr-summon-battle/privacy.html
  - https://in-on.github.io/qr-summon-battle/terms.html
  - https://in-on.github.io/qr-summon-battle/tokusho.html

## あとで決めること（今はやらなくてよい）
- ランクシーズンを14日にするか、いつ始めるか（審査に通ってから決める）
- シーズン2からのQアイコン（ローマ数字入り）
