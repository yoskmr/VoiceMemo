---
name: works-directory
description: Soyokaプロジェクトの作業ディレクトリ（works/）運用ルール。調査(research)、分析(analysis)、作業依頼、レポート作成(report)など、works/配下で作業を行う場面で必ず参照すること。「調べて」「分析して」「レポートにまとめて」「作業して」といった依頼や、investigation/exploration タスク時に自動的に使うこと。
---

# 作業ディレクトリ運用ルール

作業依頼を受けた際は `works/` 配下で作業する。

## 命名規則

`YYYYMMDD_{作業No.}_{作業内容}`

- 同じ日付が既存の場合は No. をインクリメント
- 作業開始前に `ls works/ | grep YYYYMMDD` で確認

## 標準フォルダ構成

```
works/YYYYMMDD_XX_作業名/
├── README.md
├── scripts/     # SQL, Python, Ruby 等
├── data/        # CSV, JSON 等
└── result/      # 成果物（YYYYMMDDHHMM サブディレクトリ）
```

## 作業完了時

README.md に依頼内容・実施内容・知見・TODO を記載する。

## 最終レポート

`reports/YYYYMMDD_{No.}_{タイトル}.md` に配置する。
