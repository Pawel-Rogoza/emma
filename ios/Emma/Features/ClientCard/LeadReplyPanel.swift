import SwiftUI
import UIKit

// MARK: - Odpowiedź na lead ze strony
//
// Review właściciela 04.10.2026: po wejściu w lead ma od razu czekać gotowa
// odpowiedź — „dzień dobry, dziękuję, potwierdzam konsultację, proszę
// o płatność BLIK na +48 579 910 709” — do skopiowania albo wysłania
// WhatsAppem jednym dotknięciem.
//
// Treść składa serwer (`reply_template`), tym samym kodem co panel kancelarii:
// termin, długość i cena z rezerwacji, BLIK z ustawień CRM, język klienta
// (polski albo rosyjski — nigdy ukraiński). Nic nie wysyła się samo: WhatsApp
// i „Rozmowy” otwierają się z wiadomością w polu, wysyła adwokat.

struct LeadReplyPanel: View {

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.openURL) private var openURL

    let client: Client
    let text: String
    /// Rozmowa w „Rozmowach”, gdy klient już pisał na WhatsApp.
    let threadID: ThreadID?

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Odpowiedź do klienta")
                        .font(EmmaTypography.ui(15, .semibold))
                        .foregroundStyle(EmmaTheme.ink)
                    Text("Podziękowanie, potwierdzenie konsultacji i prośba o płatność BLIK. Nic nie wysyła się samo.")
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(text)
                    .font(EmmaTypography.body(for: text, size: 14))
                    .foregroundStyle(EmmaTheme.ink)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        EmmaTheme.controlBackground,
                        in: RoundedRectangle(cornerRadius: EmmaRadii.choiceList, style: .continuous)
                    )
                    .accessibilityIdentifier("lead-reply-text")

                HStack(spacing: 8) {
                    SecondaryButton("Kopiuj", systemImage: "doc.on.doc") { copy() }
                        .accessibilityIdentifier("lead-reply-copy")
                    if let whatsApp {
                        // Wysłanie odpowiedzi to kontakt — lead przechodzi do „W kontakcie”
                        // (z „Cofnij”), tak samo jak przycisk WhatsApp wyżej.
                        ContactButton(.whatsApp, title: "WhatsApp") {
                            LeadActions.contact(client, url: whatsApp, channel: "WhatsApp", dependencies: dependencies, openURL: openURL)
                        }
                        .accessibilityIdentifier("lead-reply-whatsapp")
                    }
                }

                if let threadID {
                    SecondaryButton("Wstaw do Rozmów", systemImage: "bubble.left.and.bubble.right") {
                        dependencies.pendingThreadDraft = ThreadDraftSeed(threadID: threadID, text: text)
                        dependencies.openThread(threadID)
                    }
                    .accessibilityIdentifier("lead-reply-thread")
                }
            }
        }
    }

    /// WhatsApp z wiadomością w polu — tylko gdy znamy numer klienta.
    private var whatsApp: URL? {
        client.phone.flatMap { ContactLinks.whatsAppURL($0, text: text) }
    }

    private func copy() {
        UIPasteboard.general.string = text
        EmmaHaptics.success()
        dependencies.showToast("Skopiowano odpowiedź dla: \(client.displayName)")
    }
}
