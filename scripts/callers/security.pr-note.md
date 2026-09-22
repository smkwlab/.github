配布時に `--var RUN_DEPENDENCY_AUDIT=true|false` を明示指定します。**既定値は意図的にありません。**

| 値 | 対象 | 走るもの |
|---|---|---|
| `true` | `mix.exs` を持つリポジトリ | 依存脆弱性監査（mix_audit）+ secret scan |
| `false` | `mix.exs` が無いリポジトリ | secret scan のみ |

`true` のまま `mix.exs` が無いリポジトリへ配ると `mix deps.get` で落ちます。逆に Elixir リポジトリへ `false` で配ると、監査が落ちずに消えます。どちらも取り返しはつきますが、後者は気付けません。

secret scan（trufflehog）は言語を問いません。**private リポジトリでは GitHub 純正の secret scanning が Advanced Security を必要とするため、この caller が唯一の手段です。**

なお schedule によるトリガは、リポジトリに 60 日間活動が無いと GitHub 側で自動的に無効化されます（push / PR のトリガは影響を受けません）。
