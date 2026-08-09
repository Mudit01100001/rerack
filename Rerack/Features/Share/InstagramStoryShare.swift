import UIKit

/// PRD §9.5 "Instagram Stories hand-off."
///
/// Instagram's documented sticker/background handoff: put the image on the
/// general pasteboard under Instagram's own keys, then open
/// `instagram-stories://share`. Instagram reads the pasteboard and opens the
/// story composer with the card already placed — no upload, no account link,
/// no network call from us. Nothing is posted: the user still composes and
/// taps share inside Instagram.
enum InstagramStoryShare {
    private static let shareURL = URL(string: "instagram-stories://share")!

    /// Whether Instagram is installed *and* the scheme is declared in
    /// `LSApplicationQueriesSchemes`. Both are required — without the plist
    /// entry `canOpenURL` returns false even when Instagram is present.
    static var isAvailable: Bool {
        UIApplication.shared.canOpenURL(shareURL)
    }

    /// - Parameter backgroundImage: rendered card, 1080×1920 for a story.
    /// - Returns: whether Instagram was actually opened.
    @discardableResult
    @MainActor
    static func share(backgroundImage: UIImage, appID: String = AppIdentity.bundleID) -> Bool {
        guard isAvailable, let data = backgroundImage.pngData() else { return false }

        let items: [String: Any] = [
            "com.instagram.sharedSticker.backgroundImage": data,
            // Matches the card's own gradient so any letterboxing on a
            // different aspect ratio blends instead of banding.
            "com.instagram.sharedSticker.backgroundTopColor": "#12141F",
            "com.instagram.sharedSticker.backgroundBottomColor": "#4D2E5C",
        ]

        // Five minutes is Instagram's documented window; the pasteboard entry
        // expires on its own so a rendered card can't linger in the
        // system-wide clipboard after the hand-off.
        UIPasteboard.general.setItems(
            [items],
            options: [.expirationDate: Date().addingTimeInterval(60 * 5)]
        )

        var components = URLComponents(url: shareURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "source_application", value: appID)]
        guard let url = components?.url else { return false }

        UIApplication.shared.open(url)
        return true
    }
}
