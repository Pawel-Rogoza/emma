import SwiftUI

// MARK: - Rozmowy bez osoby w kartotece
//
// Numer kancelarii jest służbowy, więc „Rozmowy” pokazują każdą rozmowę —
// także te z importu historii WhatsApp Business, których numeru nie ma
// w kartotece. Nie udajemy osoby: wiersz ma nazwę z WhatsAppa albo numer,
// historię można przeczytać, a „Zrób leada” wpisuje numer do „Nowych”.
// Odpowiadanie zostaje w zwykłym wątku — po zamianie w leada.

struct UnassignedConversationRow: View {

    let conversation: UnassignedConversation
    let onOpen: () -> Void

    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 13) {
                // Sylwetka jak nieznany kontakt w WhatsAppie.
                Image(systemName: "person.fill")
                    .font(.system(size: 23))
                    .foregroundStyle(EmmaTheme.mutedSoft.opacity(0.8))
                    .frame(width: 54, height: 54)
                    .background(EmmaTheme.controlBackground, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(conversation.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(EmmaTheme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let sentAt = conversation.preview?.sentAt {
                            Text(timeLabel(sentAt))
                                .font(.system(size: 14))
                                .foregroundStyle(EmmaTheme.mutedSoft)
                        }
                    }
                    if let preview = conversation.preview {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            if preview.isOutgoing { ChatTicks(transport: preview.transport) }
                            Text(preview.previewText)
                                .font(.system(size: 15))
                                .foregroundStyle(EmmaTheme.mutedSoft)
                                .lineLimit(2)
                        }
                    } else if conversation.name != conversation.phone {
                        Text(conversation.phone)
                            .font(.system(size: 15))
                            .foregroundStyle(EmmaTheme.mutedSoft)
                    }
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(EmmaTheme.cardBorder)
                        .frame(height: 0.5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Otwiera historię rozmowy")
    }

    /// Dzisiejsza wiadomość — godzina, starsza — dzień.
    private func timeLabel(_ instant: Date) -> String {
        let day = AppDependencies.localDate(from: instant)
        let today = dependencies.today
        if day == today { return dependencies.dateText.clockTime(instant) }
        if day == today.adding(days: -1) { return "Wczoraj" }
        if day >= today.adding(days: -6) { return dependencies.dateText.weekdayName(for: day) }
        return String(format: "%02d.%02d.%04d", day.day, day.month, day.year)
    }
}

/// Historia rozmowy bez osoby (tylko do odczytu) i zamiana w leada.
struct UnassignedConversationSheet: View {

    let conversation: UnassignedConversation

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var phase: LoadPhase<[Message]> = .idle
    @State private var hasEarlier = false
    @State private var isCreatingLead = false

    private static let pageSize = 50

    var body: some View {
        SheetScaffold(title: conversation.name, onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tego numeru nie ma w kartotece. Zrób z rozmowy leada, żeby odpowiadać z Emmy — trafi do „Nowych” razem z całą historią.")
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.mutedSoft)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton("Zrób leada", systemImage: "person.badge.plus", isLoading: isCreatingLead) {
                    Task { await createLead() }
                }
                if let phoneURL = ContactLinks.phoneURL(conversation.phone) {
                    SecondaryButton("Zadzwoń \(conversation.phone)", systemImage: "phone") {
                        openURL(phoneURL)
                    }
                }

                history
                    .padding(.top, 6)
            }
        }
        .presentationDetents([.large])
        .task { await loadLatest() }
    }

    @ViewBuilder
    private var history: some View {
        switch phase {
        case .idle, .loading:
            LoadingState("Wczytuję historię…")
        case .failed(let failure):
            LoadFailureView(failure) {
                Task { await loadLatest() }
            }
        case .loaded(let messages):
            LazyVStack(alignment: .leading, spacing: 10) {
                if hasEarlier {
                    Button("Wczytaj starsze wiadomości") {
                        Task { await loadEarlier(before: messages.first?.sequence) }
                    }
                    .font(EmmaTypography.caption(.medium))
                    .foregroundStyle(EmmaTheme.accent)
                    .frame(maxWidth: .infinity, minHeight: EmmaSpacing.hitTarget)
                }
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                    let day = AppDependencies.localDate(from: message.sentAt)
                    let previousDay = index > 0 ? AppDependencies.localDate(from: messages[index - 1].sentAt) : nil
                    if day != previousDay {
                        ChatDaySeparator(text: dependencies.dateText.dayLabel(day))
                    }
                    MessageBubble(
                        message: message,
                        senderLabel: message.outgoingAuthorLabel,
                        showsAuthor: true
                    ) {}
                }
            }
        }
    }

    private func loadLatest() async {
        if !phase.hasLoaded { phase = .loading }
        do {
            let messages = try await dependencies.repository.latestMessages(
                threadID: conversation.threadID,
                limit: Self.pageSize
            )
            hasEarlier = messages.count >= Self.pageSize
            phase = .loaded(MessageOrdering.sorted(messages))
        } catch {
            _ = phase.recordFailure(error, fallback: "Nie udało się wczytać historii.")
        }
    }

    private func loadEarlier(before sequence: Int?) async {
        guard let sequence, let current = phase.value else { return }
        do {
            let earlier = try await dependencies.repository.messages(
                threadID: conversation.threadID,
                before: sequence,
                limit: Self.pageSize
            )
            hasEarlier = earlier.count >= Self.pageSize
            phase = .loaded(MessageOrdering.sorted(earlier + current))
        } catch {
            dependencies.showToast(ScreenLoad.message(for: error, fallback: "Nie udało się wczytać starszych wiadomości."))
        }
    }

    private func createLead() async {
        guard !isCreatingLead else { return }
        isCreatingLead = true
        defer { isCreatingLead = false }
        let created: Void? = await dependencies.perform {
            try await dependencies.repository.createLead(fromThread: conversation.threadID)
        }
        guard created != nil else { return }
        EmmaHaptics.success()
        dependencies.showToast("\(conversation.name) jest w „Nowych”")
        dismiss()
    }
}
