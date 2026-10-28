Vendored bonsoir_darwin 6.1.0 from pub.dev (upstream Skyost/Bonsoir), under its original LICENSE.
Only native code change: explicitly import Foundation in BonsoirService.swift so JSONSerialization compiles with Xcode 27. The workspace-resolution marker is removed for this standalone local dependency.
Remove this override once an SDK-compatible upstream release includes the import.
