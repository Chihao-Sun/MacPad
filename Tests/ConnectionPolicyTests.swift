import Foundation

@main enum ConnectionPolicyTests {
    static func main() {
        func decide(_ device:Bool=true,_ external:Bool=false,_ paused:Bool=false,_ busy:Bool=false,_ retry:TimeInterval=0)->AutomaticConnectionAction {
            ConnectionPolicy.action(enabled:true,otherDisplay:external,connected:false,busy:busy,paused:paused,settling:false,knownDevice:device,retryIn:retry)
        }
        // Cold login: a paired iPad may exist before IOKit reports a USB iPad.
        // The decision intentionally has no USB count prerequisite.
        assert(decide() == .connect)
        assert(decide(false) == .discover)
        assert(decide(true,true) == .externalDisplay)
        assert(decide(true,false,true) == .idle)
        assert(decide(true,false,false,true) == .idle)
        assert(decide(true,false,false,false,30) == .wait(30))
        assert(ConnectionPolicy.action(enabled:true,otherDisplay:false,connected:true,busy:false,paused:false,settling:false,knownDevice:true,retryIn:0) == .idle)
        assert(ConnectionPolicy.action(enabled:true,otherDisplay:false,connected:false,busy:false,paused:false,settling:true,knownDevice:true,retryIn:0) == .settle)
        assert(ConnectionPolicy.retryDelay(attempt:1,timedOut:true)==30)
        assert(ConnectionPolicy.retryDelay(attempt:100,timedOut:true)==60)
        assert(ConnectionPolicy.discoveryDelay(attempt:100)==60)
        // A timeout schedules another bounded attempt; it is not a user pause.
        assert(decide() == .connect)
        print("PASS: 12 cold-login, retry, manual-pause and external-display regressions")
        func migrate(usb:Bool,transport:Int?,enabled:Bool=true,busy:Bool=false,paused:Bool=false,
                     settled:Bool=true,retry:TimeInterval=0,connected:Bool=true)->ConnectionTransport? {
            TransportPolicy.migration(enabled:enabled,connected:connected,busy:busy,paused:paused,
                usbPresent:usb,configuredTransport:transport,settled:settled,retryIn:retry)
        }
        assert(TransportPolicy.initial(usbPresent:true) == .wired)
        assert(TransportPolicy.initial(usbPresent:false) == .automatic)
        assert(migrate(usb:true,transport:2) == nil)
        assert(migrate(usb:false,transport:2) == .wireless)
        assert(migrate(usb:true,transport:0) == .wired)
        assert(migrate(usb:true,transport:1) == .wired)
        assert(migrate(usb:false,transport:0) == nil)
        assert(migrate(usb:false,transport:1) == nil)
        assert(migrate(usb:true,transport:nil) == nil)
        assert(migrate(usb:true,transport:999) == nil)
        assert(migrate(usb:false,transport:2,enabled:false) == nil)
        assert(migrate(usb:false,transport:2,busy:true) == nil)
        assert(migrate(usb:false,transport:2,paused:true) == nil)
        assert(migrate(usb:false,transport:2,settled:false) == nil)
        assert(migrate(usb:false,transport:2,retry:45) == nil)
        assert(migrate(usb:false,transport:2,connected:false) == nil)
        print("PASS: 16 transport preference, unplug/replug, debounce and pause regressions")
        assert(TransportPolicy.request(choice:.automatic,usbPresent:true,recovering:false) == .automatic)
        assert(TransportPolicy.request(choice:.automatic,usbPresent:false,recovering:false) == .automatic)
        assert(TransportPolicy.request(choice:.automatic,usbPresent:false,recovering:true) == .wireless)
        assert(TransportPolicy.request(choice:.wireless,usbPresent:true,recovering:false) == .wireless)
        assert(TransportPolicy.request(choice:.wired,usbPresent:true,recovering:false) == .wired)
        assert(TransportPolicy.expected(choice:.automatic,usbPresent:true)==2)
        assert(TransportPolicy.expected(choice:.automatic,usbPresent:false)==1)
        assert(TransportPolicy.expected(choice:.wireless,usbPresent:true)==1)
        assert(TransportPolicy.expected(choice:.wired,usbPresent:false)==2)
        assert(TransportPolicy.graceRemaining(elapsed:0.5,choice:.automatic)==2.5)
        assert(TransportPolicy.graceRemaining(elapsed:4,choice:.automatic)==0)
        assert(TransportPolicy.graceRemaining(elapsed:0,choice:.wireless)==0)
        assert(TransportPolicy.migration(enabled:true,connected:true,busy:false,paused:false,usbPresent:true,configuredTransport:2,settled:true,retryIn:0,choice:.wireless) == .wireless)
        assert(TransportPolicy.migration(enabled:true,connected:true,busy:false,paused:false,usbPresent:true,configuredTransport:1,settled:true,retryIn:0,choice:.wireless) == nil)
        assert(ConnectionPolicy.retryDelay(attempt:1,rapidRecovery:true)==0.4)
        assert(ConnectionPolicy.retryDelay(attempt:3,rapidRecovery:true)==1.5)
        assert(ConnectionPolicy.retryDelay(attempt:6,rapidRecovery:true)==60)
        assert(ConnectionPolicy.retryDelay(attempt:1,timedOut:true,rapidRecovery:true)==2)
        print("PASS: 18 manual-choice, portable-auto, native-grace and bounded fast-recovery regressions")
        // Simulate a native request whose callback arrives after our deadline.
        // Thousands of reconciliation ticks must not issue another request.
        var gate=ConnectionRequestGate();let first=UUID()
        assert(gate.begin(first));gate.timedOut(first)
        for _ in 0..<1000 {assert(!gate.begin(UUID()))}
        gate.resume() // A real cable event must not forget an unfinished call.
        assert(!gate.begin(UUID()))
        assert(!gate.complete(UUID()) && gate.pending==first)
        assert(gate.complete(first));let second=UUID();assert(gate.begin(second))
        assert(!gate.complete(first) && gate.pending==second)
        assert(gate.complete(second))
        print("PASS: timeout, cable event and stale callback preserve single-flight ownership")
        // Model repeated immediate native failures across a long idle period.
        // A finite budget prevents an unbounded stack of system error alerts.
        gate=ConnectionRequestGate();var calls=0
        for _ in 0..<1000 {
            let id=UUID()
            if gate.begin(id) {calls+=1;gate.complete(id)}
        }
        assert(calls==3 && gate.suspended && gate.pending==nil)
        gate.resume();assert(gate.begin(UUID()))
        gate=ConnectionRequestGate()
        for _ in 0..<3 {let id=UUID();assert(gate.begin(id));assert(gate.complete(id))}
        gate.confirmHealthy();assert(gate.canStart && gate.attempts==0 && !gate.suspended)
        print("PASS: 1000 idle ticks make at most 3 native calls; user/device/success recovery resets budget")
    }
}
