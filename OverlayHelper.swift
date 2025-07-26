#!/usr/bin/env swift

import AppKit
import SwiftUI
import Foundation

// MARK: - Data Models
struct TutorialStep: Codable {
    let text: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let description: String
}

// MARK: - Simple Overlay Window
class SimpleOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }
}

// MARK: - Simple Overlay View (Pure AppKit)
class SimpleOverlayView: NSView {
    private let step: TutorialStep
    
    init(step: TutorialStep) {
        self.step = step
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // 受け取った座標で赤枠を描画
        let overlayRect = CGRect(x: step.x, y: step.y, width: step.width, height: step.height)
        
        // 赤い枠線
        context.setStrokeColor(NSColor.red.cgColor)
        context.setLineWidth(4.0)
        context.stroke(overlayRect)
        
        // 半透明の赤い背景
        context.setFillColor(NSColor.red.withAlphaComponent(0.2).cgColor)
        context.fill(overlayRect)
        
        // テキストラベル
        drawText(context: context, rect: overlayRect)
        
        print("🎨 外部プロセス - オーバーレイ描画完了: \(step.text) at \(overlayRect)")
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
            y: rect.maxY + 10,
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

// MARK: - Main Function
func main() {
    let args = CommandLine.arguments
    
    // 引数チェック (text, x, y, width, height, description)
    guard args.count >= 7 else {
        print("❌ 引数不足: text x y width height description が必要")
        exit(1)
    }
    
    let text = args[1]
    let x = Double(args[2]) ?? 100
    let y = Double(args[3]) ?? 100
    let width = Double(args[4]) ?? 200
    let height = Double(args[5]) ?? 50
    let description = args[6]
    
    let step = TutorialStep(
        text: text,
        x: x,
        y: y,
        width: width,
        height: height,
        description: description
    )
    
    print("🚀 外部プロセス - オーバーレイヘルパー起動")
    print("📍 表示座標: (\(x), \(y)), サイズ: \(width)×\(height)")
    print("📝 テキスト: \(text)")
    
    // NSApplication初期化
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory) // 背景プロセスとして実行
    
    // フルスクリーンウィンドウ作成
    guard let screen = NSScreen.main else {
        print("❌ スクリーン情報取得失敗")
        exit(1)
    }
    
    let screenFrame = screen.frame
    
    let window = SimpleOverlayWindow(
        contentRect: screenFrame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    
    // ウィンドウ設定
    window.level = .normal // .normalレベルで安全性確認
    window.isOpaque = false
    window.backgroundColor = .clear
    window.ignoresMouseEvents = true
    
    // オーバーレイビューを設定
    let overlayView = SimpleOverlayView(step: step)
    overlayView.frame = screenFrame
    window.contentView = overlayView
    
    // ウィンドウ表示
    window.orderFrontRegardless()
    
    print("✅ 外部プロセス - オーバーレイウィンドウ表示完了")
    
    // 5秒後に自動終了
    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
        print("⏰ 外部プロセス - 5秒経過、自動終了")
        app.terminate(nil)
    }
    
    // イベントループ開始
    app.run()
}

// エントリーポイント
main()
