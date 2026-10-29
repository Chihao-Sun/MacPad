// Compiled with the production ConnectShortcut type by scripts/test.sh.
@main enum ShortcutTests {
    @MainActor static func main() {
        let app=NSApplication.shared
        let name="MacPadShortcutTests-"+UUID().uuidString
        let preferences=UserDefaults(suiteName:name)!
        defer { preferences.removePersistentDomain(forName:name) }
        let modifiers=UInt32(cmdKey|optionKey|controlKey)
        // Use function keys rather than the user's active connection shortcut.
        var first:ConnectShortcut?=ConnectShortcut(defaults:preferences,initialKey:79,initialModifiers:modifiers,initialTitle:"test-F18")
        assert(first!.label == "test-F18",first!.message)
        var second:ConnectShortcut?=ConnectShortcut(defaults:preferences,initialKey:79,initialModifiers:modifiers,initialTitle:"test-F18")
        assert(second!.label.isEmpty && !second!.message.isEmpty)
        second=nil
        first!.beginRecording()
        first!.set(key:80,modifiers:modifiers,title:"test-F19")
        first!.endRecording()
        assert(first!.label == "test-F19" && first!.message.isEmpty)
        // A rejected replacement preserves both the active key and saved setting.
        first!.beginRecording();first!.set(key:37,modifiers:0,title:"L");first!.endRecording()
        assert(first!.label == "test-F19" && !first!.message.isEmpty)
        assert(preferences.dictionary(forKey:ConnectShortcut.defaultsKey)?["title"] as? String == "test-F19")
        // Cancel recording restores the previous global reservation.
        first!.beginRecording();first!.endRecording()
        second=ConnectShortcut(defaults:UserDefaults(suiteName:name+"-other")!,initialKey:80,initialModifiers:modifiers,initialTitle:"test-F19")
        assert(second!.label.isEmpty && !second!.message.isEmpty)
        second=nil
        var values:Unmanaged<CFArray>?
        assert(CopySymbolicHotKeys(&values)==noErr)
        let keys=values!.takeRetainedValue() as! [[String:Any]]
        if let system=keys.first(where:{($0["kHISymbolicHotKeyEnabled"] as? NSNumber)?.boolValue == true && (($0["kHISymbolicHotKeyModifiers"] as? NSNumber)?.uint32Value ?? 0) & modifiers != 0}) {
            first!.set(key:(system["kHISymbolicHotKeyCode"] as! NSNumber).uint32Value,modifiers:(system["kHISymbolicHotKeyModifiers"] as! NSNumber).uint32Value,title:"system")
            assert(first!.label == "test-F19" && first!.message.contains("系统"))
        }
        first=nil
        second=ConnectShortcut(defaults:UserDefaults(suiteName:name+"-other")!,initialKey:80,initialModifiers:modifiers,initialTitle:"test-F19")
        assert(second!.label == "test-F19" && second!.message.isEmpty)
        preferences.removePersistentDomain(forName:name+"-other")
        print("PASS: custom shortcut, global/system conflicts, rejected replacement persistence, cancel restore and lifecycle cleanup")
        withExtendedLifetime(app){}
    }
}
