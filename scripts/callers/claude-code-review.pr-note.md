PR への自動レビュー（Claude）を有効化します。

- 動作には org シークレット `ANTHROPIC_API_KEY` がこのリポジトリで利用可能である必要があります（未配布なら安全にスキップ）
- draft PR は `ready_for_review` まで、fork PR は secret 不在のため、いずれも安全にスキップします
