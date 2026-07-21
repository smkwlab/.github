この caller は `secrets: inherit` で SMTP 系の organization secrets を reusable へ渡します。次の 6 つが org（または対象リポジトリ）に設定されている必要があります:

`SMTP_SERVER` / `SMTP_PORT` / `SMTP_USERNAME` / `SMTP_PASSWORD` / `LAB_ML_ADDRESS` / `SMTP_FROM`

未設定の場合、通知ジョブは実行時に失敗します（caller の設置自体は成功します）。
