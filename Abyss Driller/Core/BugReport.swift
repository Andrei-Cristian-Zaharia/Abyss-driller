import SwiftUI
#if os(iOS) && canImport(MessageUI)
import MessageUI
import UIKit
#endif

/// "Report a bug": an email to support, pre-filled with the details that save
/// a round trip (app version, device, iOS). The player sees and sends it from
/// their own account; the game itself sends nothing.
///
/// First choice is Apple's in-app mail sheet. Without a Mail account it falls
/// back to a `mailto:` link (the player's default mail app, e.g. Gmail), and
/// as a last resort copies the address.
enum BugReport {
    static let address = "asar.innovations@gmail.com"
    /// The "[Abyss Drill]" tag lets the support inbox filter these.
    static let subject = "[Abyss Drill] Bug report"

    static func body(bestDepth: Int) -> String {
        // The questions are for the player, in their language; the details
        // under the line stay English for the support inbox.
        let what = String(localized: "What happened?", bundle: .app, comment: "Bug report email question")
        let expected = String(localized: "What did you expect to happen?", bundle: .app, comment: "Bug report email question")
        let whereAt = String(localized: "Where were you? (biome, boss, screen)", bundle: .app, comment: "Bug report email question")
        let keep = String(localized: "Please keep the details below, they help fix the bug.", bundle: .app, comment: "Bug report email")
        return """
        \(what)


        \(expected)


        \(whereAt)



        ---
        \(keep)
        App: \(appVersion)
        Device: \(deviceModel)
        System: \(systemVersion)
        Best depth: \(bestDepth) m
        """
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// Hardware identifier such as "iPhone16,2".
    static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static var systemVersion: String {
        #if os(iOS)
        return "iOS \(UIDevice.current.systemVersion)"
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    static var canUseMailSheet: Bool {
        #if os(iOS) && canImport(MessageUI)
        return MFMailComposeViewController.canSendMail()
        #else
        return false
        #endif
    }

    /// Opens the player's default mail app, pre-filled. Calls back with
    /// false if there is no mail app at all.
    static func openMailLink(bestDepth: Int, completion: @escaping (Bool) -> Void) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [URLQueryItem(name: "subject", value: subject),
                                 URLQueryItem(name: "body", value: body(bestDepth: bestDepth))]
        guard let url = components.url else { return completion(false) }
        #if os(iOS)
        UIApplication.shared.open(url, options: [:]) { completion($0) }
        #else
        completion(false)
        #endif
    }

    static func copyAddress() {
        #if os(iOS)
        UIPasteboard.general.string = address
        #endif
    }
}

#if os(iOS) && canImport(MessageUI)
/// Apple's mail sheet, pre-filled; dismisses itself when the player sends or cancels.
struct MailSheet: UIViewControllerRepresentable {
    let bestDepth: Int
    /// Called with true if the player tapped Send.
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mail = MFMailComposeViewController()
        mail.mailComposeDelegate = context.coordinator
        mail.setToRecipients([BugReport.address])
        mail.setSubject(BugReport.subject)
        mail.setMessageBody(BugReport.body(bestDepth: bestDepth), isHTML: false)
        return mail
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true)
            onFinish(result == .sent)
        }
    }
}
#endif
