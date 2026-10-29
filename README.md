# AI に旅の相談（Five UI States デモ）

FlutterKaigi 2026 の LT「AI 機能の UI はなぜ難しいのか — Five UI States で設計する Flutter × 生成 AI の画面デザイン」で使ったデモアプリです。
発表者：日野泰志 ／ X：[@pregum_fox](https://x.com/pregum_fox) ／ GitHub：[Pregum](https://github.com/Pregum)

GenUI SDK（`genui` 0.10）で、AI の応答から旅のプランや宿のカードを組み立てる。

- 状態はスライドと同じ `AiUiState`（sealed class）で持つ：`lib/state/ai_ui_state.dart`
- GenUI の `Conversation` のイベントを 5 状態に写すところ：`lib/agent/travel_agent.dart`
- 画面右上で **before**（とりあえず作った画面）と **after**（5 状態で設計した画面）を切り替えられる

| 状態 | before | after |
|---|---|---|
| Empty | 何も出ない | できること・頼み方の例・できないこと |
| Loading | 全画面スピナー | 経過のステップ・経過時間・進捗バー・スケルトン・停止 |
| Partial | 全部そろうまで出さない | 届いた部品から画面が育つ・停止 |
| Error | エラーコードのダイアログ。途中までの中身は捨てる | 途中までを残し、もう一度生成・編集して再送 |
| 低品質な応答 | そのまま成功として出す | 画面が組めなければ失敗として扱い、足すとよい条件を伝える |
| Ideal | 回答だけ | 再生成・編集・良い／違う |

## 動かし方

Flutter 3.47.2（`.mise.toml` で固定）。

```bash
flutter run -d chrome          # モック（API を叩かない）
flutter test                   # 状態遷移のテスト（スライドの Appendix A-8 と同じ内容）
```

右上の ⚙ から、モックの筋書き（最後まで届く／途中で通信が切れる／中身のない返事／とても遅い）を選べる。

### Gemini に本当に送る

API キーはファイルに置かず、1Password から実行時に渡す。

```bash
flutter run -d chrome --dart-define=GEMINI_API_KEY="$(op read 'op://<vault>/<item>/<field>')"
```

⚙ の「Gemini に本当に送る」を選ぶと、Gemini API（`streamGenerateContent`、SSE）を叩く。
モデルは `--dart-define=GEMINI_MODEL=...` で変えられる（既定は `gemini-flash-latest`）。
デバッグ実行では、届いた断片と時刻がコンソールに `RECORDING [...]` として出る（モックの台本づくり用）。

### 撮影用の URL パラメーター

Web 版では URL で状態を決めて開ける。スライドのスクリーンショットはこれで撮った。

| パラメーター | 例 | 意味 |
|---|---|---|
| `mode` | `before` | before の画面で開く（既定は after） |
| `scenario` | `networkError` | モックの筋書き（`success`／`networkError`／`lowQuality`／`slow`） |
| `send` | `1` | 開いたらすぐ「週末、箱根で温泉旅行を計画して」を送る |
| `stopAfter` | `9800` | 送ってから指定ミリ秒後に停止する |

## 中断時の課金の実験

[`experiments/cancel_billing/`](experiments/cancel_billing/) は、ストリーミングを途中で止めたとき OpenAI の利用量に計上されるかを測った実験です（Dart のコマンドラインプログラム）。結果は [FINDINGS.md](experiments/cancel_billing/FINDINGS.md) にあります。

## ライセンス

コードは [MIT License](LICENSE) です。

`assets/fonts/NotoSansJP.ttf` は SIL Open Font License 1.1（`assets/fonts/OFL.txt`）。
Web 版で日本語が化けないよう、実行時に取りに行かずに同梱している。
