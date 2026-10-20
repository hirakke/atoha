# atoha プロトタイプ

あとは、あとで。浮かんだことを3秒で「あとで」にすると、終わったら返ってくる。あとにしたものから自分の軸が見えてくる。

## 動かし方

```bash
xcodegen generate
open Atoha.xcodeproj
```

- iOS 26 以降、Xcode 26 以降
- 実機で動かすときは、Xcode の Signing & Capabilities で自分の Team を選ぶ
- アクションボタン：設定 → アクションボタン → ショートカット → 「atoha / あとで」

## 構成

| フォルダ | 中身 |
| --- | --- |
| `Atoha/Model` | SwiftData の `Item`（あとでにしたもの）と `Axis`（自分の軸） |
| `Atoha/UI/Capture` | 書き出し画面。入れたら返す時刻をドット文字で出して閉じる |
| `Atoha/UI/Home` | 「今」タブ（「次」カードと、返ってきたものを やりたい／やらなきゃ で4つに分ける）、水槽、地図から開く軸のシート |
| `Atoha/UI/Later` | 「あとで」タブ（水槽と「受け取る」、預かり中を返す時刻ごとに並べる。今受け取る・返す時刻の変更） |
| `Atoha/UI/Map` | 軸の3D地図（タブは「今」「あとで」「地図」の3つ。左上の「軸」でシート）（SceneKit のボクセル、指で回す、傾けると動く） |
| `Atoha/UI/Dot` | ドットマトリクス文字、ドット、1週間の列 |
| `Atoha/Services` | 振り分け・期限の読み取り（Foundation Models＋予備のルール）、埋め込み、軸の計算と候補 |
| `Atoha/Intents` | アクションボタン／ショートカット用の「あとで」 |
| `AtohaWatch` | Apple Watch アプリ（手首からあとで）。`Atoha/Services/WatchBridge.swift` が iPhone 側で受け取る |

## 集中

返ってきたものを1つ選んで「やる」。画面にはそれだけが残る。経過時間（ドット）、25／50分の目安（任意）、「あとで」（終わったら返る）、「終わる」。
終わると、集中中に「あとで」にしたものが返り、「できた」か「まだ」を選ぶ。集中した時間は `Item.focusSeconds` に積む。状態は UserDefaults に残り、再起動しても戻る。

## シミュレータで確かめるための起動引数（DEBUG のみ）

| 引数 | 動き |
| --- | --- |
| `-atohaReset` | データを消す |
| `-atohaAxes` | 軸を3本入れる（一人で↔人と、作る↔整える、今↔将来） |
| `-atohaSeed` | サンプルを20件入れる |
| `-atohaTab later` / `map` / `axes` | 開くタブ（`axes` は地図を開いて軸のシートを出す） |
| `-atohaCapture` | 書き出し画面を開く |
| `-atohaFocus` | 返ってきた最初のものに集中する |
| `-atohaNoNotif` | 通知の許可を求めない |

## PCC（Private Cloud Compute）

- `Services/PCCBackend.swift`：iOS 27 の `PrivateCloudComputeLanguageModel` を使うまとめ処理（まとまりの名前付け、軸の候補）。`#if compiler(>=6.3)` の中にあり、**Xcode 27 以降でビルドしたときだけ有効**。Xcode 26 では iPhone 内のモデルに自動で切り替わる
- `Services/BatchOrganizer.swift`：返ってきたものがあるときに1回まとめる。PCC は1日3回まで（`CloudAI.dailyBudget`）に抑え、超えたら iPhone 内のモデルに切り替える
- 軸のシートの下に PCC の状態（使える／上限に近い／上限）を印で出す。上限のときは Apple の「上限を増やす」画面を開くボタン
- 実機で使うには：App Store Small Business Program への登録、PCC の entitlement（`com.apple.developer.private-cloud-compute`）の申請と付与、Xcode 27

## ChatGPT（任意・個人利用）

- Sign in with ChatGPT でログインすると、まとめ処理（まとまりの名前付け、軸の候補）を ChatGPT のプラン枠のモデルで行う。選ぶ順番は PCC → ChatGPT → iPhone 内のモデル。1件ずつの振り分けは iPhone 内のまま。回数は PCC と同じ1日3回
- 既定では **DEBUG ビルドだけ**で有効。Release で出すときは UserDefaults の `atoha.chatgpt.enabled` が真のときだけ表示する
- 対象：OpenAI の方針ではオープンソース／ローカルで動かすアプリ向け。有料・ホスト型のアプリは OpenAI の関心フォームが必要。App Store 配布が認められるかは未確認
- トークンと端末ごとの ID は Keychain（`app.atoha.siwc`）に保存する。ログインは 127.0.0.1:1455 の一時的な待ち受け＋ Safari シート
- `Services/ChatGPTAuth.swift`、`Services/ChatGPTBackend.swift`、手順の元は `tools/siwc_try.py`

## まだやっていないこと

- PCC 部分の実際の動作確認（この Mac には Xcode 26 しかないため、構文チェックのみ）
- コントロールセンターの「あとで」の表示確認、預かり中が0件になったときにライブアクティビティが消えるかの確認
- Apple Watch：あとで操作と iPhone との同期の確認、コンプリケーション
- カメラで撮ってあとで、場所で返す
- 意味の近さは、日本語の文埋め込みがないため文字の組み合わせで近似している
