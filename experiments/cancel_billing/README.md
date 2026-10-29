# 中断時の課金を確かめる実験

ストリーミング中にアプリ側で中断したとき、OpenAI で何トークン課金されるかを調べます。
LT「AI 機能の UI はなぜ難しいのか」の Appendix A-5・A-5b（途中で切ると課金はどうなるか）の元になった実験です。
予備調査の結果は [FINDINGS.md](FINDINGS.md) にあります。

## やり方

「1 から 1200 まで 1 行ずつ数字を書いて」と頼み、**最初の差分から決めた秒数がたった時点で** `subscription.cancel()` します。

途中で中断した応答はサーバーに保存されず `GET /v1/responses/{id}` で取り直せないため、
1 回ずつ別の 1 分枠で実行し、**利用量 API（管理者キー、1 分単位）**で課金トークンを突き合わせます。

| 条件 | 中断のしかた |
|---|---|
| 最後まで | 中断しない（1 行あたりのトークン数の基準） |
| 最初の差分 ／ 1 秒後 ／ 2 秒後 ／ 6 秒後 | `subscription.cancel()` だけ（client はその分の終わりまで開いたまま） |
| 2 秒後 + close | `cancel()` のあと `client.close()` も |

## 実行

```bash
cd experiments/cancel_billing
cat > .env <<'EOF'          # .env は git に入らない
OPENAI_API_KEY=sk-...
OPENAI_ADMIN_KEY=sk-admin-...   # 読み取り専用の管理者キー。実験後に削除する
EOF
dart pub get
dart run bin/cancel_billing.dart --reps 3    # 6 条件 × 3 回 ≒ 20 分。--model（既定 gpt-6-luna）／ --effort（既定 none）
dart run bin/usage.dart results/<日時>.json   # 利用量の反映が遅れたとき、課金トークンだけ取り直す
```

`bin/probe.dart <行数>` は 1 リクエストだけ送り、イベントの到着時刻と中断後のふるまいを細かく出す調査用スクリプトです（`-1` で中断しない）。

## 注意

- 推論トークンは出力として課金されるがテキストとしては流れてこないため、既定では推論なし（`--effort none`）で比べます
- 受け取ったトークン数は「最後まで」の回の `output_tokens ÷ 行数` から換算した推定値です
- 利用量 API は同じ 1 分枠のほかの利用も合算します。実験中は同じ組織で API を使わないでください（`課金リクエスト` 列が 1 でない枠は要確認）
