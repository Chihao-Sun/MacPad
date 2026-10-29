import Foundation

@main enum ResolutionPolicyTests {
    static var assertions=0
    static func check(_ condition:@autoclosure ()->Bool,_ message:String) {
        assertions+=1;precondition(condition(),message)
    }
    static func main() {
        let fixtures=[(2388,1668),(2420,1668),(2732,2048),(2752,2064),(2360,1640),(2266,1488),(2160,1620),(2048,1536),(1668,2388),(1488,2266)]
        for (width,height) in fixtures {
            let panel=PanelGeometry(pixelWidth:width,pixelHeight:height)!
            let values=ResolutionPolicy.choices(for:panel)
            check(!values.isEmpty,"A normal panel needs choices")
            check(Set(values.map(\.id)).count==values.count,"Choice identifiers must be unique")
            check(values.first?.width==panel.logicalWidth,"First width follows panel pixels")
            check(values.first?.height==panel.logicalHeight,"First height follows panel pixels")
            check(ResolutionPolicy.recommended(for:panel) != nil,"Each panel needs a default")
            for value in values {
                check(ResolutionPolicy.coversPanel(value,panel:panel),"Every choice covers the panel")
                check(value.pixelWidth==value.width*2 && value.pixelHeight==value.height*2,"Choices use real HiDPI backing")
                check(ResolutionPolicy.parse(value.id)==value,"Saved choices round-trip")
                check(abs(Double(value.width)/Double(value.height)-Double(width)/Double(height))<0.004,"Choices follow panel aspect ratio")
            }
        }
        let legacy=ResolutionPolicy.choices(for:.legacy)
        check(legacy.map(\.id)==["1194x834@2388x1668","1280x894@2560x1788","1344x938@2688x1876","1600x1118@3200x2236","2388x1668@4776x3336"],"Existing verified sizes must remain unchanged")
        check(ResolutionPolicy.recommended(for:.legacy)?.id=="1344x938@2688x1876","Keep existing default")
        let larger=PanelGeometry(pixelWidth:2752,pixelHeight:2064)!
        check(ResolutionPolicy.recommended(for:larger)?.id != ResolutionPolicy.recommended(for:.legacy)?.id,"Different panels get different defaults")
        for text in ["","0x0","-1x834","999999999999999999999x834","1344x938@1x1","1344x938@@2688x1876","８００x８００","4097x1000","4096x4096","1344x938suffix"] {
            check(ResolutionPolicy.parse(text)==nil,"Reject malformed or oversized preference")
        }
        check(ResolutionPolicy.parse("1344x938")?.id=="1344x938@2688x1876","Migrate older preference format")
        check(!ResolutionPolicy.safe(width:Int.max,height:834),"No overflow for untrusted width")
        check(!ResolutionPolicy.safe(width:834,height:Int.max),"No overflow for untrusted height")
        check(ResolutionPolicy.validationMessage(width:800,height:559,panel:.legacy) != nil,"Do not label undersized backing as panel-filling HD")
        check(ResolutionPolicy.validationMessage(width:1536,height:1152,panel:larger)==nil,"Accept valid custom desktop")
        check(ResolutionPolicy.validationMessage(width:4096,height:4096,panel:larger) != nil,"Cap framebuffer area")
        check(ResolutionPolicy.validationMessage(width:1344,height:938,panel:nil) != nil,"Unknown panel requires discovery")
        check(PanelGeometry(pixelWidth:0,pixelHeight:1668)==nil,"Reject missing dimensions")
        check(PanelGeometry(pixelWidth:Int.max,pixelHeight:1668)==nil,"Reject invalid panel dimensions")
        check(PanelGeometry(pixelWidth:8192,pixelHeight:640)==nil,"Reject implausible panel aspect")
        let bounded=PanelGeometry(pixelWidth:8192,pixelHeight:4096)!
        check(ResolutionPolicy.choices(for:bounded).count==1,"Large panel gets bounded choices")
        print("PASS: \(assertions) adaptive-panel, aspect, HiDPI, migration and framebuffer-bound assertions; geometry fixtures are not real-device acceptance")
    }
}
