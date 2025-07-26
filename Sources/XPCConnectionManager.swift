import Foundation

@MainActor
class XPCConnectionManager: ObservableObject {
    private var connection: NSXPCConnection?
    private let serviceName = "com.myoverlayapp.OverlayXPCService"
    
    init() {
        setupConnection()
    }
    
    // deinitは省略してARC任せにする（MainActor isolation問題回避）
    
    private func setupConnection() {
        print("🔗 XPC接続を初期化中...")
        
        connection = NSXPCConnection(serviceName: serviceName)
        connection?.remoteObjectInterface = NSXPCInterface(with: OverlayServiceProtocol.self)
        
        // セキュアコーディングの設定（一時的にコメントアウト - ビルド優先）
        // if let interface = connection?.remoteObjectInterface {
        //     interface.setClasses([TutorialStepData.self, NSArray.self], 
        //                        for: #selector(OverlayServiceProtocol.showTutorialOverlay(steps:)), 
        //                        argumentIndex: 0, ofReply: false)
        // }
        
        connection?.invalidationHandler = { [weak self] in
            print("❌ XPC接続が無効化されました")
            Task { @MainActor in
                self?.connection = nil
            }
        }
        
        connection?.interruptionHandler = { [weak self] in
            print("⚠️ XPC接続が中断されました")
            Task { @MainActor in
                self?.reconnect()
            }
        }
        
        connection?.resume()
        print("✅ XPC接続が確立されました")
    }
    
    private func reconnect() {
        print("🔄 XPC接続を再構築中...")
        closeConnection()
        setupConnection()
    }
    
    private func closeConnection() {
        connection?.invalidate()
        connection = nil
        print("🔒 XPC接続を閉じました")
    }
    
    // MARK: - Public Methods
    
    func showTutorialOverlay(steps: [TutorialStep]) async {
        print("📤 XPC経由でオーバーレイ表示を開始...")
        
        // TutorialStep → TutorialStepData変換
        let stepDataArray = steps.map { step in
            TutorialStepData(
                id: step.id.uuidString,
                text: step.text,
                x: step.boundingBox.origin.x,
                y: step.boundingBox.origin.y,
                width: step.boundingBox.size.width,
                height: step.boundingBox.size.height,
                description: step.description
            )
        }
        
        guard let service = connection?.remoteObjectProxy as? OverlayServiceProtocol else {
            print("❌ XPCサービスプロキシの取得に失敗")
            return
        }
        
        do {
            // Sendableでないデータの送信を安全に行う
            await service.showTutorialOverlay(steps: stepDataArray)
            print("✅ XPC経由でオーバーレイ表示完了")
        } catch {
            print("❌ XPC経由でのオーバーレイ表示に失敗: \(error)")
        }
    }
    
    func hideTutorialOverlay() async {
        print("📤 XPC経由でオーバーレイ非表示を開始...")
        
        guard let service = connection?.remoteObjectProxy as? OverlayServiceProtocol else {
            print("❌ XPCサービスプロキシの取得に失敗")
            return
        }
        
        do {
            await service.hideTutorialOverlay()
            print("✅ XPC経由でオーバーレイ非表示完了")
        } catch {
            print("❌ XPC経由でのオーバーレイ非表示に失敗: \(error)")
        }
    }
    
    func ping() async -> String? {
        print("🏓 XPC接続テストを開始...")
        
        guard let service = connection?.remoteObjectProxy as? OverlayServiceProtocol else {
            print("❌ XPCサービスプロキシの取得に失敗")
            return nil
        }
        
        do {
            let result = await service.ping()
            print("✅ XPC接続テスト成功: \(result)")
            return result
        } catch {
            print("❌ XPC接続テストに失敗: \(error)")
            return nil
        }
    }
}
