import Foundation

/// Single source of truth for everything that spells the app's name out loud.
///
/// PRD Appendix A.0: the working name (`Rerack`) is expected to change before
/// public launch. Renaming the app should mean editing the line below (plus
/// `APP_DISPLAY_NAME` in project.yml, which is the Info.plist-layer twin of
/// this constant — Info.plist can't read a Swift constant directly). It
/// should never mean grepping the codebase for a hardcoded string.
///
/// `bundleID` and `appGroupID` are deliberately NOT derived from
/// `displayName` — they're the one identity that's expensive to change after
/// the first TestFlight upload (see Appendix A.0), so they're named neutrally
/// and are not expected to change when the app is renamed.
enum AppIdentity {
    static let displayName = "Rerack"
    static let bundleID = "com.mudit.logbook"
    static let appGroupID = "group.com.mudit.logbook"

    /// Prefix for exported CSV filenames (PRD §14). Tracks `displayName` on
    /// purpose — unlike the bundle ID, a stale prefix in an exported file is
    /// just cosmetic, so there's no reason to freeze it.
    static var csvExportPrefix: String { displayName.lowercased() }
}
