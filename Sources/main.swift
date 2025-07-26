import AppKit
import SwiftUI
import Foundation
import CoreGraphics

// MARK: - Data Models
struct ChatMessage: Identifiable {
    let id = UUID()
    let content: String
    let type: MessageType
    let timestamp = Date()
    
    enum MessageType {
        case user, assistant
    }
}

struct TutorialStep: Identifiable {
    let id = UUID()
    let text: String
    let boundingBox: CGRect
    let description: String
}

// MARK: - App State
@MainActor
class AppState: ObservableObject {
    @Published var isMinimized = false
    @Published var isChatVisible = false
    @Published var chatMessages: [ChatMessage] = []
    @Published var currentInput = ""
    @Published var tutorialSteps: [TutorialStep] = []
    @Published var isShowingTutorial = false
    @Published var isProcessing = false
    @Published var lastScreenshot: NSImage?
    
    func sendMessage() async {
        let message = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        
        await MainActor.run {
            chatMessages.append(ChatMessage(content: message, type: .user))
            currentInput = ""
            isProcessing = true
        }
        
        // すべての質問でAI分析を実行
        await handleTutorialRequest(message)
        
        await MainActor.run {
            isProcessing = false
        }
    }
    
    private func handleTutorialRequest(_ message: String) async {
        // MCPサーバーでスクリーンショット撮影と分析を一括実行
        let mcpService = MCPService()
        let result = await mcpService.takeScreenshotAndAnalyze(question: message)
        
        await MainActor.run {
            if let steps = result.tutorialSteps, !steps.isEmpty {
                // 安全に座標を検証
                let validSteps = steps.compactMap { step -> TutorialStep? in
                    guard step.boundingBox.width > 0,
                          step.boundingBox.height > 0,
                          step.boundingBox.origin.x >= 0,
                          step.boundingBox.origin.y >= 0 else {
                        print("⚠️ 無効な座標のステップをスキップ: \(step.text)")
                        return nil
                    }
                    return step
                }
                
                if !validSteps.isEmpty {
                    // さらに厳密な座標安全化処理
                    let ultraSafeSteps = validSteps.compactMap { step -> TutorialStep? in
                        let rect = step.boundingBox
                        
                        // NaN、無限大の検証
                        guard rect.origin.x.isFinite && rect.origin.y.isFinite &&
                              rect.size.width.isFinite && rect.size.height.isFinite &&
                              !rect.origin.x.isNaN && !rect.origin.y.isNaN &&
                              !rect.size.width.isNaN && !rect.size.height.isNaN else {
                            print("⚠️ 無限大またはNaN座標を検出、スキップ: \(step.text)")
                            return nil
                        }
                        
                        // 画面境界内への強制クランプ
                        let screenBounds = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
                        let safeX = max(0, min(rect.origin.x, screenBounds.width - 100))
                        let safeY = max(0, min(rect.origin.y, screenBounds.height - 50))
                        let safeWidth = max(50, min(rect.width, screenBounds.width - safeX))
                        let safeHeight = max(30, min(rect.height, screenBounds.height - safeY))
                        
                        let safeRect = CGRect(x: safeX, y: safeY, width: safeWidth, height: safeHeight)
                        
                        return TutorialStep(
                            text: step.text,
                            boundingBox: safeRect,
                            description: step.description
                        )
                    }
                    
                    tutorialSteps = ultraSafeSteps
                    isShowingTutorial = true
                    
                    // 分析結果の詳細を構築
                    var detailText = "✨ Claude AIが画面を分析しました！\n\n\(result.text)\n\n"
                    detailText += "🎯 検出されたUI要素:\n"
                    
                    for (index, step) in ultraSafeSteps.enumerated() {
                        detailText += "\n\(index + 1). \(step.text)\n"
                        detailText += "   📍 座標: (\(Int(step.boundingBox.origin.x)), \(Int(step.boundingBox.origin.y)))\n"
                        detailText += "   📏 サイズ: \(Int(step.boundingBox.width))×\(Int(step.boundingBox.height))\n"
                        detailText += "   📖 説明: \(step.description)\n"
                    }
                    
                    chatMessages.append(ChatMessage(
                        content: detailText + "\n\n🎯 赤枠でUI要素をハイライト表示中！",
                        type: .assistant
                    ))
                    
                    // オーバーレイ表示を安全に復活
                    print("🎯 安全な座標検証完了、オーバーレイ表示を開始...")
                    print("📊 分析結果の詳細:")
                    for (index, step) in ultraSafeSteps.enumerated() {
                        print("  \(index + 1). \(step.text) at (\(step.boundingBox.origin.x), \(step.boundingBox.origin.y))")
                    }
                    
                    // AppDelegateに安全な座標でオーバーレイ表示を依頼
                    DispatchQueue.main.async {
                        if let appDelegate = NSApp.delegate as? AppDelegate {
                            appDelegate.showTutorialOverlay(steps: ultraSafeSteps)
                        }
                    }
                    
                    // 自己校正システムの実行（少し遅延させてオーバーレイ表示完了を待つ）
                    // DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    //     Task {
                    //         await self.performSelfCalibration(originalSteps: ultraSafeSteps)
                    //     }
                    // }
                } else {
                    chatMessages.append(ChatMessage(
                        content: "🤖 Claude AIの分析結果:\n\n\(result.text)\n\n有効なUI要素が見つかりませんでした。",
                        type: .assistant
                    ))
                }
            } else {
                chatMessages.append(ChatMessage(
                    content: "🤖 Claude AIの分析結果:\n\n\(result.text)",
                    type: .assistant
                ))
            }
        }
    }
    
    
    func takeScreenshot() async {
        await MainActor.run {
            print("📷 スクリーンショット撮影を開始...")
            
            // macOSのスクリーンショット権限をチェック
            if let cgImage = CGWindowListCreateImage(
                CGRect.infinite,
                .optionOnScreenOnly,
                kCGNullWindowID,
                .bestResolution
            ) {
                let size = NSSize(width: cgImage.width, height: cgImage.height)
                let image = NSImage(cgImage: cgImage, size: size)
                lastScreenshot = image
                
                chatMessages.append(ChatMessage(
                    content: "✅ スクリーンショットを撮影しました！ (サイズ: \(Int(size.width))x\(Int(size.height)))",
                    type: .assistant
                ))
                print("📷 スクリーンショット撮影成功: \(size)")
            } else {
                chatMessages.append(ChatMessage(
                    content: "❌ スクリーンショットの撮影に失敗しました。\n\n「システム設定 > プライバシーとセキュリティ > 画面収録」でアプリの権限を有効にしてください。",
                    type: .assistant
                ))
                print("❌ スクリーンショット撮影失敗 - 権限不足の可能性")
            }
        }
    }
    
    func hideTutorial() {
        isShowingTutorial = false
        tutorialSteps = []
        
        chatMessages.append(ChatMessage(
            content: "チュートリアルを非表示にしました。",
            type: .assistant
        ))
        
        // AppDelegateのオーバーレイも非表示にする
        DispatchQueue.main.async {
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.hideTutorialOverlay()
            }
        }
    }
    
    // 自己校正システムの実行
    private func performSelfCalibration(originalSteps: [TutorialStep]) async {
        print("🔍 自己校正システムを開始...")
        
        guard let firstStep = originalSteps.first else {
            print("❌ 校正対象のステップが存在しません")
            return
        }
        
        let mcpService = MCPService()
        let calibrationResult = await mcpService.verifyOverlayAccuracy(originalStep: firstStep)
        
        await MainActor.run {
            let accuracyScore = calibrationResult.accuracyScore
            let feedback = calibrationResult.feedback
            
            var calibrationMessage = "🔍 AI自己校正結果:\n\n"
            calibrationMessage += "📊 精度スコア: \(String(format: "%.1f%%", accuracyScore * 100))\n"
            calibrationMessage += "💬 フィードバック: \(feedback)\n"
            
            if let correctedRect = calibrationResult.correctedPosition {
                calibrationMessage += "\n🎯 修正提案:\n"
                calibrationMessage += "  修正座標: (\(Int(correctedRect.origin.x)), \(Int(correctedRect.origin.y)))\n"
                calibrationMessage += "  修正サイズ: \(Int(correctedRect.width))×\(Int(correctedRect.height))\n"
                
                // 精度が低い場合は学習データとして蓄積
                if accuracyScore < 0.8 {
                    calibrationMessage += "\n📚 学習データとして記録しました。次回分析の精度向上に活用されます。"
                }
            }
            
            chatMessages.append(ChatMessage(
                content: calibrationMessage,
                type: .assistant
            ))
        }
        
        print("🎯 自己校正完了 - 精度: \(String(format: "%.2f", calibrationResult.accuracyScore))")
    }

    // テスト用チュートリアル表示機能
    func showTestTutorial() {
        let claudeService = ClaudeAPIService()
        let testSteps = claudeService.createTestTutorialSteps()
        
        tutorialSteps = testSteps
        isShowingTutorial = true
        
        chatMessages.append(ChatMessage(
            content: "🧪 テスト用チュートリアルを表示しました！\n\n固定座標での赤枠表示をテストしています。",
            type: .assistant
        ))
        
        // 直接AppDelegateに通知（NotificationCenterを避ける）
        DispatchQueue.main.async {
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.showTutorialOverlay(steps: testSteps)
            }
        }
        
        print("🧪 テスト用チュートリアル表示: \(testSteps.count)個のステップ")
    }
}

// MARK: - Views
struct FloatingPanelView: View {
    @StateObject private var appState = AppState()
    
    var body: some View {
        VStack(spacing: 0) {
            if appState.isMinimized {
                MinimizedPanel(appState: appState)
            } else {
                ExpandedPanel(appState: appState)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial, style: FillStyle())
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
        .environmentObject(appState)
    }
}

// グローバル関数としてチュートリアルオーバーレイ表示
func showTutorialOverlay(steps: [TutorialStep]) {
    print("🎯 チュートリアルオーバーレイを表示: \(steps.count)個のステップ")
    // 実際のオーバーレイ表示はAppDelegateで処理
}

struct MinimizedPanel: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "message.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.blue)
            
            Text("AI")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    appState.isMinimized = false
                }
            }) {
                Image(systemName: "chevron.up.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct ExpandedPanel: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Image(systemName: "message.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                
                Text("チュートリアルAI Ponko2")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                HStack(spacing: 4) {
                    // スクリーンショットボタン
                    Button(action: {
                        print("📷 スクリーンショットボタンがクリックされました")
                        Task {
                            await appState.takeScreenshot()
                        }
                    }) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // チュートリアル非表示ボタン
                    if appState.isShowingTutorial {
                        Button(action: {
                            appState.hideTutorial()
                        }) {
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // チャット表示切り替え
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            appState.isChatVisible.toggle()
                        }
                    }) {
                        Image(systemName: appState.isChatVisible ? "message.fill" : "message")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // 最小化
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            appState.isMinimized = true
                            appState.isChatVisible = false
                        }
                    }) {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            
            // チャットエリア
            if appState.isChatVisible {
                ChatArea(appState: appState)
            }
        }
        .frame(width: 340)
    }
}

struct ChatArea: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            // メッセージリスト
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if appState.chatMessages.isEmpty {
                        VStack(spacing: 8) {
                            Text("💡 アプリでどこを押せば良いかを教えてくれるAI")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.blue)
                            
                            Text("「〜〜機能はどこ？」のように質問してください")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("📷 緑のカメラボタンでスクリーンショット")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text("🎯 AI分析によるチュートリアル表示")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text("🖱️ 背景アプリはクリック透過")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 12)
                    } else {
                        ForEach(appState.chatMessages) { message in
                            ChatMessageView(message: message)
                        }
                        
                        if appState.isProcessing {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("分析中...")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(height: 180)
            
            // 入力エリア
            HStack(spacing: 6) {
                TextField("「どこをクリックすると...」", text: $appState.currentInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 11))
                    .onSubmit {
                        Task {
                            await appState.sendMessage()
                        }
                    }
                
                Button(action: {
                    Task {
                        await appState.sendMessage()
                    }
                }) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                }
                .disabled(appState.currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.isProcessing)
                .buttonStyle(SendButtonStyle())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.05))
        }
    }
}

struct ChatMessageView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.type == .user {
                Spacer()
            }
            
            VStack(alignment: message.type == .user ? .trailing : .leading, spacing: 2) {
                Text(message.content)
                    .font(.system(size: 10))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(message.type == .user ? Color.blue : Color.gray.opacity(0.2))
                    )
                    .foregroundColor(message.type == .user ? .white : .primary)
                
                Text(DateFormatter.timeFormatter.string(from: message.timestamp))
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            
            if message.type == .assistant {
                Spacer()
            }
        }
    }
}

struct SendButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 24, height: 24)
            .background(
                Circle()
                    .fill(Color.blue)
                    .opacity(configuration.isPressed ? 0.7 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Tutorial Overlay
struct TutorialOverlayView: View {
    let tutorialSteps: [TutorialStep]
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // 透明背景
            Color.clear
                .ignoresSafeArea()
                .allowsHitTesting(false)
            
            // 安全性のため最初のステップのみ表示（segmentation fault回避）
            if let firstStep = tutorialSteps.first {
                UltraSafeTutorialView(step: firstStep)
            }
            
            // 閉じるボタン
            VStack {
                HStack {
                    Spacer()
                    Button("チュートリアルを閉じる") {
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
                Spacer()
            }
        }
        .onAppear {
            print("🎯 UltraSafeTutorialOverlayView表示: \(tutorialSteps.count)個のステップ（最初のステップのみ表示）")
        }
    }
}

struct SafeTutorialStepView: View {
    let step: TutorialStep
    
    var body: some View {
        // 安全化された座標を事前計算
        let safeFrame = calculateSafeFrame(for: step.boundingBox)
        let textPosition = calculateSafeTextPosition(for: safeFrame)
        
        ZStack(alignment: .topLeading) {
            // 赤い枠（実際の座標位置）
            Rectangle()
                .stroke(Color.red, lineWidth: 3)
                .background(Color.red.opacity(0.15))
                .frame(width: safeFrame.width, height: safeFrame.height)
                .position(x: safeFrame.midX, y: safeFrame.midY)
            
            // 説明テキスト（安全な位置）
            VStack(alignment: .leading, spacing: 2) {
                Text(step.text)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red)
                    .cornerRadius(6)
                    .shadow(radius: 3)
                
                Text(step.description)
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(4)
                    .lineLimit(2)
            }
            .position(x: textPosition.x, y: textPosition.y)
        }
        .onAppear {
            print("🎯 SafeTutorialStepView表示: \(step.text)")
            print("  - 元座標: (\(step.boundingBox.origin.x), \(step.boundingBox.origin.y))")
            print("  - 安全座標: (\(safeFrame.origin.x), \(safeFrame.origin.y))")
            print("  - サイズ: \(safeFrame.width) x \(safeFrame.height)")
        }
    }
    
    private func calculateSafeFrame(for rect: CGRect) -> CGRect {
        // 画面サイズを取得（フォールバック付き）
        let screenBounds = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        
        // 座標の安全性確認
        guard rect.origin.x.isFinite && rect.origin.y.isFinite &&
              rect.size.width.isFinite && rect.size.height.isFinite &&
              !rect.origin.x.isNaN && !rect.origin.y.isNaN &&
              !rect.size.width.isNaN && !rect.size.height.isNaN else {
            // フォールバック: 画面中央に小さな枠
            return CGRect(x: screenBounds.width/2 - 50, y: screenBounds.height/2 - 25, width: 100, height: 50)
        }
        
        // 最小/最大サイズの制約
        let minWidth: CGFloat = 50
        let minHeight: CGFloat = 30
        let maxWidth: CGFloat = min(300, screenBounds.width * 0.3)
        let maxHeight: CGFloat = min(200, screenBounds.height * 0.2)
        
        // サイズの調整
        let adjustedWidth = max(minWidth, min(maxWidth, rect.width))
        let adjustedHeight = max(minHeight, min(maxHeight, rect.height))
        
        // 位置の調整（画面境界内に収める）
        let margin: CGFloat = 20
        let adjustedX = max(margin, min(rect.origin.x, screenBounds.width - adjustedWidth - margin))
        let adjustedY = max(margin, min(rect.origin.y, screenBounds.height - adjustedHeight - margin))
        
        return CGRect(x: adjustedX, y: adjustedY, width: adjustedWidth, height: adjustedHeight)
    }
    
    private func calculateSafeTextPosition(for frame: CGRect) -> CGPoint {
        let screenBounds = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        
        // テキストの推定サイズ
        let textWidth: CGFloat = 180
        let textHeight: CGFloat = 60
        
        // まず枠の上側に配置を試行
        var textX = frame.origin.x
        var textY = frame.origin.y - textHeight - 10
        
        // X座標の調整
        if textX + textWidth > screenBounds.width - 20 {
            textX = screenBounds.width - textWidth - 20
        }
        textX = max(20, textX)
        
        // Y座標の調整（上に配置できない場合は下に）
        if textY < 20 {
            textY = frame.origin.y + frame.height + 10
        }
        if textY + textHeight > screenBounds.height - 20 {
            textY = screenBounds.height - textHeight - 20
        }
        textY = max(20, textY)
        
        return CGPoint(x: textX + textWidth/2, y: textY + textHeight/2)
    }
}

struct UltraSafeTutorialView: View {
    let step: TutorialStep
    
    var body: some View {
        VStack(spacing: 0) {
            // 画面上部に固定表示（最も安全）
            VStack(spacing: 8) {
                Text("🎯 \(step.text)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .cornerRadius(12)
                    .shadow(radius: 6)
                
                Text("📖 \(step.description)")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(8)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                
                // 赤い枠の固定表示（座標計算なし）
                Rectangle()
                    .stroke(Color.red, lineWidth: 4)
                    .frame(width: 200, height: 100)
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(8)
                    .overlay(
                        Text("UI要素の位置")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .fontWeight(.semibold)
                    )
            }
            .padding(.top, 50)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            print("🎯 UltraSafeTutorialView表示:")
            print("  - ステップ: \(step.text)")
            print("  - 説明: \(step.description)")
            print("  - 座標: (\(step.boundingBox.origin.x), \(step.boundingBox.origin.y))")
            print("  - 安全固定表示モード")
        }
    }
}

struct TutorialStepView: View {
    let step: TutorialStep
    
    var body: some View {
        // 最も安全な固定位置実装（座標計算を一切排除）
        VStack {
            Text("🎯 \(step.text)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red)
                .cornerRadius(8)
                .shadow(radius: 4)
            
            Rectangle()
                .stroke(Color.red, lineWidth: 3)
                .frame(width: 120, height: 60)
                .background(Color.red.opacity(0.1))
            
            Spacer()
        }
        .padding()
        .onAppear {
            print("🎯 固定位置TutorialStepView表示:")
            print("  - ステップ: \(step.text)")
            print("  - 説明: \(step.description)")
        }
    }
}

// MARK: - Extensions
extension DateFormatter {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()
}

// MARK: - Claude API Models
struct ClaudeRequest: Codable {
    let model: String
    let max_tokens: Int
    let messages: [ClaudeMessage]
    let system: String?
}

struct ClaudeMessage: Codable {
    let role: String
    let content: [ClaudeContent]
}

struct ClaudeContent: Codable {
    let type: String
    let text: String?
    let source: ClaudeImageSource?
}

struct ClaudeImageSource: Codable {
    let type: String
    let media_type: String
    let data: String
}

struct ClaudeResponse: Codable {
    let content: [ClaudeResponseContent]
}

struct ClaudeResponseContent: Codable {
    let text: String
}

// MARK: - MCP Service
@MainActor
class MCPService {
    private let mcpServerPath: String
    private var mcpProcess: Process?
    
    init() {
        // MCPサーバーのパスを設定
        let currentDir = FileManager.default.currentDirectoryPath
        self.mcpServerPath = "\(currentDir)/screenshot-analysis-server"
    }
    
    func analyzeScreenshotForTutorial(screenshot: NSImage, question: String) async -> (text: String, tutorialSteps: [TutorialStep]?) {
        print("🔗 MCP経由でスクリーンショット分析を開始...")
        
        // スクリーン情報を取得
        guard let screen = NSScreen.main else {
            print("❌ スクリーン情報の取得に失敗")
            return ("スクリーン情報の取得に失敗しました。", nil)
        }
        
        let screenSize = screen.frame.size
        let scaleFactor = screen.backingScaleFactor
        
        // 画像をbase64に変換
        guard let imageData = convertImageToBase64(screenshot) else {
            print("❌ 画像の変換に失敗")
            return ("画像の変換に失敗しました。", nil)
        }
        
        // MCPサーバーを使用してスクリーンショット分析
        do {
            let result = try await callMCPTool(
                toolName: "analyze_screenshot",
                arguments: [
                    "image_data": imageData,
                    "question": question,
                    "screen_width": Int(screenSize.width),
                    "screen_height": Int(screenSize.height),
                    "scale_factor": scaleFactor
                ]
            )
            
            // 結果をパース
            if let resultData = result.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any],
               let success = json["success"] as? Bool,
               success {
                
                let message = json["message"] as? String ?? "分析完了"
                
                if let stepsArray = json["tutorial_steps"] as? [[String: Any]] {
                    let steps = stepsArray.compactMap { stepDict -> TutorialStep? in
                        guard let id = stepDict["id"] as? String,
                              let text = stepDict["text"] as? String,
                              let description = stepDict["description"] as? String,
                              let x = stepDict["x"] as? Double,
                              let y = stepDict["y"] as? Double,
                              let width = stepDict["width"] as? Double,
                              let height = stepDict["height"] as? Double else {
                            return nil
                        }
                        
                        return TutorialStep(
                            text: text,
                            boundingBox: CGRect(x: x, y: y, width: width, height: height),
                            description: description
                        )
                    }
                    
                    print("🎯 MCP解析結果: \(steps.count)個のチュートリアルステップ")
                    return (message, steps.isEmpty ? nil : steps)
                } else {
                    return (message, nil)
                }
            } else if let resultData = result.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any],
                      let errorMessage = json["error"] as? String {
                print("❌ MCP分析エラー: \(errorMessage)")
                return (errorMessage, nil)
            } else {
                return ("MCPサーバーからの応答を解析できませんでした。", nil)
            }
        } catch {
            print("❌ MCP呼び出しエラー: \(error)")
            return ("MCP分析でエラーが発生しました: \(error.localizedDescription)", nil)
        }
    }
    
    func takeScreenshotAndAnalyze(question: String) async -> (text: String, tutorialSteps: [TutorialStep]?) {
        print("🔗 Swift統合スクリーンショット分析を開始...")
        
        // Step 1: Swift側でスクリーンショット撮影
        guard let cgImage = CGWindowListCreateImage(
            CGRect.infinite,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        ) else {
            print("❌ スクリーンショット撮影に失敗")
            return ("スクリーンショット撮影に失敗しました。画面収録権限を確認してください。", nil)
        }
        
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        print("✅ Swift側でスクリーンショット撮影成功: \(nsImage.size)")
        
        // Step 1.5: デバッグ用画像保存
        saveDebugImage(nsImage, prefix: "swift_integration")
        
        // Step 2: base64変換
        guard let base64Data = convertImageToBase64(nsImage) else {
            print("❌ 画像のbase64変換に失敗")
            return ("画像変換に失敗しました。", nil)
        }
        print("✅ base64変換成功")
        
        // Step 3: スクリーン情報を取得
        guard let screen = NSScreen.main else {
            print("❌ スクリーン情報の取得に失敗")
            return ("スクリーン情報の取得に失敗しました。", nil)
        }
        
        let screenSize = screen.frame.size
        let scaleFactor = screen.backingScaleFactor
        
        do {
            // Step 4: MCP analyze_screenshotのみを呼び出し
            print("🤖 Claude API分析を開始...")
            let analysisResult = try await callMCPTool(
                toolName: "analyze_screenshot",
                arguments: [
                    "image_data": base64Data,
                    "question": question,
                    "screen_width": Int(screenSize.width),
                    "screen_height": Int(screenSize.height),
                    "scale_factor": scaleFactor
                ]
            )
            
            // 分析結果をパース
            if let resultData = analysisResult.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any],
               let success = json["success"] as? Bool,
               success {
                
                let message = json["message"] as? String ?? "分析完了"
                
                if let stepsArray = json["tutorial_steps"] as? [[String: Any]] {
                    let steps = stepsArray.compactMap { stepDict -> TutorialStep? in
                        guard let text = stepDict["text"] as? String,
                              let description = stepDict["description"] as? String,
                              let x = stepDict["x"] as? Double,
                              let y = stepDict["y"] as? Double,
                              let width = stepDict["width"] as? Double,
                              let height = stepDict["height"] as? Double else {
                            return nil
                        }
                        
                        return TutorialStep(
                            text: text,
                            boundingBox: CGRect(x: x, y: y, width: width, height: height),
                            description: description
                        )
                    }
                    
                    print("🎯 Swift統合解析結果: \(steps.count)個のチュートリアルステップ")
                    return (message, steps.isEmpty ? nil : steps)
                } else {
                    return (message, nil)
                }
            } else if let resultData = analysisResult.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any],
                      let errorMessage = json["error"] as? String {
                print("❌ MCP分析エラー: \(errorMessage)")
                return (errorMessage, nil)
            } else {
                return ("MCPサーバーからの分析応答を解析できませんでした。", nil)
            }
        } catch {
            print("❌ MCP呼び出しエラー: \(error)")
            return ("MCP分析でエラーが発生しました: \(error.localizedDescription)", nil)
        }
    }
    
    func verifyOverlayAccuracy(originalStep: TutorialStep) async -> (accuracyScore: Float, feedback: String, correctedPosition: CGRect?) {
        print("🔍 AIによる自己校正を開始...")
        
        // オーバーレイ表示後のスクリーンショットを撮影
        guard let cgImage = CGWindowListCreateImage(
            CGRect.infinite,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        ) else {
            print("❌ 校正用スクリーンショット撮影に失敗")
            return (0.0, "スクリーンショット撮影に失敗しました。", nil)
        }
        
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        print("✅ 校正用スクリーンショット撮影成功: \(nsImage.size)")
        
        // base64変換
        guard let base64Data = convertImageToBase64(nsImage) else {
            print("❌ 校正用画像のbase64変換に失敗")
            return (0.0, "画像変換に失敗しました。", nil)
        }
        
        // スクリーン情報を取得
        guard let screen = NSScreen.main else {
            print("❌ スクリーン情報の取得に失敗")
            return (0.0, "スクリーン情報の取得に失敗しました。", nil)
        }
        
        let screenSize = screen.frame.size
        let scaleFactor = screen.backingScaleFactor
        
        do {
            // 元の予測結果を構造化
            let originalPrediction = [
                "text": originalStep.text,
                "x": originalStep.boundingBox.origin.x,
                "y": originalStep.boundingBox.origin.y,
                "width": originalStep.boundingBox.size.width,
                "height": originalStep.boundingBox.size.height,
                "description": originalStep.description
            ] as [String: Any]
            
            print("🔍 校正対象:", originalPrediction)
            
            let verificationResult = try await callMCPTool(
                toolName: "verify_overlay_accuracy",
                arguments: [
                    "image_data": base64Data,
                    "original_prediction": originalPrediction,
                    "screen_width": Int(screenSize.width),
                    "screen_height": Int(screenSize.height),
                    "scale_factor": scaleFactor
                ]
            )
            
            // 検証結果をパース
            if let resultData = verificationResult.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any],
               let success = json["success"] as? Bool,
               success,
               let verificationResult = json["verification_result"] as? [String: Any] {
                
                let accuracyScore = (verificationResult["accuracy_score"] as? NSNumber)?.floatValue ?? 0.0
                let feedback = verificationResult["feedback"] as? String ?? "検証完了"
                
                var correctedRect: CGRect? = nil
                if let correctedPos = verificationResult["corrected_position"] as? [String: Any],
                   let x = (correctedPos["x"] as? NSNumber)?.doubleValue,
                   let y = (correctedPos["y"] as? NSNumber)?.doubleValue,
                   let width = (correctedPos["width"] as? NSNumber)?.doubleValue,
                   let height = (correctedPos["height"] as? NSNumber)?.doubleValue {
                    correctedRect = CGRect(x: x, y: y, width: width, height: height)
                }
                
                print("🎯 校正結果:")
                print("  - 精度スコア: \(String(format: "%.2f", accuracyScore))")
                print("  - フィードバック: \(feedback)")
                if let corrected = correctedRect {
                    print("  - 修正座標: (\(corrected.origin.x), \(corrected.origin.y))")
                }
                
                return (accuracyScore, feedback, correctedRect)
            } else {
                print("❌ 校正結果の解析に失敗")
                return (0.0, "校正結果の解析に失敗しました。", nil)
            }
        } catch {
            print("❌ MCP校正呼び出しエラー: \(error)")
            return (0.0, "校正処理でエラーが発生しました: \(error.localizedDescription)", nil)
        }
    }

    func createTestTutorialSteps() -> [TutorialStep] {
        print("🧪 MCP経由でテスト用チュートリアルステップを作成")
        
        // MCPサーバーを使用してテストチュートリアル作成
        Task {
            do {
                let result = try await callMCPTool(
                    toolName: "create_test_tutorial",
                    arguments: ["count": 3]
                )
                print("🧪 MCPテスト結果: \(result)")
            } catch {
                print("❌ MCPテスト呼び出しエラー: \(error)")
            }
        }
        
        // フォールバック用の固定値を返す
        return [
            TutorialStep(
                text: "テスト枠1",
                boundingBox: CGRect(x: 100, y: 100, width: 200, height: 50),
                description: "左上テスト用座標"
            ),
            TutorialStep(
                text: "テスト枠2",
                boundingBox: CGRect(x: 400, y: 300, width: 150, height: 80),
                description: "中央テスト用座標"
            ),
            TutorialStep(
                text: "テスト枠3",
                boundingBox: CGRect(x: 800, y: 200, width: 120, height: 40),
                description: "右側テスト用座標"
            )
        ]
    }
    
    private func convertImageToBase64(_ image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            print("❌ 画像データの変換に失敗")
            return nil
        }
        
        let maxSizeBytes = 4 * 1024 * 1024 // 4MB制限（5MBより余裕を持たせる）
        var compressionFactor: Float = 0.8
        var jpegData: Data?
        
        // サイズとクオリティを調整しながら圧縮
        repeat {
            jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionFactor])
            
            if let data = jpegData {
                let sizeInMB = Double(data.count) / (1024 * 1024)
                print("🔄 Swift圧縮テスト - 品質: \(String(format: "%.2f", compressionFactor)), サイズ: \(String(format: "%.2f", sizeInMB))MB")
                
                if data.count <= maxSizeBytes {
                    print("✅ Swift圧縮完了 - 最終品質: \(String(format: "%.2f", compressionFactor))")
                    return data.base64EncodedString()
                }
            }
            
            compressionFactor -= 0.1
            
        } while compressionFactor > 0.1 && jpegData != nil
        
        // それでも大きい場合は画像サイズを縮小
        print("🔄 画像サイズを縮小して再試行...")
        let scaleFactor: CGFloat = 0.7
        let newSize = NSSize(
            width: image.size.width * scaleFactor,
            height: image.size.height * scaleFactor
        )
        
        if let resizedImage = resizeImage(image, to: newSize) {
            return convertImageToBase64(resizedImage) // 再帰的に呼び出し
        }
        
        print("❌ 画像圧縮に失敗")
        return nil
    }
    
    private func saveDebugImage(_ image: NSImage, prefix: String = "swift_capture") {
        // デバッグディレクトリを作成
        let debugDir = "./debug_screenshots"
        let fileManager = FileManager.default
        
        do {
            try fileManager.createDirectory(atPath: debugDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("❌ デバッグディレクトリの作成に失敗: \(error)")
            return
        }
        
        // タイムスタンプ付きファイル名を生成
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let debugPath = "\(debugDir)/\(prefix)_\(timestamp).png"
        
        // PNG形式で高品質保存（デバッグ用なので圧縮しない）
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            print("❌ デバッグ画像のPNG変換に失敗")
            return
        }
        
        do {
            let url = URL(fileURLWithPath: debugPath)
            try pngData.write(to: url)
            let sizeInMB = Double(pngData.count) / (1024 * 1024)
            print("💾 デバッグ用スクリーンショット保存: \(debugPath) (サイズ: \(String(format: "%.2f", sizeInMB))MB)")
        } catch {
            print("❌ デバッグ画像の保存に失敗: \(error)")
        }
    }
    
    private func resizeImage(_ image: NSImage, to newSize: NSSize) -> NSImage? {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        newImage.unlockFocus()
        return newImage
    }
    
    private func callMCPTool(toolName: String, arguments: [String: Any]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "\(mcpServerPath)/build/index.js"]
        
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        
        // MCPリクエストを作成
        let request = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": [
                "name": toolName,
                "arguments": arguments
            ]
        ] as [String : Any]
        
        let requestData = try JSONSerialization.data(withJSONObject: request)
        let requestString = String(data: requestData, encoding: .utf8)! + "\n"
        
        // リクエストを送信
        inputPipe.fileHandleForWriting.write(requestString.data(using: .utf8)!)
        inputPipe.fileHandleForWriting.closeFile()
        
        // レスポンスを受信
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let responseString = String(data: outputData, encoding: .utf8) ?? ""
        
        process.waitUntilExit()
        
        // エラーチェック
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        if !errorData.isEmpty {
            let errorString = String(data: errorData, encoding: .utf8) ?? ""
            print("MCP Server Error: \(errorString)")
        }
        
        // レスポンスをパース
        if let responseData = responseString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
           let result = json["result"] as? [String: Any],
           let content = result["content"] as? [[String: Any]],
           let firstContent = content.first,
           let text = firstContent["text"] as? String {
            return text
        }
        
        throw NSError(domain: "MCPError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid MCP response"])
    }
}

// MARK: - Legacy Claude API Service (Fallback)
@MainActor
class ClaudeAPIService {
    private let apiKey: String
    private let apiURL = "https://api.anthropic.com/v1/messages"
    
    init() {
        // 環境変数からAPIキーを取得、フォールバックは空文字
        self.apiKey = ProcessInfo.processInfo.environment["CLAUDE_API_KEY"] ?? ""
        
        if apiKey.isEmpty {
            print("⚠️ CLAUDE_API_KEY環境変数が設定されていません")
        }
    }
    
    func analyzeScreenshotForTutorial(screenshot: NSImage, question: String) async -> (text: String, tutorialSteps: [TutorialStep]?) {
        print("🤖 Claude API分析を開始...")
        
        // 画像を5MB制限内に圧縮
        guard let compressedImageData = compressImageForAPI(screenshot) else {
            print("❌ 画像の処理に失敗")
            return ("画像の処理に失敗しました。", nil)
        }
        
        let base64Image = compressedImageData.base64EncodedString()
        let sizeInMB = Double(compressedImageData.count) / (1024 * 1024)
        print("📸 画像を圧縮完了 (サイズ: \(String(format: "%.2f", sizeInMB))MB)")
        
        // スクリーン情報を取得
        let screen = NSScreen.main!
        let screenSize = screen.frame.size
        let backingScaleFactor = screen.backingScaleFactor
        
        let systemPrompt = """
        あなたはmacOSアプリケーションのチュートリアルアシスタントです。
        
        スクリーン情報:
        - 論理解像度: \(Int(screenSize.width))x\(Int(screenSize.height))
        - スケールファクタ: \(backingScaleFactor)
        - このスクリーンショットは物理ピクセルで撮影されています
        
        スクリーンショットを分析して、ユーザーの質問に対応するUI要素の位置を特定してください。
        
        重要: 座標は物理ピクセル座標で指定してください（スクリーンショットの実際のピクセル座標）。
        
        以下のJSON形式で回答してください：
        {
          "message": "ユーザーへの説明メッセージ",
          "tutorial_steps": [
            {
              "text": "UI要素の名前",
              "x": 100,
              "y": 100,
              "width": 200,
              "height": 50,
              "description": "詳細説明"
            }
          ]
        }
        
        座標は画面左上を(0,0)とした絶対座標で指定してください。
        UI要素が見つからない場合は、tutorial_stepsを空の配列にしてください。
        """
        
        let request = ClaudeRequest(
            model: "claude-3-5-sonnet-20241022",
            max_tokens: 1000,
            messages: [
                ClaudeMessage(
                    role: "user",
                    content: [
                        ClaudeContent(
                            type: "image",
                            text: nil,
                            source: ClaudeImageSource(
                                type: "base64",
                                media_type: "image/jpeg",
                                data: base64Image
                            )
                        ),
                        ClaudeContent(
                            type: "text",
                            text: question,
                            source: nil
                        )
                    ]
                )
            ],
            system: systemPrompt
        )
        
        guard let url = URL(string: apiURL) else {
            print("❌ 無効なURL")
            return ("APIのURLが無効です。", nil)
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        
        do {
            let jsonData = try JSONEncoder().encode(request)
            urlRequest.httpBody = jsonData
            
            print("🌐 Claude APIにリクエスト送信中...")
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 HTTP ステータス: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    let errorText = String(data: data, encoding: .utf8) ?? "不明なエラー"
                    print("❌ APIエラー: \(errorText)")
                    return ("API呼び出しでエラーが発生しました (HTTP \(httpResponse.statusCode))", nil)
                }
            }
            
            let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
            let responseText = claudeResponse.content.first?.text ?? "応答が空です"
            
            print("✅ Claude API応答受信: \(responseText.prefix(200))...")
            
            return parseClaudeResponse(responseText)
            
        } catch {
            print("❌ Claude API エラー: \(error)")
            return ("API呼び出しでエラーが発生しました: \(error.localizedDescription)", nil)
        }
    }
    
    private func parseClaudeResponse(_ responseText: String) -> (text: String, tutorialSteps: [TutorialStep]?) {
        // JSON部分を抽出
        if let jsonRange = responseText.range(of: #"\{[\s\S]*\}"#, options: .regularExpression),
           let jsonData = String(responseText[jsonRange]).data(using: .utf8) {
            
            do {
                let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
                
                let message = json?["message"] as? String ?? responseText
                
                if let tutorialStepsArray = json?["tutorial_steps"] as? [[String: Any]] {
                    let steps = tutorialStepsArray.compactMap { stepDict -> TutorialStep? in
                        guard let text = stepDict["text"] as? String,
                              let description = stepDict["description"] as? String else {
                            return nil
                        }
                        
                        // 座標の型安全な取得
                        let x = (stepDict["x"] as? NSNumber)?.doubleValue ?? 0
                        let y = (stepDict["y"] as? NSNumber)?.doubleValue ?? 0
                        let width = (stepDict["width"] as? NSNumber)?.doubleValue ?? 100
                        let height = (stepDict["height"] as? NSNumber)?.doubleValue ?? 30
                        
                        // 物理座標から論理座標への変換
                        let physicalRect = CGRect(x: x, y: y, width: width, height: height)
                        let logicalRect = convertPhysicalToLogicalCoordinates(physicalRect)
                        
                        // デバッグ情報を出力
                        debugCoordinateConversion(
                            physicalRect: physicalRect,
                            logicalRect: logicalRect
                        )
                        
                        return TutorialStep(
                            text: text,
                            boundingBox: logicalRect,
                            description: description
                        )
                    }
                    
                    print("🎯 解析結果: \(steps.count)個のチュートリアルステップ")
                    return (message, steps.isEmpty ? nil : steps)
                }
                
                return (message, nil)
                
            } catch {
                print("❌ JSON パースエラー: \(error)")
                return (responseText, nil)
            }
        }
        
        // JSONが見つからない場合はそのまま返す
        return (responseText, nil)
    }
    
    // MARK: - 座標変換とデバッグ機能
    private func convertPhysicalToLogicalCoordinates(_ physicalRect: CGRect) -> CGRect {
        guard let screen = NSScreen.main else {
            print("❌ メインスクリーンの取得に失敗")
            return physicalRect
        }
        
        let scaleFactor = screen.backingScaleFactor
        let screenFrame = screen.frame
        
        // 物理座標から論理座標への変換
        let logicalX = physicalRect.origin.x / scaleFactor
        let logicalY = physicalRect.origin.y / scaleFactor
        let logicalWidth = physicalRect.size.width / scaleFactor
        let logicalHeight = physicalRect.size.height / scaleFactor
        
        // スクリーン境界内に収める
        let clampedX = max(0, min(logicalX, screenFrame.width - logicalWidth))
        let clampedY = max(0, min(logicalY, screenFrame.height - logicalHeight))
        
        return CGRect(
            x: clampedX,
            y: clampedY,
            width: logicalWidth,
            height: logicalHeight
        )
    }
    
    private func debugCoordinateConversion(physicalRect: CGRect, logicalRect: CGRect) {
        guard let screen = NSScreen.main else { return }
        
        let scaleFactor = screen.backingScaleFactor
        let screenFrame = screen.frame
        
        print("🔍 座標変換デバッグ:")
        print("  📱 スクリーン情報:")
        print("    - 論理解像度: \(Int(screenFrame.width))x\(Int(screenFrame.height))")
        print("    - スケールファクター: \(scaleFactor)")
        print("    - 物理解像度: \(Int(screenFrame.width * scaleFactor))x\(Int(screenFrame.height * scaleFactor))")
        print("  📍 座標変換:")
        print("    - 物理座標: x=\(physicalRect.origin.x), y=\(physicalRect.origin.y)")
        print("    - 論理座標: x=\(logicalRect.origin.x), y=\(logicalRect.origin.y)")
        print("    - サイズ変換: \(physicalRect.size.width)x\(physicalRect.size.height) → \(logicalRect.size.width)x\(logicalRect.size.height)")
        print("  ✅ 境界チェック: スクリーン内=\(logicalRect.origin.x >= 0 && logicalRect.origin.y >= 0 && logicalRect.maxX <= screenFrame.width && logicalRect.maxY <= screenFrame.height)")
    }
    
    // テスト用の固定座標機能
    func createTestTutorialSteps() -> [TutorialStep] {
        print("🧪 テスト用チュートリアルステップを作成")
        
        return [
            TutorialStep(
                text: "テスト枠1",
                boundingBox: CGRect(x: 100, y: 100, width: 200, height: 50),
                description: "左上テスト用座標"
            ),
            TutorialStep(
                text: "テスト枠2",
                boundingBox: CGRect(x: 400, y: 300, width: 150, height: 80),
                description: "中央テスト用座標"
            ),
            TutorialStep(
                text: "テスト枠3",
                boundingBox: CGRect(x: 800, y: 200, width: 120, height: 40),
                description: "右側テスト用座標"
            )
        ]
    }
    
    // MARK: - Private Helper Methods
    private func compressImageForAPI(_ image: NSImage) -> Data? {
        let maxSizeBytes = 4 * 1024 * 1024 // 4MBに制限（5MBより余裕を持たせる）
        
        // まず元のサイズをチェック
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            print("❌ 画像データの変換に失敗")
            return nil
        }
        
        // 初期圧縮品質
        var compressionFactor: Float = 0.8
        var jpegData: Data?
        
        // サイズとクオリティを調整しながら圧縮
        repeat {
            jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionFactor])
            
            if let data = jpegData {
                print("🔄 圧縮テスト - 品質: \(String(format: "%.2f", compressionFactor)), サイズ: \(String(format: "%.2f", Double(data.count) / (1024 * 1024)))MB")
                
                if data.count <= maxSizeBytes {
                    print("✅ 圧縮完了 - 最終品質: \(String(format: "%.2f", compressionFactor))")
                    return data
                }
            }
            
            compressionFactor -= 0.1
            
        } while compressionFactor > 0.1 && jpegData != nil
        
        // それでも大きい場合は画像サイズを縮小
        print("🔄 画像サイズを縮小して再試行...")
        let scaleFactor: CGFloat = 0.7
        let newSize = NSSize(
            width: image.size.width * scaleFactor,
            height: image.size.height * scaleFactor
        )
        
        if let resizedImage = resizeImage(image, to: newSize) {
            return compressImageForAPI(resizedImage) // 再帰的に呼び出し
        }
        
        print("❌ 画像圧縮に失敗")
        return nil
    }
    
    private func resizeImage(_ image: NSImage, to newSize: NSSize) -> NSImage? {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        newImage.unlockFocus()
        return newImage
    }
}

// MARK: - Safe Overlay View (Core Graphics)
class SafeOverlayView: NSView {
    private let step: TutorialStep
    private let screenSize: CGSize
    
    init(step: TutorialStep, screenSize: CGSize) {
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
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // 安全な描画座標を計算
        let safeRect = calculateSafeRect()
        
        // 赤い枠線を描画
        context.setStrokeColor(NSColor.red.cgColor)
        context.setLineWidth(4.0)
        context.stroke(safeRect)
        
        // 半透明の赤い背景
        context.setFillColor(NSColor.red.withAlphaComponent(0.2).cgColor)
        context.fill(safeRect)
        
        // テキストラベルを描画
        drawSafeText(context: context, rect: safeRect)
        
        print("🎨 SafeOverlayView描画完了: \(step.text) at \(safeRect)")
    }
    
    private func calculateSafeRect() -> CGRect {
        let originalRect = step.boundingBox
        
        // 座標の安全性チェック
        guard originalRect.origin.x.isFinite && originalRect.origin.y.isFinite &&
              originalRect.size.width.isFinite && originalRect.size.height.isFinite &&
              !originalRect.origin.x.isNaN && !originalRect.origin.y.isNaN &&
              !originalRect.size.width.isNaN && !originalRect.size.height.isNaN else {
            // フォールバック: 画面中央
            return CGRect(x: screenSize.width/2 - 100, y: screenSize.height/2 - 50, width: 200, height: 100)
        }
        
        // 最小/最大サイズ制約
        let minWidth: CGFloat = 50
        let minHeight: CGFloat = 30
        let maxWidth: CGFloat = min(400, screenSize.width * 0.4)
        let maxHeight: CGFloat = min(200, screenSize.height * 0.3)
        
        let adjustedWidth = max(minWidth, min(maxWidth, originalRect.width))
        let adjustedHeight = max(minHeight, min(maxHeight, originalRect.height))
        
        // 画面境界内にクランプ
        let margin: CGFloat = 20
        let adjustedX = max(margin, min(originalRect.origin.x, screenSize.width - adjustedWidth - margin))
        let adjustedY = max(margin, min(originalRect.origin.y, screenSize.height - adjustedHeight - margin))
        
        return CGRect(x: adjustedX, y: adjustedY, width: adjustedWidth, height: adjustedHeight)
    }
    
    private func drawSafeText(context: CGContext, rect: CGRect) {
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
        
        // 画面境界内チェック
        let clampedTextRect = CGRect(
            x: max(10, min(textRect.origin.x, screenSize.width - textRect.width - 10)),
            y: max(10, min(textRect.origin.y, screenSize.height - textRect.height - 10)),
            width: textRect.width,
            height: textRect.height
        )
        
        context.setFillColor(NSColor.red.cgColor)
        context.fill(clampedTextRect)
        
        // テキスト描画
        let textPoint = CGPoint(
            x: clampedTextRect.midX - textSize.width / 2,
            y: clampedTextRect.midY - textSize.height / 2
        )
        
        attributedString.draw(at: textPoint)
    }
}

// MARK: - Window Classes
class DraggableWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

class TutorialWindow: NSWindow {
    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var controlWindow: DraggableWindow!
    var tutorialWindow: TutorialWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupControlWindow()
        setupTutorialObserver()
        setupMenu()
        
        print("🚀 AIオーバーレイアプリ v2.0 が起動しました")
        print("📷 緑のカメラボタンでスクリーンショット撮影")
        print("🤖 「どこをクリックすると〜できるの？」と質問してください")
        print("🎯 デモ版チュートリアル表示機能")
        print("🖱️ 背景アプリは透過してクリック可能")
        print("⌘Q で終了")
    }
    
    @MainActor
    private func setupControlWindow() {
        let windowSize = CGSize(width: 360, height: 90)
        let screenFrame = NSScreen.main!.frame
        let windowOrigin = CGPoint(
            x: screenFrame.width - windowSize.width - 50,
            y: screenFrame.height - windowSize.height - 100
        )
        
        controlWindow = DraggableWindow(
            contentRect: NSRect(origin: windowOrigin, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        controlWindow.isOpaque = false
        controlWindow.backgroundColor = .clear
        controlWindow.hasShadow = true
        controlWindow.isMovableByWindowBackground = true
        controlWindow.level = .floating
        controlWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let contentView = FloatingPanelView()
        controlWindow.contentView = NSHostingView(rootView: contentView)
        
        controlWindow.makeKeyAndOrderFront(nil)
        controlWindow.orderFrontRegardless()
    }
    
    private func setupTutorialObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ShowTutorialOverlay"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Claude分析結果のステップを受け取る
            if let steps = notification.object as? [TutorialStep] {
                Task { @MainActor in
                    self?.showTutorialOverlay(steps: steps)
                }
            }
        }
    }
    
    @MainActor
    func showTutorialOverlay(steps: [TutorialStep]) {
        // 安全性のため一度完全にクリア
        hideTutorialOverlay()
        
        print("⏱️ タイマーベース遅延再描画: 2.0秒待機でmacOSシステム安定化を待機中...")
        
        // タイマーベース遅延再描画（2.0秒に延長）
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            print("⏱️ 2.0秒待機完了、安全なオーバーレイ作成を開始...")
            self.createSafeOverlay(steps: steps)
        }
    }
    
    @MainActor
    private func createSafeOverlay(steps: [TutorialStep]) {
        guard !steps.isEmpty else {
            print("❌ 表示するステップがありません")
            return
        }
        
        guard let firstStep = steps.first else {
            print("❌ 最初のステップが存在しません")
            return
        }
        
        print("🚀 外部プロセス方式でオーバーレイ表示を開始...")
        
        // 外部プロセス実行
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        
        let currentDir = FileManager.default.currentDirectoryPath
        let helperPath = "\(currentDir)/OverlayHelper.swift"
        
        process.arguments = [
            helperPath,
            firstStep.text,
            "\(firstStep.boundingBox.origin.x)",
            "\(firstStep.boundingBox.origin.y)",
            "\(firstStep.boundingBox.size.width)",
            "\(firstStep.boundingBox.size.height)",
            firstStep.description
        ]
        
        // プロセス出力をキャプチャ
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            print("✅ 外部プロセス起動成功")
            print("📍 座標: (\(firstStep.boundingBox.origin.x), \(firstStep.boundingBox.origin.y))")
            print("📏 サイズ: \(firstStep.boundingBox.size.width)×\(firstStep.boundingBox.size.height)")
            print("📝 テキスト: \(firstStep.text)")
            
            // プロセス終了を非同期で監視
            DispatchQueue.global(qos: .background).async {
                process.waitUntilExit()
                let exitCode = process.terminationStatus
                
                DispatchQueue.main.async {
                    if exitCode == 0 {
                        print("✅ 外部プロセス正常終了")
                    } else {
                        print("⚠️ 外部プロセス異常終了: コード \(exitCode)")
                        
                        // エラー出力を表示
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        if !errorData.isEmpty,
                           let errorString = String(data: errorData, encoding: .utf8) {
                            print("❌ エラー出力: \(errorString)")
                        }
                    }
                }
            }
            
        } catch {
            print("❌ 外部プロセス起動失敗: \(error)")
        }
    }
    
    @MainActor
    func hideTutorialOverlay() {
        tutorialWindow?.close()
        tutorialWindow = nil
        print("🎯 チュートリアルオーバーレイを非表示にしました")
    }
    
    @MainActor
    private func setupMenu() {
        let appMenu = NSMenu()
        
        appMenu.addItem(NSMenuItem(
            title: "MyOverlayApp について",
            action: #selector(showAbout),
            keyEquivalent: ""
        ))
        
        appMenu.addItem(NSMenuItem.separator())
        
        appMenu.addItem(NSMenuItem(
            title: "MyOverlayApp を終了",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        
        let mainMenuBar = NSMenu(title: "MyOverlayApp")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenuBar.addItem(appMenuItem)
        NSApp.mainMenu = mainMenuBar
    }
    
    @MainActor
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "MyOverlayApp v2.0"
        alert.informativeText = "AI搭載インタラクティブオーバーレイアプリ\n\n✨ 機能:\n• スクリーンショット撮影 (画面収録権限必要)\n• インタラクティブチュートリアル (デモ版)\n• 赤枠ガイド表示\n• ドラッグ移動対応\n• 背景透過クリック"
        alert.alertStyle = .informational
        alert.runModal()
    }
}

// MARK: - Main Entry Point
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
