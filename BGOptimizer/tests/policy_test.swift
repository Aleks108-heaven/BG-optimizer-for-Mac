// Who may be slowed: a security tool's name must start a word. A plain substring test took "eset" inside "UpdateSettings",
// "Preset" and "Reset" for the ESET security tool, so ordinary programs were never slowed and were labelled "Security tool".
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "  pass" : "  FAIL", what); if !ok { failures += 1 } }
func verdict(_ path: String) -> Verdict { Policy.classify(path: path).verdict }

// Real security tools in the ways they are named: app folders, reverse-DNS labels, program names with a suffix.
let tools = [
    "/Applications/ESET Endpoint Security.app/Contents/MacOS/esets_daemon",
    "/Library/Application Support/ESET/esets/bin/esets_daemon",
    "/Applications/Microsoft Defender.app/Contents/MacOS/wdavdaemon",
    "/Applications/Microsoft Defender.app/Contents/MacOS/Microsoft Defender Helper.app/Contents/MacOS/Microsoft Defender Helper",
    "/Library/SystemExtensions/ABC/com.microsoft.wdav.epsext.systemextension/Contents/MacOS/com.microsoft.wdav.epsext",
    "/Applications/Malwarebytes.app/Contents/MacOS/Malwarebytes",
    "/Library/Application Support/Malwarebytes/MBAM/Engine.bundle/Contents/MacOS/RTProtectionDaemon",
    "/Applications/Falcon.app/Contents/Resources/falconctl",
    "/Library/CS/falcond",
    "/Applications/CrowdStrike Falcon.app/Contents/MacOS/Falcon",
    "/Library/Sentinel/sentinel-agent.bundle/Contents/MacOS/sentineld",
    "/Library/Little Snitch/Little Snitch Agent.app/Contents/MacOS/Little Snitch Agent",
    "/Applications/Norton 360.app/Contents/MacOS/NortonSecurity",
    "/Library/Sophos Anti-Virus/SophosScanD.app/Contents/MacOS/SophosScanD",
    "/Applications/Avast.app/Contents/MacOS/Avast",
    "/Library/Jamf/Jamf.app/Contents/MacOS/JamfDaemon",
    "/usr/local/McAfee/AntiMalware/VShieldScanner",
    "/Applications/Bitdefender/AntiVirusforMac.app/Contents/MacOS/Bitdefender",
]
for t in tools { check(Policy.isSecurityTool(t), "still a security tool: \(t.split(separator: "/").suffix(2).joined(separator: "/"))") }
check(Policy.isSecurityTool("com.eset.fake") && Policy.isSecurityTool("com.crowdstrike.falcon.Agent") && Policy.isSecurityTool("ESET"), "labels and bare names still match (start, after a dot)")
check(["com.microsoft.wdav.tray", "at.obdev.little snitch daemon", "com.malwarebytes.mbam.rtprotection.daemon"].allSatisfy { Policy.isSecurityTool($0) }, "dotted labels still match")

// Programs that only contain a security tool's name inside another word, taken from the processes of a real Mac and from common names.
let ordinary = [
    "/System/Library/ExtensionKit/Extensions/SoftwareUpdateSettingsExtensionIntents.appex/Contents/MacOS/SoftwareUpdateSettingsExtensionIntents",
    "/System/Library/ExtensionKit/Extensions/StorageSettingsIntentsExtension.appex/Contents/MacOS/StorageSettingsIntentsExtension",
    "/System/Library/PrivateFrameworks/CascadeSets.framework/Versions/A/XPCServices/SetStoreUpdateService.xpc/Contents/MacOS/SetStoreUpdateService",
    "/Users/me/dev/reset-db/node_modules/.bin/node",
    "/Applications/Lightroom.app/Contents/Presets/preset-helper",
    "/Applications/Photo Tool.app/Contents/MacOS/OffsetRenderer",
    "/Users/me/tools/ClockSettingsHelper",
    "/Users/me/Library/Application Support/Preset/worker",
]
for o in ordinary { check(!Policy.isSecurityTool(o), "not a security tool: \(o.split(separator: "/").last ?? "")") }

// The same decision through classify: an ordinary user program is allowed (ok), not taken for a security tool.
check(verdict("/Users/me/dev/reset-db/node_modules/.bin/node") == .ok, "classify: a program in a folder called reset-db can be slowed")
check(verdict("/Applications/Photo Tool.app/Contents/MacOS/OffsetRenderer") == .ok, "classify: a program called OffsetRenderer can be slowed")
check(Policy.classify(path: "/Applications/ESET Endpoint Security.app/Contents/MacOS/esets_daemon").verdict == .never, "classify: ESET is never slowed")
check(Policy.classify(path: "/Applications/Microsoft Defender.app/Contents/MacOS/wdavdaemon").reason == "Security tool", "classify: Defender's reason says 'Security tool'")

// Words after a digit or a letter do not count as a start; punctuation and spaces do.
check(!Policy.isSecurityTool("2eset") && !Policy.isSecurityTool("xavast") && Policy.isSecurityTool("-eset") && Policy.isSecurityTool("my eset"), "boundary: a letter or digit before the name blocks it; '-' or a space allows it")
check(Policy.isSecurityTool("preset eset") && !Policy.isSecurityTool("preset resetsettings"), "boundary: a later real match is still found after a false one")
check(!Policy.isSecurityTool("") && !Policy.isSecurityTool("e"), "boundary: empty and tiny text")

print(failures == 0 ? "POLICY: ALL PASSED" : "POLICY: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
