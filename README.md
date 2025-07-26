# Ponko2 - AI Overlay App

🚀 **AI搭載インタラクティブオーバーレイアプリ**

![Ponko2 Main Interface](docs/images/main.png)

Ponko2は、Claude AIを活用してスクリーンショットを分析し、UI要素の位置を特定してチュートリアル表示する革新的なmacOSアプリケーションです。

![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)
![Platform](https://img.shields.io/badge/Platform-macOS-blue.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## ✨ 主要機能

### 🤖 AI駆動スクリーンショット分析
- **Claude API統合**: 最先端のAIによる画面解析
- **UI要素自動検出**: ボタン、アイコン、メニューなどの自動識別
- **インテリジェント座標計算**: 物理ピクセルから論理座標への精密変換

### 🎯 インタラクティブオーバーレイ
- **外部プロセス方式**: segmentation fault完全回避の安全な実装
- **リアルタイム赤枠表示**: 対象UI要素の正確なハイライト表示
- **チュートリアルガイド**: ステップバイステップの操作説明

### 🛡️ 安全性とパフォーマンス
- **メモリ安全**: 独立プロセスによるクラッシュ防止
- **自動圧縮**: 5MB以内の画像最適化
- **権限管理**: 画面収録権限の適切な処理

## 🏗️ アーキテクチャ

```
Ponko2/
├── Sources/
│   ├── main.swift              # メインアプリケーション
│   ├── OverlayServiceProtocol.swift    # XPCプロトコル定義
│   ├── XPCConnectionManager.swift      # XPC接続管理
│   └── OverlayXPCService/              # XPCサービス
├── OverlayHelper.swift         # 外部プロセスオーバーレイ
├── screenshot-analysis-server/ # MCPサーバー (Node.js)
└── Package.swift              # Swift Package Manager
```

### 🔧 技術スタック
- **フロントエンド**: SwiftUI + AppKit
- **AI分析**: Claude API (Anthropic)
- **画像処理**: Core Graphics
- **プロセス通信**: XPC + 外部プロセス
- **バックエンド**: MCP (Model Context Protocol) サーバー

## 🚀 セットアップ

### 前提条件
- macOS 13.0+ 
- Xcode 15.0+
- Swift 5.9+
- Node.js 18+ (MCPサーバー用)

### インストール

1. **リポジトリのクローン**
```bash
git clone https://github.com/Tonoyama/ponko2.git
cd ponko2
```

2. **依存関係のインストール**
```bash
# Swift依存関係
swift package resolve

# MCPサーバー依存関係
cd screenshot-analysis-server
npm install
npm run build
cd ..
```

3. **ビルドと実行**
```bash
swift build
swift run MyOverlayApp
```

### 📱 初回セットアップ
1. **画面収録権限**: システム設定 > プライバシーとセキュリティ > 画面収録
2. **API設定**: Claude APIキーの設定（必要に応じて）
3. **実行確認**: 緑のカメラボタンでスクリーンショット撮影テスト

## 💡 使用方法

### 基本操作
1. **アプリ起動**: `swift run MyOverlayApp` でアプリを開始
2. **質問入力**: 「VSCodeのgitアイコンはどこ？」のように質問
3. **AI分析**: 自動でスクリーンショット撮影・AI分析実行
4. **結果表示**: 赤枠で対象UI要素をハイライト表示

### 質問例
- 「ファイルメニューはどこをクリックすればいい？」
- 「保存ボタンの場所を教えて」
- 「設定画面はどこから開く？」

## 🔧 カスタマイズ

### API設定
```swift
// Sources/main.swift内
private let apiKey = "your-claude-api-key-here"
```

### オーバーレイ設定
```swift
// OverlayHelper.swift内
let overlayDuration: TimeInterval = 5.0  // 表示時間
let frameWidth: CGFloat = 4.0           // 枠線太さ
```

## 🤝 開発に参加

### 課題報告
バグ報告や機能要望は[Issues](https://github.com/Tonoyama/ponko2/issues)でお気軽にどうぞ。

### プルリクエスト
1. フォークしてフィーチャーブランチを作成
2. 変更をコミット (`git commit -am 'Add feature'`)
3. ブランチをプッシュ (`git push origin feature`)
4. プルリクエストを開く

### 開発ガイドライン
- Swift 5.9+ の最新機能を活用
- コードコメントは日本語OK
- セキュリティを最優先に考慮
- パフォーマンス影響を最小限に

## 📚 技術詳細

### 外部プロセス方式
```swift
// 安全なオーバーレイ表示
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
process.arguments = [helperPath, text, x, y, width, height, description]
```

### AI座標変換
```swift
// 物理座標 → 論理座標変換
let logicalX = physicalRect.origin.x / scaleFactor
let logicalY = physicalRect.origin.y / scaleFactor
```

## 🏆 実績

- ✅ **segmentation fault完全解決**: 外部プロセス方式採用
- ✅ **AI精度向上**: Claude API統合による高精度UI検出
- ✅ **メモリ効率**: 自動画像圧縮で5MB以内に最適化
- ✅ **ユーザーエクスペリエンス**: 直感的なチャット形式UI

## 📄 ライセンス

MIT License - 詳細は[LICENSE](LICENSE)ファイルを参照してください。

## 👨‍💻 作者

**Tonoyama** - [GitHub](https://github.com/Tonoyama)

---

**"AI時代のインタラクティブなUI案内体験を"** 🚀
