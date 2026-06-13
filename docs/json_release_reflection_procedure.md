
# JSON Release Reflection Procedure

- 対象: `sensui_swipe`
- 対象ファイル: `assets/quiz_data.json`
- 目的: 既存公開問題を変更せず、各カテゴリを100問化した管理台帳を安全にJSONへ反映する

## 保護対象
- `part1`: `P1-001` から `P1-050`
- `part2`: `P2-001` から `P2-050`
- `part3`: `P3-001` から `P3-050`
- `part4`: `P4-001` から `P4-050`

## 反映ルール
1. 先頭50問は現行JSONをそのまま保持する。
2. 51問目以降は、対応CSVの `P*-051` 以降から順番に反映する。
3. JSONへ書き込む項目は `question` `isCorrect` `explanation` `imagePath` のみとする。
4. 反映対象は `status=approved` かつ `app_ready=yes` の行のみとする。
