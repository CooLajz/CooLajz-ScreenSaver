import AppKit
import CryptoKit

enum AtlasInstallation {
    static var isInstalled: Bool {
        let parent = Bundle.main.bundleURL.resolvingSymlinksInPath().deletingLastPathComponent()
        return ["/Applications",FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path].contains(parent.path)
    }
    static func register() {
        guard isInstalled, #available(macOS 14, *), let plugin = Bundle.main.builtInPlugInsURL?.appendingPathComponent("AtlasExtension.appex"),
              let executable = Bundle(url: plugin)?.executableURL else { return }
        DispatchQueue.global(qos: .utility).async {
            do {
                let data = try Data(contentsOf: executable)
                let attributes = try FileManager.default.attributesOfItem(atPath: executable.path)
                let identity = plugin.path+"|\(attributes[.systemFileNumber]!)|"+SHA256.hash(data: data).map { String(format: "%02x",$0) }.joined()
                let previous = AtlasSettings.defaults.string(forKey: "installedExtension.v1")
                try run("/usr/bin/pluginkit",["-a",plugin.path])
                if previous != identity {
                    let session = CGSessionCopyCurrentDictionary() as? [String:Any]
                    if session?["CGSSessionScreenIsLocked"] as? Bool != true && session?[kCGSessionOnConsoleKey as String] as? Bool == true {
                        // Refresh only this user's wallpaper host after a changed
                        // installation. No Dock, login item or saver preferences.
                        try run("/usr/bin/killall",["-u",NSUserName(),"-TERM","WallpaperAgent"],allowMissing: true)
                        AtlasSettings.defaults.set(identity,forKey: "installedExtension.v1")
                    }
                }
            } catch { NSLog("Atlas: registrace spořiče selhala: %@",error.localizedDescription) }
        }
    }
    private static func run(_ executable: String,_ arguments: [String],allowMissing: Bool = false) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 || (allowMissing && process.terminationStatus == 1) else { throw AtlasError.unavailable("Registrace systémového spořiče nebyla dokončena.") }
    }
    static func openSettings() {
        if #available(macOS 14, *) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!) }
        else if let saver = Bundle.main.url(forResource: "Atlas",withExtension: "saver") { NSWorkspace.shared.open(saver) }
    }
}
