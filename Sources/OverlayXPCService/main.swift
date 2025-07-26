import Cocoa
import Foundation

// XPCサービスとメインアプリ間の通信プロトコル
@objc protocol OverlayServiceProtocol {
    func showTutorialOverlay(steps: [TutorialStepData]) async
    func hideTutorialOverlay() async
    func ping() async -> String
}

// XPCで送信可能なデータ構造
@objc class TutorialStepData: NSObject, NSSecureCoding, @unchecked Sendable {
    static let supportsSecureCoding: Bool = true
    
    @objc let id: String
    @objc let text: String
    @objc let x: Double
    @objc let y: Double
    @objc let width: Double
    @objc let height: Double
    @objc let stepDescription: String // NSObjectのdescriptionと競合を避けるため
    
    init(id: String, text: String, x: Double, y: Double, width: Double, height: Double, description: String) {
        self.id = id
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.stepDescription = description
        super.init()
    }
    
    required init?(coder: NSCoder) {
        guard let id = coder.decodeObject(of: NSString.self, forKey: "id") as String?,
              let text = coder.decodeObject(of: NSString.self, forKey: "text") as String?,
              let stepDescription = coder.decodeObject(of: NSString.self, forKey: "stepDescription") as String? else {
            return nil
        }
        
        self.id = id
        self.text = text
        self.x = coder.decodeDouble(forKey: "x")
        self.y = coder.decodeDouble(forKey: "y")
        self.width = coder.decodeDouble(forKey: "width")
        self.height = coder.decodeDouble(forKey: "height")
        self.stepDescription = stepDescription
        super.init()
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(id, forKey: "id")
        coder.encode(text, forKey: "text")
        coder.encode(x, forKey: "x")
        coder.encode(y, forKey: "y")
        coder.encode(width, forKey: "width")
        coder.encode(height, forKey: "height")
        coder.encode(stepDescription, forKey: "stepDescription")
    }
}

// XPCサービスのメインエントリーポイント
class OverlayXPCServiceDelegate: NSObject, @preconcurrency NSXPCListenerDelegate {
    @MainActor
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        print("🔗 XPCサービス: 新しい接続を受信")
        
        // プロトコルの設定
        newConnection.exportedInterface = NSXPCInterface(with: OverlayServiceProtocol.self)
        newConnection.exportedObject = OverlayService()
        
        newConnection.resume()
        print("✅ XPCサービス: 接続が確立されました")
        return true
    }
}

// オーバーレイ表示を担当するサービス実装（research.mdのベストプラクティス準拠）
@MainActor
class OverlayService: NSObject, OverlayServiceProtocol {
    private var overlayWindow: NSWindow?
    
    func showTutorialOverlay(steps: [TutorialStepData]) async {
        print("🎯 XPCサービス: オーバーレイ表示開始 (\(steps.count)ステップ)")
        
        // 既存のオーバーレイを非表示
        hideOverlayInternal()
        
        guard let firstStep = steps.first else {
            print("❌ XPCサービス: 表示するステップがありません")
            return
        }
        
        // 透明オーバーレイウィンドウを作成
        createOverlayWindow(for: firstStep)
    }
    
    func hideTutorialOverlay() async {
        print("🚫 XPCサービス: オーバーレイ非表示")
        hideOverlayInternal()
    }
    
    func ping() async -> String {
        return "🏓 XPCサービス応答: \(Date())"
    }
    
    // MARK: - Private Methods
    
    @MainActor
    private func hideOverlayInternal() {
        overlayWindow?.close()
        overlayWindow = nil
    }
    
    @MainActor
    private func createOverlayWindow(for step: TutorialStepData) {
        // 画面サイズを取得
        guard let screen = NSScreen.main else {
            print("❌ XPCサービス: メインスクリーンが取得できません")
            return
        }
        
        let screenFrame = screen.frame
        print("📐 XPCサービス: 画面サイズ \(screenFrame.size)")
        
        // 透明フルスクリーンウィンドウを作成
        overlayWindow = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        guard let window = overlayWindow else { return }
        
        // research.mdの知見に基づくウィンドウ設定
        window.level = .statusBar  // 最前面表示
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]  // 全Spaces対応
        window.isOpaque = false  // 透明化
        window.backgroundColor = .clear  // 背景透明
        window.ignoresMouseEvents = true  // マウスイベント透過
        window.hasShadow = false  // 影なし
        
        // research.mdで推奨：フルスクリーン対応のアクセサリアプリ設定
        NSApp.setActivationPolicy(.accessory)
        
        // Core Graphics直接描画によるオーバーレイコンテンツビューを作成
        let contentView = OverlayContentView(step: step, screenSize: screenFrame.size)
        window.contentView = contentView
        
        // ウィンドウを表示
        window.orderFrontRegardless()
        print("✅ XPCサービス: オーバーレイウィンドウを表示しました")
        print("📍 XPCサービス: ステップ「\(step.text)」at (\(step.x), \(step.y))")
    }
}

// research.mdで推奨：完全なCore Graphics描画によるオーバーレイビュー
@MainActor
class OverlayContentView: NSView {
    private let step: TutorialStepData
    private let screenSize: CGSize
    
    init(step: TutorialStepData, screenSize: CGSize) {
        self.step = step
        self.screenSize = screenSize
        super.init(frame: CGRect(origin: .zero, size: screenSize))
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // research.md推奨：Core Graphicsで直接描画（SwiftUI/NSHostingViewを使わない）
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // 赤枠を描画
        let overlayRect = CGRect(
            x: step.x - step.width / 2,
            y: screenSize.height - step.y - step.height / 2,  // Y座標反転
            width: step.width,
            height: step.height
        )
        
        // 赤い枠線（research.mdの安全な描画方法）
        context.setStrokeColor(NSColor.red.cgColor)
        context.setLineWidth(4.0)
        context.stroke(overlayRect)
        
        // 半透明の赤い背景
        context.setFillColor(NSColor.red.withAlphaComponent(0.2).cgColor)
        context.fill(overlayRect)
        
        // テキストラベル
        drawText(context: context, rect: overlayRect)
        
        print("🎨 XPCサービス: 描画完了 - 矩形(\(overlayRect))")
    }
    
    private func drawText(context: CGContext, rect: CGRect) {
        let text = step.text
        let font = NSFont.boldSystemFont(ofSize: 16)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        
        // テキスト背景
        let textRect = CGRect(
            x: rect.midX - textSize.width / 2 - 8,
            y: rect.maxY + 8,
            width: textSize.width + 16,
            height: textSize.height + 8
        )
        
        context.setFillColor(NSColor.red.cgColor)
        context.fill(textRect)
        
        // テキスト描画
        let textPoint = CGPoint(
            x: textRect.midX - textSize.width / 2,
            y: textRect.midY - textSize.height / 2
        )
        
        attributedString.draw(at: textPoint)
    }
}

// research.md準拠：MainActorでのメイン実行部分
print("🚀 XPCサービス起動: OverlayXPCService")
print("📋 Info.plist設定: JoinExistingSession, ServiceType=Application, RunLoopType=NSRunLoop")

// NSApplicationを初期化
let app = NSApplication.shared

// research.mdで強調：フルスクリーン対応のアクセサリアプリ設定
_ = app.setActivationPolicy(.accessory)  // Dock非表示のアクセサリアプリ
print("✅ ActivationPolicy設定: .accessory（フルスクリーン対応）")

// XPCリスナーを設定
let delegate = OverlayXPCServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()

print("👂 XPCサービス: リスナー開始")
print("🎯 research.mdベストプラクティス適用完了")

// アプリケーションを実行
app.run()
