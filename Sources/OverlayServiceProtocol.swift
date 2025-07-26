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
