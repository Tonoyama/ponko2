# Ponko2 - AI Overlay App

**※ 現時点ではアプリの実装はできていますが、座標の設定がうまくいってないため改良が必要です...現時点ではポンコツです orz**

🚀 **インタラクティブチュートリアル表示アプリ**

<img src="docs/images/main.png" alt="Ponko2 Main Interface" width="70%">

Ponko2は、Claude AIを活用してスクリーンショットを分析し、UI要素の位置を特定してチュートリアル表示するmacOSアプリケーションです。

アプリ上にオーバーレイを作成することでアプリを操作しながらLLMにUIを教えてもらうことが可能です

<img src="docs/images/overlay.png" alt="Ponko2 Main Interface" width="70%">

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
- Claude API キー ([Anthropic Console](https://console.anthropic.com) で取得)

### インストール

1. **リポジトリのクローン**
```bash
git clone https://github.com/Tonoyama/ponko2.git
cd ponko2
```

2. **環境設定ファイルの作成**
```bash
# .env.exampleから.envファイルを作成
cp .env.example .env
```

3. **APIキーの設定**
```bash
# .envファイルを編集してAPIキーを設定
nano .env
```

`.env`ファイル内で以下を設定：
```bash
# Claude API キー (必須)
CLAUDE_API_KEY=sk-ant-api03-your-actual-api-key-here

# アプリ設定 (オプション)
APP_NAME=Ponko2
LOG_LEVEL=info
```

4. **依存関係のインストール**
```bash
# Swift依存関係
swift package resolve

# MCPサーバー依存関係
cd screenshot-analysis-server
npm install
npm run build
cd ..
```

5. **ビルドと実行**
```bash
swift build
swift run MyOverlayApp
```

### 📱 初回セットアップ
1. **画面収録権限**: システム設定 > プライバシーとセキュリティ > 画面収録を`.build/debug/MyOverlayApp`に設定
2. **API設定**: アプリ内の⚙️ボタンから.envファイルの作成・APIキー設定が可能
3. **実行確認**: 質問を入力してAI分析機能をテスト

### 🔐 Claude API キーの取得方法

1. [Anthropic Console](https://console.anthropic.com) にアクセス
2. アカウント作成・ログイン
3. API Keys セクションで新しいキーを作成
4. 作成されたキー（`sk-...`で始まる）をコピー

### ⚙️ APIキーの設定方法

取得したAPIキーは以下の2つの方法で設定できます：

#### 方法1: アプリ内設定（推奨・簡単）
1. **アプリを起動**: `swift run MyOverlayApp`
2. **設定画面を開く**: フローティングパネル右上の⚙️（歯車）ボタンをクリック
3. **APIキーを入力**: 取得したAPIキーを入力フィールドに貼り付け
4. **保存**: 「APIキーを.envに保存」ボタンをクリック
5. **確認**: 設定状態が「APIキーが設定済みです」になることを確認

> **💡 ヒント**: アプリ内設定では自動で.envファイルが作成され、APIキーが安全に保存されます。

#### 方法2: .envファイル手動編集
1. **ファイル作成**: `.env.example`から`.env`ファイルを作成
2. **編集**: `.env`ファイルを開いて`CLAUDE_API_KEY=取得したAPIキー`を設定
3. **保存**: ファイルを保存してアプリを再起動

## 💡 使用方法

### 基本操作
1. **アプリ起動**: `swift run MyOverlayApp` でアプリを開始
2. **APIキー設定**: 初回起動時はフローティングパネル右上の⚙️ボタンからAPIキーを設定
3. **質問入力**: 「VSCodeのgitアイコンはどこ？」のように質問
4. **AI分析**: 自動でスクリーンショット撮影・AI分析実行
5. **結果表示**: 赤枠で対象UI要素をハイライト表示

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

## 📄 ライセンス

MIT License - 詳細は[LICENSE](LICENSE)ファイルを参照してください。

## 👨‍💻 作者

**Tonoyama** - [GitHub](https://github.com/Tonoyama)

---

**"AI時代のインタラクティブなUI案内体験を"** 🚀
