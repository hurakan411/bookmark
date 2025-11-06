# Nebula Journal Landing Page

Astro製のシングルページLPです。iPhone向けアプリ「Nebula Journal」の世界観を表現し、機能や価格、FAQ、CTAなどを1枚で伝えます。

## 主なセクション

- スクロールヒーロー：AIコーチの価値を強調するヒーローセクションとハイライト統計
- 機能紹介：カード型の機能3本柱
- 体験紹介：タイムライン形式でアプリの使い方を説明
- レビュー：βユーザーの証言
- 価格プラン：3つのサブスクリプションプラン
- FAQ：よくある質問
- ダウンロード CTA：App Store 事前登録ボタンと問い合わせ導線

## 技術スタック

- [Astro 4](https://astro.build/)
- [Tailwind CSS 3](https://tailwindcss.com/)

## セットアップ

> **前提**: Node.js 18 以上が必要です。macOS で `brew install node` などを利用して Node.js を準備してください。

```bash
npm install
npm run dev
```

### 開発サーバー

- `npm run dev` : 開発モードで起動 (ホットリロード対応)
- `npm run build` : 本番ビルドを生成
- `npm run preview` : ビルド結果をローカルでプレビュー
- `npm run lint` : Astro の型チェック

## ディレクトリ構成

```
├── src
│   ├── components     # セクション単位の Astro コンポーネント
│   ├── layouts        # 共通レイアウト
│   ├── pages          # ルーティング (index.astro)
│   └── styles         # グローバルスタイル (Tailwind + カスタム)
├── public
│   └── images         # SVG モックアップやOG画像
├── astro.config.mjs
├── tailwind.config.cjs
└── tsconfig.json
```

## カスタマイズのヒント

- 画像は `public/images` に SVG で配置しています。実際のスクリーンショットに差し替える場合は同名ファイルを置き換えてください。
- CTA ボタンのリンク (`DownloadCTA.astro`) はダミーの `#` になっています。App Store の URL に差し替えてください。
- 色味やフォントは `tailwind.config.cjs` と `src/styles/global.css` で調整できます。

## ライセンス

プロジェクト固有のライセンス要件がある場合はここに追記してください。
