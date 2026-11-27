import Foundation

/// Single source of truth for version labels shown in the app.
/// Release metadata lives in the bundle; the fallbacks are only for unit
/// tests and previews that do not have an Info.plist.
enum AppVersion {
    static var short: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var display: String {
        "v\(short) · b\(build)"
    }
}
