# 赤チャリマップ

非公式の赤チャリマップ(東京自転車シェアリング ポートマップ)

## 概要

- 各ポートのタイトルに台数を表示
    - 0台の場合はアイコンをグレーにして表示
    
## 開発予定

- [ ] 自転車番号毎の情報を取得
    - [ ] 各ポートの説明に自転車番号一覧を追加(予約を超絶便利にしたい)
    - [ ] 自転車毎のポート移動履歴と滞在時間を表示(バッテリー切れなど不良自転車は滞在が他と比べて長いはず)

## URL

### 非公式マップ(Googleマイマップ)

https://www.google.com/maps/d/viewer?mid=105LHUShFiBhNviCJ5RCvIley_XLl0btn

### 本家(Googleマイマップ)

https://www.google.com/maps/d/viewer?mid=1L2l1EnQJhCNlm_Xxkp9RTjIj68Q

## 動作方法

### Heroku

TBD

```shell
heroku scale cron=1
```

## ライセンス

MIT