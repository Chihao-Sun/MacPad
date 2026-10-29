import AppKit
import SwiftUI
import ServiceManagement
import Carbon

struct DisplaySnapshot {
    let rows: [[String:Any]]
    var ipad: Bool { rows.contains { $0["kind"] as? String == "sidecar" } }
    var others: [String] { rows.filter { $0["kind"] as? String == "other" }.compactMap { $0["name"] as? String } }
    static func read() -> DisplaySnapshot {
        let names = Dictionary(uniqueKeysWithValues:NSScreen.screens.compactMap { screen -> (UInt32,String)? in
            guard let n=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else{return nil}
            return (n.uint32Value,screen.localizedName)
        })
        var ids=[CGDirectDisplayID](repeating:0,count:32), count:UInt32=0
        guard CGGetOnlineDisplayList(32,&ids,&count) == .success else{return DisplaySnapshot(rows:[])}
        return DisplaySnapshot(rows:ids.prefix(Int(count)).filter{$0 != 0}.map { id in
            let vendor=CGDisplayVendorNumber(id), model=CGDisplayModelNumber(id)
            let name=names[id] ?? "显示器 \(id)"
            // Apple Sidecar has an AirPlay vendor and 'iPad' product code even
            // when it uses USB. Do not infer its transport from the screen name.
            let sidecar=(vendor==0x6161706c && model==0x69506164) || name.localizedCaseInsensitiveContains("sidecar")
            let ours=vendor==0x4d50
            let virtual=(MPBridge.displayTraits(id)["virtual"] as? NSNumber)?.boolValue ?? false
            let kind=sidecar ? "sidecar" : (ours ? "macpadVirtual" : (virtual ? "otherVirtual" : "other"))
            // Unknown displays count as other: avoid taking over an existing
            // desktop. This is not a universal hardware/virtual display detector.
            return ["id":id,"name":name,"kind":kind,"active":CGDisplayIsActive(id) != 0,"main":CGDisplayIsMain(id) != 0,"mirrors":CGDisplayMirrorsDisplay(id)]
        })
    }
}

extension ResolutionChoice {
    static func matching(_ mode:CGDisplayMode)->ResolutionChoice? {
        guard ResolutionPolicy.safe(width:mode.width,height:mode.height),mode.pixelWidth==mode.width*2,mode.pixelHeight==mode.height*2 else{return nil}
        return ResolutionChoice(width:mode.width,height:mode.height)
    }
}

struct ConnectionEvent:Identifiable {
    let id=UUID()
    let time:Date
    let title:String
    let detail:String
    let symbol:String
    let warning:Bool
}

@MainActor final class MacPadModel: ObservableObject {
    @Published var names:[String]=[]
    @Published var selection=""
    @Published var usbCount=0
    @Published var status="连接 iPad，开始使用"
    @Published var detail="解锁 iPad，并用数据线直接连接这台 Mac。"
    @Published var busy=false
    @Published var hasIPadScreen=false
    @Published var virtualID:UInt32=0
    @Published var otherDisplays:[String]=[]
    @Published var mirrored=false
    @Published var configuredTransport:Int?
    @Published var switchingTransport=false
    @Published private(set) var transportChoice:TransportChoice = .automatic
    @Published var transportMessage=""
    @Published var automaticTransport=(UserDefaults.standard.object(forKey:"automaticTransport") as? Bool) ?? true {
        didSet {UserDefaults.standard.set(automaticTransport,forKey:"automaticTransport");nextTransportAttempt = .distantPast;scheduleTick(after:0.2)}
    }
    @Published var resolutionChoices:[ResolutionChoice]=[]
    @Published var selectedResolution=""
    @Published private(set) var nativePanel:PanelGeometry?
    @Published private(set) var panelSource="unknown"
    private var panelReadDisplay:UInt32=0
    private var panelReadDevice=""
    private var panelRetryAfter=Date.distantPast
    private var pendingPanelResolution:ResolutionChoice?
    private var resolutionDisplay:UInt32=0
    @Published var autoConnect=UserDefaults.standard.bool(forKey:"autoConnect") {
        didSet {UserDefaults.standard.set(autoConnect,forKey:"autoConnect"); paused=false;attempts=0;requestGate.resume();nextAttempt = .distantPast;if autoConnect {scheduleTick(after:0.1)}}
    }
    @Published var loginEnabled=SMAppService.mainApp.status == .enabled
    @Published var logs:[String]=[]
    @Published var events:[ConnectionEvent]=[]
    @Published var adjustingResolution=false
    @Published var resolutionMessage=""
    private var pendingResolution:ResolutionChoice?
    private var resolutionRequest=UUID()
    private var timer:Timer?
    private var attempts=0
    private var discoveryAttempts=0
    private var automaticPhase=""
    private var cableChangedAt=Date()
    private var nextTransportAttempt=Date.distantPast
    private var migrationID=UUID()
    private var resumeAfterMigration=false
    private var connectionTarget:ConnectionTransport?
    private var manualChoiceCablePresent:Bool?
    private var manualFallback:Int?
    private var pendingMigrationTarget:ConnectionTransport?
    private var migrationCablePresent=false
    private var disconnectedSince:Date?
    private var recoveryStarted:Date?
    private var recoveryMatchedSince:Date?
    private var recoveryReason=""
    private var lastRecoveryDuration:TimeInterval?
    private var lastDiscovery=Date.distantPast
    private var lastDiscoveryDuration:TimeInterval=0
    private var lastRequestDuration:TimeInterval=0
    private var rapidRecovery:Bool {recoveryStarted.map{Date().timeIntervalSince($0)<30} ?? false}
    var launchContext="unknown"
    private var lastConnectionTrigger="none"
    private var requestID=UUID()
    private var requestGate=ConnectionRequestGate()
    private var discoveredNames=Set<String>()
    private var newlyDiscovered=Set<String>()
    private var healthySince:Date?
    private var paused=false
    private var nextAttempt=Date.distantPast
    private var headlessSince:Date?
    private var lastDiagnosticSignature:Data?
    private var lastLogText=""
    private var pendingTick:DispatchWorkItem?
    private var pendingEnvironment:DispatchWorkItem?
    private var sleeping=false
    private var nextMirrorAttempt=Date.distantPast
    private var snapshot=DisplaySnapshot(rows:[])
    private let started=Date()
    private let diagnosticDirectory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("MacPad",isDirectory:true)
    init() {
        refresh(discover:true,hardware:true)
        log("MacPad \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "") 启动")
        // Device/display changes drive reconciliation. A tolerant 30-second
        // watchdog covers missed notifications without continuous discovery.
        timer=Timer.scheduledTimer(withTimeInterval:30,repeats:true) { [weak self] _ in
            Task { @MainActor in
                guard let self else{return}
                self.refresh(discover:!self.hasIPadScreen && !self.rapidRecovery,hardware:true);self.tick()
            }
        }
        timer?.tolerance=5
        _=MPBridge.startUSBMonitoring { [weak self] in
            Task { @MainActor in self?.environmentChanged(discover:self?.selection.isEmpty ?? true) }
        }
        NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.environmentChanged(discover:false) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in
                guard let self else{return}
                self.sleeping=true;self.pendingTick?.cancel();self.timer?.fireDate = .distantFuture
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in
                guard let self else{return}
                self.sleeping=false;self.paused=false;self.attempts=0;self.requestGate.resume();self.headlessSince=nil;self.nextAttempt = .distantPast
                self.transportChoice = .automatic;self.manualChoiceCablePresent=nil;self.manualFallback=nil
                self.timer?.fireDate=Date().addingTimeInterval(30);self.environmentChanged(discover:true)
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.sessionDidBecomeActiveNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.environmentChanged(discover:true) }
        }
        scheduleTick(after:4.5)
    }
    func scheduleTick(after delay:TimeInterval) {
        pendingTick?.cancel()
        let work=DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.pendingTick=nil;self?.tick() }
        }
        pendingTick=work;DispatchQueue.main.asyncAfter(deadline:.now()+max(delay,0.1),execute:work)
    }
    func environmentChanged(discover:Bool) {
        panelReadDisplay=0
        pendingEnvironment?.cancel()
        let work=DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self,!self.sleeping else{return}
                self.refresh(discover:discover,hardware:true);self.tick()
            }
        }
        pendingEnvironment=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.4,execute:work)
    }
    func log(_ text:String) {
        let now=Date()
        logs.append("\(now.formatted(date:.omitted,time:.standard))  \(text)")
        let event:(String,String,String,Bool)?
        if text.contains("高清显示大小：") {event=("显示大小已调整",text.replacingOccurrences(of:"高清显示大小：",with:""),"textformat.size",false)}
        else if text.contains("检测到 USB") {event=("iPad 已插入","已检测到数据线连接。","cable.connector",false)}
        else if text.contains("已镜像") {event=("桌面已连接","iPad 和 Mac 显示同一个桌面。","ipad.landscape",false)}
        else if text.contains("切换连接方式：") {event=("正在切换连接",text.replacingOccurrences(of:"切换连接方式：",with:""),"arrow.triangle.2.circlepath",false)}
        else if text.contains("连接已恢复，耗时") {event=("连接已恢复",text,"checkmark.circle",false)}
        else if text.contains("显示器已断开") {event=("iPad 已断开","自动连接开启时，会尝试恢复桌面。","ipad.landscape",false)}
        else if text.contains("已启用登录") {event=("登录后自动启动","MacPad 会在菜单栏静默运行。","power",false)}
        else if text.contains("MacPad ") {event=("MacPad 已启动","正在检查 iPad 和桌面连接。","app",false)}
        else if text.contains("失败") || text.contains("超时") || text.contains("系统返回") {event=("连接需要检查",text,"exclamationmark.triangle",true)}
        else {event=nil}
        if let event {
            events.append(ConnectionEvent(time:now,title:event.0,detail:event.1,symbol:event.2,warning:event.3))
            if events.count>40 {events.removeFirst(events.count-40)}
        }
        if logs.count>80 {logs.removeFirst(logs.count-80)}
    }
    func refresh(discover:Bool=false,hardware:Bool=false,forceDiscovery:Bool=false) {
        if discover && (forceDiscovery || names.isEmpty || selection.isEmpty || (!hasIPadScreen && !rapidRecovery && Date().timeIntervalSince(lastDiscovery)>60)) {
            let began=Date()
            let devices=MPBridge.devices()
            let found=Array(Set(devices.compactMap{$0["name"] as? String})).sorted()
            let discovered=Set(devices.filter{($0["discovered"] as? NSNumber)?.boolValue == true}.compactMap{$0["name"] as? String})
            newlyDiscovered=discovered.subtracting(discoveredNames);discoveredNames=discovered
            lastDiscovery=Date();lastDiscoveryDuration=Date().timeIntervalSince(began)
            if lastDiscoveryDuration>0.2 {log(String(format:"系统设备发现耗时 %.3f 秒",lastDiscoveryDuration))}
            if names != found && (!found.isEmpty || names.isEmpty || forceDiscovery) {names=found}
        }
        if !names.contains(selection) {
            let saved=UserDefaults.standard.string(forKey:"selectedDevice") ?? ""
            selection=names.contains(saved) ? saved : (names.count==1 ? names[0] : "")
        }
        if newlyDiscovered.contains(selection) {
            requestGate.resume();nextAttempt = .distantPast
        }
        newlyDiscovered.removeAll()
        let previousUSB=usbCount
        if hardware {let count=Int(MPBridge.usbIPadCount());if count != usbCount {usbCount=count}}
        if (previousUSB>0) != (usbCount>0) {
            requestGate.resume();nextAttempt = .distantPast
            cableChangedAt=Date();nextTransportAttempt = .distantPast
            if (hasIPadScreen || resumeAfterMigration) && !paused && automaticTransport {beginRecovery("线缆变化")}
        }
        if previousUSB==0 && usbCount>0 {attempts=0;paused=false;nextAttempt = .distantPast;log("检测到 USB iPad")}
        if previousUSB>0 && usbCount==0 {log("USB 数据线已拔出");nextAttempt = .distantPast}
        snapshot=DisplaySnapshot.read()
        if snapshot.ipad,(MPBridge.connectionInfo(forName:selection)["connected"] as? NSNumber)?.boolValue != true,
           let active=names.first(where:{(MPBridge.connectionInfo(forName:$0)["connected"] as? NSNumber)?.boolValue == true}) {selection=active}
        let wasConnected=hasIPadScreen
        if hasIPadScreen != snapshot.ipad {hasIPadScreen=snapshot.ipad}
        if otherDisplays != snapshot.others {otherDisplays=snapshot.others}
        let owned=MPBridge.virtualDisplayID();if virtualID != owned {virtualID=owned}
        let ipad=snapshot.rows.first(where:{$0["kind"] as? String == "sidecar"})?["id"] as? UInt32 ?? 0
        refreshPanel(ipad)
        let virtuals=snapshot.rows.filter{$0["kind"] as? String == "macpadVirtual"}.compactMap{$0["id"] as? UInt32}
        let mirror=ipad != 0 && virtualID != 0 && CGDisplayMirrorsDisplay(virtualID)==0 && CGDisplayMirrorsDisplay(ipad)==virtualID && virtuals.filter{$0 != virtualID}.allSatisfy{CGDisplayMirrorsDisplay($0)==virtualID}
        if mirrored != mirror {mirrored=mirror}
        refreshResolutions(virtualID)
        if otherDisplays.isEmpty {if headlessSince==nil {headlessSince=Date()}}
        else {headlessSince=nil}
        if hasIPadScreen {
            let info=MPBridge.connectionInfo(forName:selection)
            let transport=(info["configuredTransport"] as? NSNumber)?.intValue
            if configuredTransport != transport {configuredTransport=transport}
            if mirror,(info["connected"] as? NSNumber)?.boolValue == true {
                if healthySince==nil {healthySince=Date()}
                if Date().timeIntervalSince(healthySince!)>=2 {requestGate.confirmHealthy()}
            } else {healthySince=nil}
            if !wasConnected {log("系统已检测到 iPad 随航显示器")}
            if !switchingTransport {
                if recoveryStarted==nil {if busy {busy=false};requestID=UUID();attempts=0;resumeAfterMigration=false}
                if status != "iPad 已连接" {status="iPad 已连接"}
            }
            if !wasConnected {
                pendingTick?.cancel();pendingTick=nil
                nextTransportAttempt=Date().addingTimeInterval(rapidRecovery ? 0 : 5)
                if recoveryStarted != nil {scheduleTick(after:0.15)}
            }
            let description=otherDisplays.isEmpty ? "当前没有实体显示器，iPad 正在显示 Mac 桌面。" : "Mac 桌面已连接到 iPad。"
            if !switchingTransport && detail != description {detail=description}
        } else {
            healthySince=nil
            configuredTransport=nil
            recoveryMatchedSince=nil
            // The disconnect callback can precede the display-offline event.
            // Derive paused copy here as well, rather than retaining the old
            // connected headline until a later callback happens to refresh it.
            if paused {
                status="已断开 iPad"
                detail="自动连接已暂停。桌面设置已保留，点“连接”即可恢复。"
            } else if wasConnected && !busy && !switchingTransport {
                status="正在恢复 iPad 连接"
                detail="画面连接暂时中断，正在尝试恢复。"
            }
            if wasConnected {log("iPad 显示器已断开");nextAttempt=Date().addingTimeInterval(rapidRecovery ? 0.25 : 2)}
        }
    }
    func refreshResolutions(_ source:UInt32) {
        guard source != 0 else {resolutionDisplay=0;return}
        resolutionDisplay=source
        if resolutionChoices.isEmpty {resolutionChoices=nativePanel.map(ResolutionPolicy.choices) ?? ResolutionPolicy.legacyChoices}
        guard !adjustingResolution,let mode=CGDisplayCopyDisplayMode(source),let actual=ResolutionChoice.matching(mode) else{return}
        if !resolutionChoices.contains(actual) {
            guard let panel=nativePanel,ResolutionPolicy.coversPanel(actual,panel:panel) else{return}
            resolutionChoices.append(actual)
        }
        if selectedResolution != actual.id {selectedResolution=actual.id}
    }
    var nativePanelDescription:String {
        guard let panel=nativePanel else{return hasIPadScreen ? "未识别，使用兼容档位" : "连接后自动识别"}
        return "\(panel.pixelWidth) × \(panel.pixelHeight) · " + (panelSource=="cached" ? "上次识别" : "系统识别")
    }
    var resolutionFootnote:String {
        guard let panel=nativePanel else{return hasIPadScreen ? "尚未取得 iPad 原生像素，当前使用兼容档位，暂不能确认面板像素覆盖。" : "连接后会读取 iPad 的原生像素与比例，再生成适合这块屏幕的高清档位。"}
        if let choice=resolutionChoices.first(where:{$0.id==selectedResolution}) {
            return "iPad 原生像素 \(panel.pixelWidth) × \(panel.pixelHeight)。当前高清渲染 \(choice.pixelWidth) × \(choice.pixelHeight)，可按文字大小与桌面空间选择。"
        }
        return "显示大小已按这台 iPad 的屏幕比例生成，所有档位均使用高清渲染。"
    }
    private func refreshPanel(_ display:UInt32) {
        let changedDevice=panelReadDevice != selection
        if display==0 {
            panelReadDisplay=0
            if changedDevice {
                panelReadDevice=selection
                let saved=UserDefaults.standard.dictionary(forKey:"nativePanels")?[selection] as? [String:Int]
                nativePanel=saved.flatMap{PanelGeometry(pixelWidth:$0["width"] ?? 0,pixelHeight:$0["height"] ?? 0)}
                panelSource=nativePanel == nil ? "unknown" : "cached"
                resolutionChoices=nativePanel.map(ResolutionPolicy.choices) ?? ResolutionPolicy.legacyChoices
                pendingPanelResolution=nil
            }
            return
        }
        guard changedDevice || panelReadDisplay != display else{return}
        guard changedDevice || Date()>=panelRetryAfter else{return}
        let values=MPBridge.nativePanel(forDisplay:display)
        guard let w=(values["width"] as? NSNumber)?.intValue,let h=(values["height"] as? NSNumber)?.intValue,
              let geometry=PanelGeometry(pixelWidth:w,pixelHeight:h),!ResolutionPolicy.choices(for:geometry).isEmpty else {
            panelRetryAfter=Date().addingTimeInterval(5);return
        }
        let changed=changedDevice || geometry != nativePanel || resolutionChoices.isEmpty
        let cached=UserDefaults.standard.dictionary(forKey:"nativePanels")?[selection] as? [String:Int]
        let cachedGeometry=cached.flatMap{PanelGeometry(pixelWidth:$0["width"] ?? 0,pixelHeight:$0["height"] ?? 0)}
        panelReadDisplay=display;panelReadDevice=selection;panelRetryAfter = .distantPast
        nativePanel=geometry;panelSource=values["source"] as? String ?? "native-mode"
        if !selection.isEmpty {
            var cache=UserDefaults.standard.dictionary(forKey:"nativePanels") ?? [:]
            let item=["width":w,"height":h]
            if cache[selection] as? [String:Int] != item {cache[selection]=item;UserDefaults.standard.set(cache,forKey:"nativePanels")}
        }
        guard changed else{return}
        resolutionChoices=ResolutionPolicy.choices(for:geometry)
        let samePanel=cachedGeometry == nil || cachedGeometry == geometry
        let saved=(samePanel ? UserDefaults.standard.dictionary(forKey:"displaySizesByDevice")?[selection] as? String : nil)
            ?? (!UserDefaults.standard.bool(forKey:"resolutionProfileMigrationCompleted") && geometry == .legacy ? UserDefaults.standard.string(forKey:"displaySize") : nil)
        let preferred=saved.flatMap(ResolutionPolicy.parse).flatMap{ResolutionPolicy.coversPanel($0,panel:geometry) ? $0 : nil}
            ?? ResolutionPolicy.recommended(for:geometry)
        if let preferred {
            if !resolutionChoices.contains(preferred){resolutionChoices.append(preferred)}
            pendingPanelResolution=preferred
            resolutionMessage="正在按 iPad 屏幕适配…";scheduleTick(after:0.15)
        }
        log("已识别 iPad 原生像素：\(w) × \(h)，高清档位 \(resolutionChoices.count) 个")
    }
    private func rememberResolution(_ choice:ResolutionChoice) {
        selectedResolution=choice.id;UserDefaults.standard.set(choice.id,forKey:"displaySize")
        if nativePanel != nil {UserDefaults.standard.set(true,forKey:"resolutionProfileMigrationCompleted")}
        if !selection.isEmpty {
            var sizes=UserDefaults.standard.dictionary(forKey:"displaySizesByDevice") ?? [:]
            if sizes[selection] as? String != choice.id {sizes[selection]=choice.id;UserDefaults.standard.set(sizes,forKey:"displaySizesByDevice")}
        }
    }
    func customResolution(width:String,height:String)->String? {
        guard hasIPadScreen,!busy,!adjustingResolution,!switchingTransport else{return "请等待 iPad 连接稳定后再调整显示大小。"}
        guard let w=Int(width),let h=Int(height) else{return "请输入整数宽度和高度。"}
        if let error=ResolutionPolicy.validationMessage(width:w,height:h,panel:nativePanel){return error}
        let choice=ResolutionChoice(width:w,height:h)
        if !resolutionChoices.contains(choice){resolutionChoices.append(choice)}
        pendingPanelResolution=nil;applyResolution(choice);return nil
    }
    func setResolution(_ id:String) {
        guard !adjustingResolution,let choice=resolutionChoices.first(where:{$0.id==id}) else{return}
        pendingPanelResolution=nil
        applyResolution(choice)
    }
    private func applyResolution(_ choice:ResolutionChoice) {
        guard resolutionDisplay != 0 else{return}
        if let mode=CGDisplayCopyDisplayMode(virtualID),ResolutionChoice.matching(mode)==choice {
            refresh()
            if mirrored {rememberResolution(choice);resolutionMessage=""}
            else {pendingPanelResolution=choice;scheduleTick(after:max(0.5,nextMirrorAttempt.timeIntervalSinceNow))}
            return
        }
        adjustingResolution=true;resolutionMessage="正在调整显示大小…"
        let request=UUID();resolutionRequest=request;pendingResolution=choice
        do {
            try MPBridge.setVirtualPixelWidth(UInt(choice.pixelWidth),height:UInt(choice.pixelHeight))
            virtualID=MPBridge.virtualDisplayID();resolutionDisplay=virtualID
            nextMirrorAttempt = .distantPast
            finishResolution(request,choice:choice,attempt:0)
        } catch {adjustingResolution=false;pendingResolution=nil;resolutionMessage="未能调整显示大小，请重试。";log("显示大小调整失败：\(error.localizedDescription)")}
    }
    private func finishResolution(_ request:UUID,choice:ResolutionChoice,attempt:Int) {
        guard request==resolutionRequest else{return}
        refresh();maintainMirroring();refresh()
        if let actual=CGDisplayCopyDisplayMode(virtualID),ResolutionChoice.matching(actual)==choice,mirrored {
            rememberResolution(choice)
            adjustingResolution=false;pendingResolution=nil;resolutionMessage=""
            MPBridge.releasePreviousVirtuals()
            log("高清显示大小：\(choice.title)，渲染 \(choice.pixelWidth)×\(choice.pixelHeight)")
            writeDiagnostics(force:true);return
        }
        if attempt>=12 {
            MPBridge.restorePreviousVirtual()
            virtualID=MPBridge.virtualDisplayID();resolutionDisplay=virtualID;nextMirrorAttempt = .distantPast
            adjustingResolution=false;pendingResolution=nil
            refresh();maintainMirroring();refresh()
            resolutionMessage="调整未完成，已保留原显示大小。"
            log("显示大小调整失败，保留原桌面");writeDiagnostics(force:true);return
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) { [weak self] in self?.finishResolution(request,choice:choice,attempt:attempt+1) }
    }
    @discardableResult func ensureVirtual() -> Bool {
        guard virtualID==0 else{return true}
        do {try MPBridge.createVirtual();virtualID=MPBridge.virtualDisplayID();log("虚拟屏幕已创建并由本进程保留");return true}
        catch {status="虚拟屏幕创建失败";detail=error.localizedDescription;log(detail);return false}
    }
    func tick() {
        guard !sleeping else{return}
        refresh()
        reconcileManualChoiceWithCable()
        defer {writeDiagnostics()}
        if hasIPadScreen {
            maintainMirroring()
            if !adjustingResolution,!switchingTransport,virtualID != 0,let choice=pendingPanelResolution {
                pendingPanelResolution=nil;applyResolution(choice)
            }
            let ipad=snapshot.rows.first(where:{$0["kind"] as? String == "sidecar"})?["id"] as? UInt32 ?? 0
            if !adjustingResolution,ipad != 0 && virtualID != 0 && CGDisplayMirrorsDisplay(ipad)==virtualID,
               let mode=CGDisplayCopyDisplayMode(virtualID),ResolutionChoice.matching(mode) != nil {
                MPBridge.releasePreviousVirtuals()
            }
            reconcileTransport()
            confirmRecoveryIfReady()
        }
        if !hasIPadScreen && requestGate.suspended && !busy {
            status="等待 iPad 重新就绪"
            detail=requestGate.pending == nil ? "连续连接未成功，已停止重复请求。请解锁 iPad 后重插数据线，或点“连接”重试。" : "上一次系统连接仍未结束，已暂停重复请求。请等待系统完成。"
            traceAutomatic("waiting-for-device-change")
            return
        }
        // A transport handover resumes the desktop that was already in use,
        // including a manually connected session with an external display.
        if resumeAfterMigration && !hasIPadScreen && !busy && !paused {
            let delay=nextAttempt.timeIntervalSinceNow
            if delay>0 {scheduleTick(after:delay)}
            else {connect(manual:false,trigger:"transport-switch")}
            return
        }
        guard autoConnect && otherDisplays.isEmpty else {
            traceAutomatic(autoConnect ? "external-display" : "disabled")
            if !hasIPadScreen && !busy && autoConnect {status="正在使用其他显示器";detail="拔掉外接显示器后，将自动尝试连接 iPad。"}
            return
        }
        // Let hot-plug and login display enumeration settle. Retain a virtual
        // display before checking for iPad, so a headless login has a canvas.
        let remaining=4-Date().timeIntervalSince(headlessSince ?? Date())
        guard remaining<=0 else {traceAutomatic("settling");scheduleTick(after:remaining+0.1);return}
        guard ensureVirtual() else {return}
        if selection.isEmpty {refresh(discover:true)}
        let action=ConnectionPolicy.action(enabled:autoConnect,otherDisplay:!otherDisplays.isEmpty,connected:hasIPadScreen,busy:busy,paused:paused,settling:false,knownDevice:!selection.isEmpty,retryIn:nextAttempt.timeIntervalSinceNow)
        switch action {
        case .idle:traceAutomatic(hasIPadScreen ? "connected" : (paused ? "user-paused" : "request-in-flight"))
        case .externalDisplay:traceAutomatic("external-display")
        case .settle:break
        case .wait(let delay):traceAutomatic("retry-backoff");scheduleTick(after:delay)
        case .discover:
            discoveryAttempts+=1
            let delay=ConnectionPolicy.discoveryDelay(attempt:discoveryAttempts)
            nextAttempt=Date().addingTimeInterval(delay)
            status="等待发现 iPad";detail="请解锁 iPad。有线连接请插好数据线；无线连接需开启 Wi-Fi、蓝牙和接力。"
            traceAutomatic("discovering-device");scheduleTick(after:delay)
        case .connect:
            discoveryAttempts=0;traceAutomatic(usbCount>0 ? "request-wired" : "request-system-wireless")
            connect(manual:false)
        }
    }
    private func traceAutomatic(_ phase:String) {
        guard automaticPhase != phase else{return}
        automaticPhase=phase
        log("自动连接阶段：\(phase)，USB=\(usbCount)，候选=\(names.count)")
    }
    var transportDescription:String {
        if switchingTransport || (resumeAfterMigration && busy) {return "正在切换…"}
        guard hasIPadScreen else{return "未连接"}
        if configuredTransport==2 {return "USB-C 有线"}
        if configuredTransport==1 || (configuredTransport==0 && usbCount==0) {return "无线"}
        return "系统自动"
    }
    var automaticChoiceTitle:String {hasIPadScreen ? "自动（\(transportDescription)）" : "自动（有线优先）"}
    func chooseTransport(_ choice:TransportChoice) {
        guard !busy,!switchingTransport,!adjustingResolution,requestGate.pending==nil else{return}
        requestGate.resume()
        refresh(hardware:true)
        guard choice != .wired || usbCount>0 else {transportMessage="请先连接 USB-C 数据线。";return}
        let previous=transportChoice
        transportChoice=choice;manualChoiceCablePresent=choice == .automatic ? nil : (usbCount>0)
        paused=false;attempts=0;transportMessage="";nextTransportAttempt = .distantPast
        if !hasIPadScreen {beginRecovery("手动选择",reset:true);connect(manual:true,trigger:"manual-transport");return}
        let expected=TransportPolicy.expected(choice:choice,usbPresent:usbCount>0)
        // An explicit return to Automatic creates a mobile system session.
        // The manual override itself is never persisted to the next login.
        if configuredTransport==expected && !(choice == .automatic && previous != .automatic) {writeDiagnostics(force:true);return}
        manualFallback=configuredTransport
        let target=TransportPolicy.request(choice:choice,usbPresent:usbCount>0,recovering:false)
        beginTransportMigration(target,manual:true)
    }
    private func reconcileManualChoiceWithCable() {
        guard let atSelection=manualChoiceCablePresent,Date().timeIntervalSince(cableChangedAt)>=0.6,
              atSelection != (usbCount>0) else{return}
        transportChoice = .automatic;manualChoiceCablePresent=nil;manualFallback=nil;transportMessage=""
        pendingMigrationTarget=nil
        log("线缆状态变化，恢复自动有线优先")
    }
    private func beginRecovery(_ reason:String,reset:Bool=false) {
        if reset || recoveryStarted==nil {recoveryStarted=Date();recoveryReason=reason}
        recoveryMatchedSince=nil;resumeAfterMigration=true
    }
    private func confirmRecoveryIfReady() {
        guard let began=recoveryStarted,!switchingTransport else{return}
        let expected=TransportPolicy.expected(choice:transportChoice,usbPresent:usbCount>0)
        guard hasIPadScreen,mirrored,configuredTransport==expected else {recoveryMatchedSince=nil;return}
        if recoveryMatchedSince==nil {recoveryMatchedSince=Date()}
        guard Date().timeIntervalSince(recoveryMatchedSince!)>=0.8 else {scheduleTick(after:0.2);return}
        lastRecoveryDuration=Date().timeIntervalSince(began)
        log(String(format:"连接已恢复，耗时 %.2f 秒（%@）",lastRecoveryDuration!,recoveryReason))
        recoveryStarted=nil;recoveryMatchedSince=nil;resumeAfterMigration=false;manualFallback=nil
        busy=false;requestID=UUID();attempts=0
    }
    private func restoreManualFallbackIfNeeded() {
        guard let fallback=manualFallback else{return}
        manualFallback=nil
        transportChoice=fallback==1 ? .wireless : .automatic
        manualChoiceCablePresent=fallback==1 ? (usbCount>0) : nil
        pendingMigrationTarget=fallback==2 && usbCount>0 ? .wired : .wireless
        transportMessage="切换未完成，正在恢复上一次可用的连接。"
        log("手动切换失败，恢复上一次可用连接")
    }
    private func reconcileTransport() {
        guard !adjustingResolution,requestGate.pending==nil,!requestGate.suspended else{return}
        let remaining=0.6-Date().timeIntervalSince(cableChangedAt)
        if remaining>0 {scheduleTick(after:remaining+0.1);return}
        let wait=nextTransportAttempt.timeIntervalSinceNow
        let target=TransportPolicy.migration(enabled:automaticTransport || transportChoice != .automatic,connected:hasIPadScreen,busy:busy,
            paused:paused,usbPresent:usbCount>0,configuredTransport:configuredTransport,settled:true,retryIn:wait,choice:transportChoice)
        guard let target else {
            if automaticTransport && wait>0 && !busy && !paused {scheduleTick(after:wait)}
            return
        }
        let grace=TransportPolicy.graceRemaining(elapsed:Date().timeIntervalSince(cableChangedAt),choice:transportChoice)
        if grace>0 {scheduleTick(after:min(grace,0.25));return}
        beginTransportMigration(target)
    }
    private func beginTransportMigration(_ target:ConnectionTransport,manual:Bool=false) {
        // The virtual canvas stays alive through the system's disconnect and
        // reconnect. Neither resolution nor mirroring preferences are reset.
        guard ensureVirtual(),!selection.isEmpty else{return}
        let id=UUID();migrationID=id;requestID=UUID()
        beginRecovery(manual ? "手动选择" : "自动接续",reset:manual)
        pendingMigrationTarget=target;migrationCablePresent=usbCount>0;disconnectedSince=nil
        switchingTransport=true;busy=true;resumeAfterMigration=true
        nextTransportAttempt=Date().addingTimeInterval(60)
        status="正在切换为\(target.title)连接";detail="虚拟桌面已保留，画面可能短暂中断。"
        log("切换连接方式：\(target.title)，保留当前高清镜像桌面")
        writeDiagnostics(force:true)
        MPBridge.disconnectName(selection) { [weak self] error in
            Task { @MainActor in
                guard let self,self.migrationID==id,self.switchingTransport else{return}
                self.refresh()
                if let error,self.hasIPadScreen {self.finishMigrationFailure(error,id:id);return}
                self.waitForMigrationDisconnect(id:id,remaining:80)
            }
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+12) { [weak self] in
            guard let self,self.migrationID==id,self.switchingTransport else{return}
            self.refresh()
            self.finishMigrationFailure("系统暂未完成连接切换，继续保留当前桌面并重试。",id:id)
        }
    }
    private func waitForMigrationDisconnect(id:UUID,remaining:Int) {
        guard migrationID==id,switchingTransport else{return}
        refresh()
        let nativeConnected=(MPBridge.connectionInfo(forName:selection)["connected"] as? NSNumber)?.boolValue ?? false
        if !hasIPadScreen && !nativeConnected {
            if disconnectedSince==nil {disconnectedSince=Date()}
            if Date().timeIntervalSince(disconnectedSince!)>=0.6 {resumeMigratingDesktop(id:id);return}
        } else {disconnectedSince=nil}
        guard remaining>0 else {finishMigrationFailure("系统断开超时，继续保留当前连接。",id:id);return}
        DispatchQueue.main.asyncAfter(deadline:.now()+0.1) { [weak self] in self?.waitForMigrationDisconnect(id:id,remaining:remaining-1) }
    }
    private func resumeMigratingDesktop(id:UUID) {
        guard migrationID==id else{return}
        switchingTransport=false;busy=false;nextAttempt = .distantPast
        // Re-read the cable after the disconnect; rapid unplug/replug should
        // reconnect using the newest state rather than the obsolete request.
        refresh(hardware:true)
        if migrationCablePresent != (usbCount>0) {transportChoice = .automatic;manualChoiceCablePresent=nil;pendingMigrationTarget=nil}
        let target=pendingMigrationTarget;pendingMigrationTarget=nil
        connect(manual:false,trigger:"transport-switch",requested:target)
    }
    private func finishMigrationFailure(_ error:String,id:UUID) {
        guard migrationID==id else{return}
        migrationID=UUID();switchingTransport=false;busy=false
        resumeAfterMigration = !hasIPadScreen
        restoreManualFallbackIfNeeded()
        detail=error;log("连接切换失败：\(error)")
        nextAttempt=Date().addingTimeInterval(rapidRecovery ? 0.4 : 5)
        scheduleTick(after:rapidRecovery ? 0.4 : 5);writeDiagnostics(force:true)
    }
    private func configureMirrorDesktop() -> CGError {
        guard virtualID != 0 else{return .invalidOperation}
        let displays=DisplaySnapshot.read().rows
        let targets=displays.filter { row in
            let kind=row["kind"] as? String
            return kind=="macpadVirtual" || kind=="sidecar"
        }.compactMap{$0["id"] as? UInt32}.filter{$0 != virtualID}
        var config:CGDisplayConfigRef?
        let begin=CGBeginDisplayConfiguration(&config)
        guard begin == .success,let config else{return begin}
        // The retained 2x virtual display is the source. iPad and any previous
        // MacPad host mirror that one desktop, so no cursor can escape to a
        // hidden extension. Change source and mode in one atomic transaction.
        var result=CGConfigureDisplayMirrorOfDisplay(config,virtualID,kCGNullDirectDisplay)
        for target in targets where result == .success {result=CGConfigureDisplayMirrorOfDisplay(config,target,kCGNullDirectDisplay)}
        for target in targets where result == .success {result=CGConfigureDisplayMirrorOfDisplay(config,target,virtualID)}
        if result == .success {return CGCompleteDisplayConfiguration(config,.forSession)}
        CGCancelDisplayConfiguration(config);return result
    }
    func maintainMirroring() {
        guard Date()>=nextMirrorAttempt,virtualID != 0 else{return}
        let ipad=snapshot.rows.first(where:{$0["kind"] as? String == "sidecar"})?["id"] as? UInt32 ?? 0
        guard ipad != 0,CGDisplayIsOnline(virtualID) != 0,CGDisplayCopyDisplayMode(virtualID) != nil else{return}
        let virtuals=snapshot.rows.filter{$0["kind"] as? String == "macpadVirtual"}.compactMap{$0["id"] as? UInt32}
        guard CGDisplayMirrorsDisplay(virtualID) != 0 || CGDisplayMirrorsDisplay(ipad) != virtualID || virtuals.filter({$0 != virtualID}).contains(where:{CGDisplayMirrorsDisplay($0) != virtualID}) else{return}
        nextMirrorAttempt=Date().addingTimeInterval(adjustingResolution ? 0.5 : 15)
        let result=configureMirrorDesktop()
        log(result == .success ? "iPad 已镜像高清虚拟桌面" : "镜像设置失败，系统错误 \(result.rawValue)")
    }
    func connect(manual:Bool=true,trigger:String?=nil,requested:ConnectionTransport?=nil) {
        refresh(discover:selection.isEmpty,hardware:true)
        guard !hasIPadScreen else {return}
        guard !busy else{return}
        guard requestGate.pending==nil else {
            status="正在等待系统连接结束";detail="上一次请求尚未返回，暂不重复连接。";return
        }
        if manual {requestGate.resume()}
        guard requestGate.canStart else {return}
        if transportChoice == .wired && usbCount==0 {transportChoice = .automatic;manualChoiceCablePresent=nil}
        if manual {paused=false;attempts=0}
        guard !selection.isEmpty else {status="请选择 iPad";detail="若列表为空，请检查 Apple 账户与 iPad 信任状态。";return}
        guard ensureVirtual() else{return}
        UserDefaults.standard.set(selection,forKey:"selectedDevice")
        busy=true;attempts+=1
        let target=requested ?? pendingMigrationTarget ?? TransportPolicy.request(choice:transportChoice,usbPresent:usbCount>0,recovering:rapidRecovery)
        pendingMigrationTarget=nil;connectionTarget=target
        lastConnectionTrigger=trigger ?? (manual ? "manual" : "automatic")
        log("\(manual ? "手动" : "自动")发起\(target.title)随航，第 \(attempts) 次，USB=\(usbCount)")
        status="正在连接 iPad";detail="保持 iPad 解锁，正在等待系统随航。"
        let id=UUID();requestID=id
        DispatchQueue.main.asyncAfter(deadline:.now()+(rapidRecovery ? 0 : 1)) { [weak self] in
            guard let self,self.requestID==id else{return}
            self.refresh()
            guard !self.hasIPadScreen,self.requestID==id else{return}
            guard self.requestGate.begin(id) else {self.busy=false;return}
            let callBegan=Date()
            MPBridge.connectName(self.selection,transport:target.systemValue) { [weak self] error in
                Task { @MainActor in
                    guard let self else{return}
                    // Retire the native token even when a display event has
                    // invalidated this request's UI generation in the meantime.
                    self.requestGate.complete(id)
                    self.lastRequestDuration=Date().timeIntervalSince(callBegan)
                    self.log(String(format:"系统连接请求回调 %.3f 秒（%@）",self.lastRequestDuration,target.title))
                    guard self.requestID==id else{return}
                    self.busy=false
                    self.refresh()
                    let retry=ConnectionPolicy.retryDelay(attempt:self.attempts,rapidRecovery:self.rapidRecovery)
                    self.nextAttempt=Date().addingTimeInterval(error == nil ? max(2,retry) : retry)
                    if let error,(!self.hasIPadScreen || self.configuredTransport != TransportPolicy.expected(choice:self.transportChoice,usbPresent:self.usbCount>0)) {
                        self.restoreManualFallbackIfNeeded()
                        self.log("系统返回：\(error)")
                    }
                    self.scheduleTick(after:max(self.nextAttempt.timeIntervalSinceNow,0.15))
                    // Actual connected display wins over an 'already in use'
                    // response from a raced or repeated connection request.
                    guard !self.hasIPadScreen else{return}
                    if let error {self.status=self.requestGate.suspended ? "等待 iPad 重新就绪" : "等待重试连接";self.detail=error}
                    else {self.status="正在建立显示画面";self.detail="系统已接收请求，等待 iPad 显示器上线。";self.log("系统连接请求完成")}
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+25) { [weak self] in
            guard let self,self.requestID==id,self.busy else{return}
            self.refresh()
            guard !self.hasIPadScreen else{return}
            self.requestGate.timedOut(id);self.busy=false
            self.restoreManualFallbackIfNeeded()
            let delay=ConnectionPolicy.retryDelay(attempt:self.attempts,timedOut:true,rapidRecovery:self.rapidRecovery)
            self.nextAttempt=Date().addingTimeInterval(delay)
            self.status="正在等待系统连接结束";self.detail="连接超时，但系统请求仍在处理中，已暂停重复请求。"
            self.log("系统连接超时，等待原请求结束，暂不重复连接")
            self.writeDiagnostics(force:true)
        }
    }
    func disconnect() {
        paused=true;requestID=UUID();migrationID=UUID();busy=false;switchingTransport=false;resumeAfterMigration=false
        recoveryStarted=nil;recoveryMatchedSince=nil;manualFallback=nil;pendingMigrationTarget=nil
        transportMessage="";status="正在断开 iPad"
        MPBridge.disconnectName(selection) { [weak self] error in
            Task { @MainActor in
                guard let self else{return}
                self.refresh()
                if !self.hasIPadScreen {
                    self.status="已断开 iPad"
                    self.detail="自动连接已暂停。桌面设置已保留，点“连接”即可恢复。"
                } else if let error {self.detail=error;self.log("断开未完成：\(error)")}
                self.writeDiagnostics(force:true)
            }
        }
        writeDiagnostics(force:true)
    }
    func setLogin(_ enabled:Bool) {
        do {
            if enabled {
                // Refresh an existing registration after moving from a build
                // directory to the installed app's fixed path.
                if SMAppService.mainApp.status != .enabled {try SMAppService.mainApp.register()}
            } else {try SMAppService.mainApp.unregister()}
            loginEnabled=SMAppService.mainApp.status == .enabled
            if enabled && !loginEnabled {detail="请在系统设置的登录项中允许 MacPad。"}
            log(loginEnabled ? "已启用登录后启动" : "登录后启动尚未启用")
        } catch {loginEnabled=SMAppService.mainApp.status == .enabled;detail=error.localizedDescription;log("登录项设置失败：\(error.localizedDescription)")}
        writeDiagnostics(force:true)
    }
    func writeDiagnostics(force:Bool=false) {
        let render=CGDisplayCopyDisplayMode(virtualID)
        var record:[String:Any]=["version":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") ?? "unknown","build":Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") ?? "unknown","pid":ProcessInfo.processInfo.processIdentifier,"started":ISO8601DateFormatter().string(from:started),"appPath":Bundle.main.bundlePath,"status":status,"usbIPadCount":usbCount,"iPadConnected":hasIPadScreen,"mirrored":mirrored,"displaySize":selectedResolution,"virtualDisplayID":virtualID,"otherDisplayCount":otherDisplays.count,"autoConnectWhenHeadless":autoConnect,"loginEnabled":SMAppService.mainApp.status == .enabled,"busy":busy,"adjustingResolution":adjustingResolution,"resolutionMessage":resolutionMessage,"retryPaused":paused,"controlWindowVisible":NSApp.windows.contains{$0.title=="MacPad" && $0.isVisible},"activationPolicy":NSApp.activationPolicy().rawValue,"launchContext":launchContext,"automaticPhase":automaticPhase,"lastConnectionTrigger":lastConnectionTrigger,"connectionAttemptCount":attempts,"displays":snapshot.rows]
        record["automaticTransport"]=automaticTransport;record["switchingTransport"]=switchingTransport
        record["connectionMethod"]=transportDescription;record["configuredTransport"]=configuredTransport ?? -1
        record["requestedTransport"]=connectionTarget?.rawValue ?? "none"
        record["resumeAfterMigration"]=resumeAfterMigration
        record["transportChoice"]=transportChoice.rawValue
        record["rapidRecovery"]=rapidRecovery
        record["nativeRequestPending"]=requestGate.pending != nil
        record["automaticRetrySuspended"]=requestGate.suspended
        record["nativeAttemptsInEpoch"]=requestGate.attempts
        record["deviceDiscoveryDurationMs"]=Int(lastDiscoveryDuration*1000)
        record["lastRequestDurationMs"]=Int(lastRequestDuration*1000)
        if let duration=lastRecoveryDuration {record["lastRecoveryDurationMs"]=Int(duration*1000)}
        if let render {record["renderMode"]=["width":render.width,"height":render.height,"pixelWidth":render.pixelWidth,"pixelHeight":render.pixelHeight,"is2x":render.pixelWidth>=render.width*2 && render.pixelHeight>=render.height*2]}
        record["availableHDModes"]=resolutionChoices.map{["id":$0.id,"width":$0.width,"height":$0.height,"pixelWidth":$0.pixelWidth,"pixelHeight":$0.pixelHeight]}
        if let panel=nativePanel {record["nativePanel"]=["width":panel.pixelWidth,"height":panel.pixelHeight,"source":panelSource]}
        guard let signature=try? JSONSerialization.data(withJSONObject:record,options:[.sortedKeys]),force || signature != lastDiagnosticSignature else{return}
        lastDiagnosticSignature=signature
        record["checked"]=ISO8601DateFormatter().string(from:Date())
        do {
            try FileManager.default.createDirectory(at:diagnosticDirectory,withIntermediateDirectories:true)
            try JSONSerialization.data(withJSONObject:record,options:[.prettyPrinted,.sortedKeys]).write(to:diagnosticDirectory.appendingPathComponent("status.json"),options:.atomic)
            let text=logs.joined(separator:"\n")
            if text != lastLogText {try text.write(to:diagnosticDirectory.appendingPathComponent("latest-session.log"),atomically:true,encoding:.utf8);lastLogText=text}
        } catch { /* A diagnostic write must never interrupt a display session. */ }
    }
}

enum MacPadArtwork {
    static let app:NSImage = {
        if let url=Bundle.main.url(forResource:"MacPadIcon",withExtension:"png"),let image=NSImage(contentsOf:url) {return image}
        return NSImage(systemSymbolName:"ipad.landscape",accessibilityDescription:"MacPad") ?? NSImage(size:NSSize(width:56,height:56))
    }()
    static let menuBar:NSImage = {
        let image=NSImage(size:NSSize(width:40,height:23))
        for scale in [1,2,3] {
            if let url=Bundle.main.url(forResource:"MacPadMenuBar@\(scale)x",withExtension:"png"),
               let data=try? Data(contentsOf:url),let rep=NSBitmapImageRep(data:data) {rep.size=NSSize(width:40,height:23);image.addRepresentation(rep)}
        }
        image.isTemplate=false;image.accessibilityDescription="MacPad"
        return image
    }()
}

@MainActor final class MenuBarPill:NSView {
    let popup:NSMenu
    private var pressed=false
    override var isFlipped:Bool {true}
    private var pillFrame:NSRect {let h=min(23,bounds.height);return NSRect(x:0,y:(bounds.height-h)/2,width:40,height:h)}
    init(frame:NSRect,menu:NSMenu) {
        popup=menu;super.init(frame:frame)
        setAccessibilityElement(true);setAccessibilityRole(.menuBarItem)
        setAccessibilityLabel("MacPad")
    }
    required init?(coder:NSCoder){nil}
    override func draw(_ dirtyRect:NSRect) {
        MacPadArtwork.menuBar.draw(in:pillFrame,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        if pressed {
            NSColor.black.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect:pillFrame,xRadius:12,yRadius:12).fill()
        }
    }
    override func hitTest(_ point:NSPoint)->NSView? {
        let local=convert(point,from:superview)
        return NSBezierPath(roundedRect:pillFrame,xRadius:12,yRadius:12).contains(local) ? self : nil
    }
    override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
    override func mouseDown(with event:NSEvent){openMenu()}
    override func rightMouseDown(with event:NSEvent){openMenu()}
    override func accessibilityPerformPress()->Bool {openMenu();return true}
    private func openMenu() {
        pressed=true;needsDisplay=true
        popup.popUp(positioning:nil,at:NSPoint(x:0,y:pillFrame.maxY+2),in:self)
        pressed=false;needsDisplay=true
    }
}

struct MacPadMark:View {
    var body:some View {
        Image(nsImage:MacPadArtwork.app).resizable().interpolation(.high).scaledToFit()
            .frame(width:56,height:56).accessibilityLabel("MacPad")
    }
}
enum MacPadPane:Hashable {case display,automation,activity}

struct SidebarMaterial:NSViewRepresentable {
    func makeNSView(context:Context)->NSVisualEffectView {
        let view=NSVisualEffectView();view.material = .sidebar;view.blendingMode = .behindWindow;view.state = .followsWindowActiveState;return view
    }
    func updateNSView(_ view:NSVisualEffectView,context:Context){}
}

struct MacPadView:View {
    @ObservedObject var model:MacPadModel
    @State private var pane:MacPadPane? = .display
    @State private var showCustomResolution=false
    @State private var customWidth=""
    @State private var customHeight=""
    @State private var keepPanelRatio=true
    @State private var customError=""
    private var version:String {Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "1.0.0"}
    private var deviceName:String {model.selection.isEmpty ? "iPad 显示器" : model.selection}
    private var connectionText:String {model.switchingTransport ? "正在切换" : (model.hasIPadScreen ? "已连接" : (model.busy ? "正在连接" : "未连接"))}
    var body:some View {
        HSplitView {
            VStack(spacing:0) {
                List(selection:$pane) {
                    Section {
                    HStack(spacing:10) {
                        sidebarIcon("ipad.landscape",color:.blue)
                        VStack(alignment:.leading,spacing:4) {
                            Text(deviceName).font(.system(size:13,weight:.semibold)).lineLimit(2)
                            HStack(spacing:6) {
                                Circle().fill(model.hasIPadScreen ? Color.green : Color.secondary).frame(width:7,height:7)
                                Text(connectionText).font(.system(size:12))
                            }.foregroundStyle(pane == .display ? Color.white.opacity(0.9) : Color.secondary)
                        }
                    }.padding(.vertical,5).listRowInsets(EdgeInsets(top:4,leading:6,bottom:4,trailing:6)).tag(MacPadPane.display)
                    }
                    Section {
                    HStack(spacing:10) {sidebarIcon("cable.connector",color:.teal);Text("自动连接")}.frame(height:22).listRowInsets(EdgeInsets(top:5,leading:6,bottom:5,trailing:6)).tag(MacPadPane.automation)
                    HStack(spacing:10) {sidebarIcon("list.bullet.rectangle",color:.gray);Text("连接记录")}.frame(height:22).listRowInsets(EdgeInsets(top:5,leading:6,bottom:5,trailing:6)).tag(MacPadPane.activity)
                    } header: {Color.clear.frame(height:10).accessibilityHidden(true)}
                }.listStyle(.sidebar).scrollContentBackground(.hidden).font(.system(size:13)).contentMargins(.horizontal,8,for:.scrollContent)
                HStack(spacing:10) {
                    MacPadMark().scaleEffect(0.5).frame(width:28,height:28)
                    VStack(alignment:.leading,spacing:3) {Text("MacPad").font(.system(size:12,weight:.semibold));Text("V\(version)").font(.system(size:11)).foregroundStyle(.secondary)}
                    Spacer()
                }.padding(.horizontal,16).padding(.vertical,14)
            }.background(SidebarMaterial().ignoresSafeArea())
                .frame(minWidth:210,idealWidth:220,maxWidth:240)
        VStack(alignment:.leading,spacing:0) {
                HStack {
                    Text(title).font(.system(size:17,weight:.semibold))
                    Spacer()
                    Button("刷新"){model.refresh(discover:true,hardware:true,forceDiscovery:true);model.tick()}
                    if model.hasIPadScreen {Button("断开"){model.disconnect()}.disabled(model.busy)}
                    else {Button(model.busy ? "连接中…" : "连接"){model.connect()}.buttonStyle(.borderedProminent).disabled(model.busy || model.selection.isEmpty)}
                }.controlSize(.regular).padding(.horizontal,24).padding(.top,24).padding(.bottom,12)
                switch pane ?? .display {
                case .display:displaySettings
                case .automation:automationSettings
                case .activity:activitySettings
                }
            }.frame(minWidth:520,maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        }.frame(minWidth:760,minHeight:440).background(Color(nsColor:.windowBackgroundColor))
            .sheet(isPresented:$showCustomResolution) {customResolutionSheet}
    }
    private func sidebarIcon(_ name:String,color:Color)->some View {
        Image(systemName:name).font(.system(size:13,weight:.medium)).foregroundStyle(.white)
            .frame(width:22,height:22).background(color,in:RoundedRectangle(cornerRadius:5,style:.continuous)).frame(width:28)
    }
    private var title:String {
        switch pane ?? .display {case .display:return "连接与显示";case .automation:return "自动连接";case .activity:return "连接记录"}
    }
    private var displaySettings:some View {
        Form {
            Section {
                VStack(alignment:.leading,spacing:8) {
                    HStack(spacing:7) {
                        Circle().fill(model.hasIPadScreen ? Color.green : (model.busy ? Color.orange : Color.secondary)).frame(width:8,height:8)
                        Text(model.hasIPadScreen && !model.switchingTransport ? "已连接" : model.status).foregroundStyle(.secondary)
                    }
                    Text(model.detail).font(.system(size:13)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal:false,vertical:true)
                }.padding(.vertical,2)
                LabeledContent("桌面模式") {Text(model.mirrored ? "镜像" : "等待镜像").foregroundStyle(.secondary)}
                HStack(spacing:16) {
                    Text("连接方式")
                    Spacer(minLength:16)
                    Picker("连接方式",selection:Binding(get:{model.transportChoice},set:model.chooseTransport)) {
                        Text(model.automaticChoiceTitle).tag(TransportChoice.automatic)
                        Text("USB-C 有线").tag(TransportChoice.wired).disabled(model.usbCount==0)
                        Text("无线").tag(TransportChoice.wireless)
                    }.labelsHidden().fixedSize().disabled(model.busy || model.switchingTransport || model.adjustingResolution)
                }
                if !model.transportMessage.isEmpty {Text(model.transportMessage).font(.system(size:12)).foregroundStyle(.secondary)}
                else if model.transportChoice != .automatic {Text("本次手动选择；下次拔插线或登录后恢复自动。当前：\(model.transportDescription)。").font(.system(size:12)).foregroundStyle(.secondary)}
                LabeledContent("虚拟屏幕") {Text(model.virtualID>0 ? "已就绪" : "未创建").foregroundStyle(.secondary)}
            }
            Section {
                HStack(spacing:16) {
                    Text("连接到")
                    Spacer(minLength:16)
                    Picker("连接到",selection:$model.selection) {
                        Text("请选择 iPad").tag("")
                        ForEach(model.names,id:\.self){Text($0).tag($0)}
                    }.labelsHidden().fixedSize().frame(maxWidth:.infinity,alignment:.trailing).disabled(model.hasIPadScreen || model.busy)
                }
                if model.hasIPadScreen && !model.resolutionChoices.isEmpty {
                    LabeledContent("iPad 屏幕") {Text(model.nativePanelDescription).foregroundStyle(.secondary)}
                    HStack(spacing:16) {
                        Text("显示大小")
                        Spacer(minLength:16)
                        Picker("显示大小",selection:Binding(get:{model.selectedResolution},set:{value in
                            if value=="custom" {
                                let choice=model.resolutionChoices.first{$0.id==model.selectedResolution}
                                customWidth=String(choice?.width ?? model.nativePanel?.logicalWidth ?? 1344)
                                customHeight=String(choice?.height ?? model.nativePanel?.logicalHeight ?? 938)
                                keepPanelRatio=true;customError="";showCustomResolution=true
                            } else {model.setResolution(value)}
                        })) {
                            ForEach(model.resolutionChoices){Text($0.title).tag($0.id)}
                            if model.nativePanel != nil {Divider();Text("自定义…").tag("custom")}
                        }.labelsHidden().fixedSize().frame(maxWidth:.infinity,alignment:.trailing).disabled(model.adjustingResolution || model.switchingTransport || model.busy)
                    }
                    if !model.resolutionMessage.isEmpty {Text(model.resolutionMessage).font(.system(size:12)).foregroundStyle(.secondary)}
                }
            } footer: {Text(model.resolutionFootnote)}
        }.formStyle(.grouped).font(.system(size:13))
    }
    private var customResolutionSheet:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("自定义显示大小").font(.headline)
            Text("设置桌面空间；MacPad 会使用高清渲染。\(model.nativePanelDescription)。").font(.system(size:12)).foregroundStyle(.secondary)
            HStack {
                Text("桌面宽度")
                TextField("宽度",text:$customWidth).frame(width:90).onChange(of:customWidth){_,value in
                    if keepPanelRatio,let width=Int(value),(320...4096).contains(width),let panel=model.nativePanel {customHeight=String(panel.height(forWidth:width))}
                }
                Text("高度")
                TextField("高度",text:$customHeight).frame(width:90).disabled(keepPanelRatio)
            }
            Toggle("保持 iPad 屏幕比例",isOn:$keepPanelRatio).onChange(of:keepPanelRatio){_,enabled in
                if enabled,let width=Int(customWidth),(320...4096).contains(width),let panel=model.nativePanel {customHeight=String(panel.height(forWidth:width))}
            }
            if !keepPanelRatio {Text("与 iPad 比例不同时，画面可能出现黑边。").font(.system(size:12)).foregroundStyle(.secondary)}
            if !customError.isEmpty {Text(customError).font(.system(size:12)).foregroundStyle(.red)}
            HStack {
                Spacer()
                Button("取消"){showCustomResolution=false}.keyboardShortcut(.cancelAction)
                Button("应用") {
                    if let error=model.customResolution(width:customWidth,height:customHeight){customError=error}
                    else {showCustomResolution=false}
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width:430)
    }
    private var automationSettings:some View {
        Form {
            Section {
                Toggle(isOn:$model.autoConnect) {
                    VStack(alignment:.leading,spacing:5) {
                        Text("没有实体显示器时自动连接")
                        Text("登录后或拔掉外接屏时，插线优先有线；没有数据线时尝试无线，并保持镜像桌面。")
                            .font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                }
            }
            Section {
                Toggle(isOn:$model.automaticTransport) {
                    VStack(alignment:.leading,spacing:5) {
                        Text("自动切换有线与无线")
                        Text("插线后优先使用 USB-C；拔线后尝试无线接续。切换可能短暂中断画面，当前桌面会保留。")
                            .font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                }
            } footer: {Text("无线连接需要两端开启 Wi-Fi、蓝牙和接力，登录同一 Apple 账户并保持在附近。点击“断开”会暂停连接；想切无线时直接拔线。")}
            Section {
                Toggle("登录 Mac 后启动",isOn:Binding(get:{model.loginEnabled},set:model.setLogin))
            } footer: {Text("开机密码仍由你输入。登录后，MacPad 在菜单栏运行。")}
        }.formStyle(.grouped).toggleStyle(.switch).font(.system(size:13))
    }
    private var activitySettings:some View {
        Form {
            if model.events.isEmpty {
                Section {Label("暂无连接记录",systemImage:"clock").foregroundStyle(.secondary).padding(.vertical,12)}
            } else {
                Section {
                    ForEach(model.events.reversed()) {event in
                        HStack(alignment:.top,spacing:12) {
                            Image(systemName:event.symbol).foregroundStyle(event.warning ? Color.orange : Color.accentColor).frame(width:22,height:22)
                            VStack(alignment:.leading,spacing:4) {
                                Text(event.title)
                                Text(event.detail).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                            }
                            Spacer(minLength:8)
                            Text(event.time,style:.time).font(.system(size:11)).foregroundStyle(.secondary).monospacedDigit()
                        }.padding(.vertical,5)
                    }
                } footer: {Text("只记录本次运行的连接与显示变化。")}
            }
        }.formStyle(.grouped).font(.system(size:13))
    }
}

@MainActor final class AppDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
    var model:MacPadModel!
    var window:NSWindow!
    var statusItem:NSStatusItem!
    func applicationDidFinishLaunching(_ notification:Notification) {
        model=MacPadModel()
        if CommandLine.arguments.contains("--enable-headless") {model.autoConnect=true;model.setLogin(true)}
        // During an upgrade the previous process can keep its display until the
        // new process owns another. Never terminate the previous process here.
        if CommandLine.arguments.contains("--handover") {_=model.ensureVirtual();model.refresh()}
        model.writeDiagnostics(force:true)
        let menu=NSMenu()
        menu.addItem(withTitle:"打开 MacPad",action:#selector(show),keyEquivalent:"").target=self
        menu.addItem(withTitle:"连接 iPad",action:#selector(connect),keyEquivalent:"").target=self
        menu.addItem(.separator())
        menu.addItem(withTitle:"退出 MacPad…",action:#selector(quit),keyEquivalent:"q").target=self
        statusItem=NSStatusBar.system.statusItem(withLength:40)
        if let button=statusItem.button {
            button.image=nil;button.title="";button.isBordered=false
            (button.cell as? NSButtonCell)?.highlightsBy=[]
            button.target=nil;button.action=nil;button.setAccessibilityElement(false)
            let pill=MenuBarPill(frame:button.bounds,menu:menu)
            pill.autoresizingMask=[.width,.height];button.addSubview(pill)
        }
        let event=NSAppleEventManager.shared().currentAppleEvent
        let properties=event?.paramDescriptor(forKeyword:AEKeyword(keyAEPropData))
        let login=event?.paramDescriptor(forKeyword:AEKeyword(keyAELaunchedAsLogInItem)) != nil || properties?.enumCodeValue==AEKeyword(keyAELaunchedAsLogInItem)
        model.launchContext=login ? "login-item" : (CommandLine.arguments.contains("--handover") ? "upgrade-handover" : "manual-or-restore")
        let background=login || CommandLine.arguments.contains("--background")
        model.log(background ? "后台启动：菜单栏运行" : "打开控制窗口")
        if !background {show()}
        model.tick()
    }
    @objc func show(){
        if window==nil {
        let visible=NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1194,height:834)
        let size=NSSize(width:max(760,min(860,visible.width-48)),height:max(440,min(600,visible.height-56)))
        window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.contentMinSize=NSSize(width:760,height:440)
        window.titlebarAppearsTransparent=true;window.titleVisibility = .hidden;window.toolbarStyle = .unified;window.delegate=self
        window.title="MacPad";window.contentView=NSHostingView(rootView:MacPadView(model:model));window.center();window.isReleasedWhenClosed=false
        // Prefer the visible Sidecar screen over an offscreen virtual desktop.
        if let screen=NSScreen.screens.first(where:{$0.localizedName.localizedCaseInsensitiveContains("sidecar")}) {
            let frame=screen.visibleFrame
            window.setFrameOrigin(NSPoint(x:frame.midX-window.frame.width/2,y:frame.midY-window.frame.height/2))
        }
        }
        window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);model.writeDiagnostics(force:true)
    }
    func windowWillClose(_ notification:Notification) {
        // Discard the hosting tree while keeping the display owner and menu alive.
        window?.contentView=nil;window=nil
        DispatchQueue.main.async { [weak self] in self?.model.writeDiagnostics(force:true) }
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {show();return false}
    @objc func connect(){model.connect()}
    @objc func quit(){NSApp.terminate(nil)}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {false}
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        if MPBridge.virtualDisplayID()>0 {
            let alert=NSAlert();alert.messageText="退出 MacPad？";alert.informativeText="退出会移除这个进程保留的虚拟屏幕，iPad 桌面可能随之断开。"
            alert.addButton(withTitle:"取消");alert.addButton(withTitle:"退出")
            return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
        }
        return .terminateNow
    }
}

@main enum MacPadMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--probe") {
            let devices=MPBridge.devices()
            let data:[String:Any]=["capabilities":MPBridge.capabilities(),"devices":devices,"connections":devices.map{MPBridge.connectionInfo(forName:($0["name"] as? String) ?? "")},"usbIPadCount":MPBridge.usbIPadCount(),"displays":DisplaySnapshot.read().rows,"loginStatus":SMAppService.mainApp.status.rawValue,"autoConnectWhenHeadless":UserDefaults.standard.bool(forKey:"autoConnect")]
            if let bytes=try? JSONSerialization.data(withJSONObject:data,options:[.prettyPrinted,.sortedKeys]) {print(String(decoding:bytes,as:UTF8.self))};return
        }
        if CommandLine.arguments.contains("--virtual-test") {
            let app=NSApplication.shared
            guard !DisplaySnapshot.read().others.isEmpty else {fputs("需要先连接备用显示器，未执行测试。\n",stderr);exit(2)}
            do {
                try MPBridge.createVirtual();let id=MPBridge.virtualDisplayID();RunLoop.main.run(until:Date().addingTimeInterval(3))
                print("Virtual id=\(id), online=\(CGDisplayIsOnline(id)), active=\(CGDisplayIsActive(id))")
                let valid=id != 0 && CGDisplayIsOnline(id) != 0 && CGDisplayIsActive(id) != 0
                MPBridge.releaseVirtual();withExtendedLifetime(app){}
                if !valid {exit(3)}
            } catch {fputs("\(error.localizedDescription)\n",stderr);exit(1)}
            return
        }
        let arguments=CommandLine.arguments
        if let index=arguments.firstIndex(of:"--desktop-size"),index+1<arguments.count {
            let value=arguments[index+1]
            if let choice=ResolutionPolicy.parse(value) {UserDefaults.standard.set(choice.id,forKey:"displaySize")}
        }
        let app=NSApplication.shared, delegate=AppDelegate();app.delegate=delegate;app.setActivationPolicy(.accessory);app.run();withExtendedLifetime(delegate){}
    }
}
