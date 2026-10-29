import Foundation

struct PanelGeometry:Equatable {
    let pixelWidth:Int
    let pixelHeight:Int
    init?(pixelWidth:Int,pixelHeight:Int) {
        guard (640...8192).contains(pixelWidth),(640...8192).contains(pixelHeight),
              Double(pixelWidth)/Double(pixelHeight)>=0.3,Double(pixelWidth)/Double(pixelHeight)<=3.4 else{return nil}
        self.pixelWidth=pixelWidth;self.pixelHeight=pixelHeight
    }
    var logicalWidth:Int {(pixelWidth+1)/2}
    var logicalHeight:Int {(pixelHeight+1)/2}
    var key:String {"\(pixelWidth)x\(pixelHeight)"}
    func height(forWidth width:Int)->Int {Int((Double(width)*Double(pixelHeight)/Double(pixelWidth)).rounded())}
    static let legacy=PanelGeometry(pixelWidth:2388,pixelHeight:1668)!
}

struct ResolutionChoice:Identifiable,Equatable {
    enum Role:String {case native="原生像素",comfortable="较大文字",recommended="默认大小",moreSpace="更多空间",custom="自定义"}
    let width:Int
    let height:Int
    var role:Role = .custom
    var pixelWidth:Int {width*2}
    var pixelHeight:Int {height*2}
    var id:String {"\(width)x\(height)@\(pixelWidth)x\(pixelHeight)"}
    var title:String {"\(width) × \(height) · 高清 · \(role.rawValue)"}
    static func ==(lhs:Self,rhs:Self)->Bool {lhs.width==rhs.width && lhs.height==rhs.height}
}

enum ResolutionPolicy {
    static let maximumLogical=4096
    static let maximumRenderPixels=33_554_432
    // Preserve the sizes already selected and verified by existing users.
    static let legacyChoices:[ResolutionChoice]=[
        .init(width:1194,height:834,role:.native),.init(width:1280,height:894,role:.comfortable),
        .init(width:1344,height:938,role:.recommended),.init(width:1600,height:1118,role:.moreSpace),
        .init(width:2388,height:1668,role:.moreSpace)
    ]
    static func safe(width:Int,height:Int)->Bool {
        (320...maximumLogical).contains(width) && (320...maximumLogical).contains(height) && width*height*4<=maximumRenderPixels
    }
    static func coversPanel(_ choice:ResolutionChoice,panel:PanelGeometry)->Bool {
        safe(width:choice.width,height:choice.height) && choice.pixelWidth>=panel.pixelWidth && choice.pixelHeight>=panel.pixelHeight
    }
    static func choices(for panel:PanelGeometry)->[ResolutionChoice] {
        if panel == .legacy {return legacyChoices}
        let scales:[(Double,ResolutionChoice.Role)]=[(1,.native),(1.075,.comfortable),(1.125,.recommended),(4.0/3.0,.moreSpace),(2,.moreSpace)]
        var result:[ResolutionChoice]=[]
        for (scale,role) in scales {
            let width=scale==1 ? panel.logicalWidth : (scale==2 ? panel.pixelWidth : max(panel.logicalWidth,Int((Double(panel.logicalWidth)*scale/16).rounded())*16))
            let height=scale==1 ? panel.logicalHeight : max(panel.logicalHeight,panel.height(forWidth:width))
            let choice=ResolutionChoice(width:width,height:height,role:role)
            if coversPanel(choice,panel:panel) && !result.contains(choice) {result.append(choice)}
        }
        return result
    }
    static func recommended(for panel:PanelGeometry)->ResolutionChoice? {
        let values=choices(for:panel)
        return values.first{$0.role == .recommended} ?? values.first
    }
    static func parse(_ value:String)->ResolutionChoice? {
        let logical=value.split(separator:"@",omittingEmptySubsequences:false).first ?? ""
        let parts=logical.split(separator:"x",omittingEmptySubsequences:false)
        guard parts.count==2,parts.allSatisfy({!$0.isEmpty && $0.allSatisfy({$0.isASCII && $0.isNumber})}),
              let w=Int(parts[0]),let h=Int(parts[1]),safe(width:w,height:h) else{return nil}
        let choice=ResolutionChoice(width:w,height:h)
        guard !value.contains("@") || value==choice.id else{return nil}
        return choice
    }
    static func validationMessage(width:Int,height:Int,panel:PanelGeometry?)->String? {
        guard (320...maximumLogical).contains(width),(320...maximumLogical).contains(height) else{return "桌面宽高须在 320 到 4096 之间。"}
        guard safe(width:width,height:height) else{return "这个尺寸的高清画布过大，请减小宽度或高度。"}
        guard let panel else{return "请先连接 iPad，识别屏幕能力后再设置自定义尺寸。"}
        guard coversPanel(.init(width:width,height:height),panel:panel) else {
            return "为覆盖这台 iPad 的屏幕像素，桌面至少需要 \(panel.logicalWidth) × \(panel.logicalHeight)。"
        }
        return nil
    }
}
