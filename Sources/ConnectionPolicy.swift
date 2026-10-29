import Foundation

// A local deadline does not cancel Apple's asynchronous request. Retain its
// token until its own callback, including after timeout or a cable change.
struct ConnectionRequestGate {
    static let maximumAttempts=3
    private(set) var pending:UUID?
    private(set) var attempts=0
    private(set) var suspended=false
    var canStart:Bool {pending==nil && !suspended && attempts<Self.maximumAttempts}
    mutating func resume() {attempts=0;suspended=false}
    mutating func begin(_ id:UUID)->Bool {
        guard canStart else{return false}
        pending=id;attempts+=1;return true
    }
    @discardableResult mutating func complete(_ id:UUID)->Bool {
        guard pending==id else{return false}
        pending=nil
        if attempts>=Self.maximumAttempts {suspended=true}
        return true
    }
    mutating func timedOut(_ id:UUID) {
        guard pending==id else{return}
        suspended=true
    }
    mutating func confirmHealthy() {resume()}
}

enum AutomaticConnectionAction:Equatable {
    case idle, externalDisplay, settle, discover, connect
    case wait(TimeInterval)
}

enum ConnectionPolicy {
    static func shouldDiscover(otherDisplay:Bool,paused:Bool,manual:Bool)->Bool {
        manual || (!otherDisplay && !paused)
    }

    // IOKit USB enumeration is diagnostic information. At login it may lag
    // behind Sidecar's paired/recent device list, so it must not veto USB-only
    // requests to a known device.
    static func action(enabled:Bool,otherDisplay:Bool,connected:Bool,busy:Bool,
                       paused:Bool,settling:Bool,knownDevice:Bool,retryIn:TimeInterval)->AutomaticConnectionAction {
        guard enabled,!connected,!busy,!paused else{return .idle}
        if otherDisplay{return .externalDisplay}
        if settling{return .settle}
        if retryIn>0{return .wait(retryIn)}
        return knownDevice ? .connect : .discover
    }
    static func retryDelay(attempt:Int,timedOut:Bool=false,rapidRecovery:Bool=false)->TimeInterval {
        if rapidRecovery && attempt<=5 {
            let quick:[TimeInterval]=[0.4,0.8,1.5,3,5]
            let delay=quick[min(max(attempt-1,0),quick.count-1)]
            return timedOut ? max(2,delay) : delay
        }
        let delays:[TimeInterval]=[5,10,20,40,60]
        let delay=delays[min(max(attempt-1,0),delays.count-1)]
        return timedOut ? max(30,delay) : delay
    }
    static func discoveryDelay(attempt:Int)->TimeInterval {
        let delays:[TimeInterval]=[3,5,10,20,30,60]
        return delays[min(max(attempt-1,0),delays.count-1)]
    }
}

enum ConnectionTransport:String {
    // Automatic uses Apple's ordinary connection API. The explicit wired and
    // wireless values were read back from successful sessions on this Mac.
    case automatic, wired, wireless
    var title:String {switch self {case .automatic:return "自动";case .wired:return "有线";case .wireless:return "无线"}}
    var systemValue:Int {switch self {case .automatic:return 0;case .wireless:return 1;case .wired:return 2}}
}

enum TransportChoice:String,CaseIterable {
    case automatic,wired,wireless
}

enum TransportPolicy {
    static func initial(usbPresent:Bool)->ConnectionTransport {usbPresent ? .wired : .automatic}
    static func migration(enabled:Bool,connected:Bool,busy:Bool,paused:Bool,
                          usbPresent:Bool,configuredTransport:Int?,settled:Bool,
                          retryIn:TimeInterval,choice:TransportChoice = .automatic)->ConnectionTransport? {
        guard enabled,connected,!busy,!paused,settled,retryIn<=0 else{return nil}
        // Unknown system configurations do not justify disrupting a desktop.
        guard let configuredTransport,[0,1,2].contains(configuredTransport) else{return nil}
        if choice == .wireless {return configuredTransport==1 ? nil : .wireless}
        if choice == .wired {return usbPresent && configuredTransport != 2 ? .wired : nil}
        if usbPresent && configuredTransport != 2 {return .wired}
        if !usbPresent && configuredTransport == 2 {return .wireless}
        return nil
    }
    static func request(choice:TransportChoice,usbPresent:Bool,recovering:Bool)->ConnectionTransport {
        if choice == .wireless{return .wireless}
        if choice == .wired{return .wired}
        // Leave normal sessions mobile so the OS can migrate without tearing
        // them down. Only a confirmed unplug recovery pins wireless explicitly.
        return recovering && !usbPresent ? .wireless : .automatic
    }
    static func expected(choice:TransportChoice,usbPresent:Bool)->Int {
        if choice == .wireless{return 1}
        if choice == .wired{return 2}
        return usbPresent ? 2 : 1
    }
    static func graceRemaining(elapsed:TimeInterval,choice:TransportChoice)->TimeInterval {
        choice == .automatic ? max(0,3-elapsed) : 0
    }
}
