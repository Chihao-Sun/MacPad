#!/bin/zsh
set -euo pipefail
root="${0:A:h:h}"
cd "$root"
mkdir -p .build
xcrun swiftc Sources/ConnectionPolicy.swift Tests/ConnectionPolicyTests.swift -o .build/ConnectionPolicyTests
.build/ConnectionPolicyTests
xcrun swiftc Sources/ResolutionPolicy.swift Tests/ResolutionPolicyTests.swift -o .build/ResolutionPolicyTests
.build/ResolutionPolicyTests
/usr/bin/python3 - <<'PY'
from pathlib import Path
s=Path('Sources/MacPad.swift').read_text();a=s.index('enum MacPadArtwork');b=s.index('struct MacPadMark:View',a)
body='''
@main enum PillTests {
@MainActor static func main() {
 let app=NSApplication.shared
 let parent=NSView(frame:NSRect(x:0,y:0,width:60,height:30))
 for h:CGFloat in [22,30] {
  let pill=MenuBarPill(frame:NSRect(x:10,y:0,width:40,height:h),menu:NSMenu());parent.addSubview(pill)
  assert(pill.hitTest(NSPoint(x:27,y:h/2)) === pill)
  assert(pill.hitTest(NSPoint(x:10.1,y:0.1)) == nil)
  assert(pill.hitTest(NSPoint(x:49.9,y:h-0.1)) == nil)
  assert(pill.hitTest(NSPoint(x:9,y:h/2)) == nil)
  pill.removeFromSuperview()
 }
 assert(MacPadArtwork.menuBar.size == NSSize(width:40,height:23))
 print("PASS: native22/30pt container, capsule center/corners/margins and Retina vector size")
 withExtendedLifetime(app){}
}}
'''
Path('.build/MenuBarPillTests.swift').write_text('import AppKit\n'+s[a:b]+body)
PY
xcrun swiftc -parse-as-library .build/MenuBarPillTests.swift -o .build/MenuBarPillTests
.build/MenuBarPillTests
/usr/bin/python3 - <<'PY'
from pathlib import Path
s=Path('Sources/MacPad.swift').read_text()
a=s.index('@MainActor final class ConnectShortcut:');b=s.index('struct ShortcutRecorder:',a)
Path('.build/ShortcutTests.swift').write_text('import AppKit\nimport SwiftUI\nimport Carbon\n'+s[a:b]+Path('Tests/ShortcutTests.swift').read_text())
PY
xcrun swiftc -parse-as-library .build/ShortcutTests.swift -o .build/ShortcutTests
.build/ShortcutTests
