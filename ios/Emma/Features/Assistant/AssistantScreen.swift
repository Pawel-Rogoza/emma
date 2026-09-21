import SwiftUI

// MARK: - Ekran Emmy (`emmaPage()` + `dock()`)
//
// Ekran nie jest właścicielem sesji głosowej: subskrybuje stan jednego
// koordynatora, a opuszczenie ekranu **nie** kończy rozmowy (§5.6). Nie ma tu
// drugiego transportu, drugiego subskrybenta ani drugiego silnika audio.
//
// Nota `.demo-foot` mówi prawdę o bieżącym środowisku: w Demo nie ma połączenia
// z backendem; poza Demo rozmowa idzie przez Gemini Live do prawdziwego backendu,
// a demonstracyjne pozostają tylko te czynności, które
// naprawdę są symulowane (np. wysyłka wiadomości).


@MainActor
struct AssistantScreen: View {

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.emmaLayout) private var layout
    @StateObject private var store = AssistantStoreRegistry.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        contextSelector
                        if store.turns.isEmpty {
                            intro
                        } else {
                            conversation
                        }
                        statusBlock
                        if !store.turns.isEmpty, store.pendingAction == nil {
                            smallSuggestions
                        }
                        demoFoot
                    }
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.top, EmmaSpacing.contentTop)
                    .padding(.bottom, EmmaSpacing.contentBottom)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
                // Rozmowa jest kotwiczona na dole: gdy pojawia się klawiatura,
                // karta nowej propozycji zostaje nad nią, a nie pod nią (§6).
                .defaultScrollAnchor(.bottom)
                .onChange(of: store.turns.count) { _, _ in
                    guard let last = store.turns.last else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            VoiceDock(
                state: store.voiceState,
                onStart: { Task { await store.startNewConversation() } },
                onEnd: { Task { await store.endSession() } }
            )

            composer
        }
        .background(EmmaTheme.bg)
        .task { await store.activate(dependencies) }
        .onChange(of: dependencies.pendingEmmaAction) { _, _ in
            Task { await store.consumePendingRequest() }
        }
        .onChange(of: dependencies.pendingVoiceStart) { _, _ in
            Task { await store.consumePendingRequest() }
        }
        .onChange(of: dependencies.emmaContext) { _, _ in
            Task { await store.contextChanged() }
        }
        .onChange(of: dependencies.dataVersion) { _, _ in
            Task { await store.reload() }
        }
        .onDisappear {
            // Opuszczenie ekranu nie kończy rozmowy (§5.6).
            dependencies.voice.viewDidDisappear()
        }
    }

    // MARK: Nagłówek

    private var header: some View {
        ScreenHeader(
            kicker: "TWÓJ ASYSTENT",
            title: "Emma",
        )
    }

    // MARK: Wybór kontekstu (`.emma-context`)

    private var contextSelector: some View {
        Button {
            dependencies.present(.emmaContextSelection(action: nil))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: store.contextClient == nil ? "globe" : "folder")
                    .font(.system(size: 15, weight: .regular))
                Text(store.contextTitle)
                    // Nazwa klienta może być cyrylicą — czcionka wg pisma.
                    .font(EmmaTypography.body(for: store.contextTitle, size: 11))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(EmmaTheme.contextStripText)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: EmmaMetrics.emmaContextMinHeight, alignment: .leading)
            .background(EmmaTheme.contextStripBackground)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.emmaContext, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.emmaContext, style: .continuous)
                    .strokeBorder(EmmaTheme.contextStripBorder, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Kontekst Emmy: \(store.contextTitle)")
        .padding(.top, 12)
    }

    // MARK: Stan pusty (`emma-idle`)

    private var intro: some View {
        VStack(spacing: 0) {
            EmmaOrb(
                size: .hero,
                isActive: store.voiceState.orbIsActive,
                breathing: true,
                state: store.voiceState.turn
            )
                .padding(.top, 32)
                .padding(.bottom, 23)

            Text(introHeading)
                .font(EmmaTypography.heading(22))
                .tracking(-0.7)
                .foregroundStyle(EmmaTheme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)

            Text(introParagraph)
                .font(EmmaTypography.emmaBody(introParagraph))
                .foregroundStyle(EmmaTheme.emmaIntroText)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 26)

            VStack(spacing: 0) {
                suggestionRow(
                    systemImage: "speaker.wave.2",
                    title: store.contextClient == nil ? "Opowiedz mi o dzisiejszym dniu" : "Podsumuj tę sprawę",
                    subtitle: store.contextClient == nil
                        ? "Konsultacje i rzeczy do załatwienia"
                        : "Kontekst, notatki i otwarte zadania"
                ) {
                    await store.runExample(store.contextClient == nil ? .brief : .prepareCase)
                }
                Divider().overlay(EmmaTheme.rowSeparator)
                suggestionRow(
                    systemImage: "bubble.left.and.bubble.right",
                    title: "Przygotuj odpowiedź",
                    subtitle: "W języku klienta, do sprawdzenia"
                ) {
                    await store.runExample(.reply)
                }
                Divider().overlay(EmmaTheme.rowSeparator)
                suggestionRow(
                    systemImage: "checklist",
                    title: "Dodaj kolejne zadanie",
                    subtitle: "Przypisz osobę i termin"
                ) {
                    await store.runExample(.task)
                }
            }
            .padding(.horizontal, 13)
            .background(EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.emmaSuggestions, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.emmaSuggestions, style: .continuous)
                    .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
    }

    private var introHeading: String {
        store.contextClient == nil ? "Od czego zaczynamy?" : "Jestem w kontekście tej sprawy."
    }

    private var introParagraph: String {
        if let client = store.contextClient {
            return "\(client.topic).\nMam pod ręką ustalenia, zadania i terminy."
        }
        if let awaiting = store.clients.first(where: { $0.needsReply }) {
            let firstName = awaiting.displayName.split(separator: " ").first.map(String.init) ?? awaiting.displayName
            return "\(firstName) czeka na odpowiedź.\nMogę pomóc Ci przygotować się do rozmowy."
        }
        return "Mogę omówić plan, sprawę lub kolejne zadanie."
    }

    private func suggestionRow(
        systemImage: String,
        title: String,
        subtitle: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(EmmaTheme.emmaSuggestionIcon)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.ink)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.emmaSuggestionSubtitle)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(EmmaTheme.emmaSuggestionChevron)
            }
            .padding(.vertical, 15)
            .frame(minHeight: EmmaSpacing.hitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)")
    }

    // MARK: Rozmowa (`emma-thread`, `emma-proposal`)

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 15) {
            ForEach(store.turns) { turn in
                switch turn {
                case .message(let message):
                    messageBubble(message)
                case .action(let action):
                    actionCard(action)
                }
            }
        }
        .padding(.top, 21)
    }

    private func messageBubble(_ message: AssistantStore.MessageTurn) -> some View {
        let isUser = message.role == .user
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(isUser ? "Ty" : "Emma")
                    .font(EmmaTypography.caption(.semibold))
                    .foregroundStyle(EmmaTheme.emmaTurnLabel)
                if message.isSummary {
                    StatusPill("Streszczenie", kind: .neutral)
                }
                Spacer(minLength: 0)
            }
            Text(message.text)
                .font(EmmaTypography.emmaBody(message.text))
                .foregroundStyle(EmmaTheme.ink.opacity(0.9))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)
            if !isUser {
                Button {
                    Task { await store.readTurn(id: message.id) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 14))
                        Text(message.isSummary ? "Odsłuchaj streszczenie" : "Odsłuchaj")
                            .font(EmmaTypography.caption())
                    }
                    .foregroundStyle(EmmaTheme.emmaListenText)
                    .frame(minHeight: EmmaSpacing.hitTarget, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(message.isSummary ? "Odsłuchaj streszczenie" : "Odsłuchaj wypowiedź Emmy")
                .padding(.top, 2)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isUser ? EmmaTheme.contextStripBackground : EmmaTheme.surface)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: EmmaRadii.emmaTurn,
                bottomLeadingRadius: isUser ? EmmaRadii.emmaTurn : EmmaRadii.emmaTurnTail,
                bottomTrailingRadius: isUser ? EmmaRadii.emmaTurnTail : EmmaRadii.emmaTurn,
                topTrailingRadius: EmmaRadii.emmaTurn,
                style: .continuous
            )
        )
        .overlay {
            UnevenRoundedRectangle(
                topLeadingRadius: EmmaRadii.emmaTurn,
                bottomLeadingRadius: isUser ? EmmaRadii.emmaTurn : EmmaRadii.emmaTurnTail,
                bottomTrailingRadius: isUser ? EmmaRadii.emmaTurnTail : EmmaRadii.emmaTurn,
                topTrailingRadius: EmmaRadii.emmaTurn,
                style: .continuous
            )
            .strokeBorder(isUser ? EmmaTheme.contextStripBorder : EmmaTheme.emmaTurnBorder, lineWidth: 1)
        }
        .padding(.leading, isUser ? 30 : 0)
    }

    private func actionCard(_ action: AssistantStore.ActionTurn) -> some View {
        EmmaActionCard(
            proposal: action.proposal,
            clientName: action.proposal.clientID.flatMap { store.clientName(for: $0) },
            execution: action.execution,
            isArmedForVoice: store.isArmed(action.proposal),
            onEdit: { text in
                Task { await store.edit(actionID: action.proposal.id, text: text) }
            },
            onConfirm: { text in
                Task { await store.confirm(actionID: action.proposal.id, text: text) }
            },
            onCancel: {
                Task { await store.cancel(actionID: action.proposal.id) }
            },
            dueDateText: store.dueDateLabel(for: action.proposal),
            onSpeak: { text in
                Task { await store.speakAction(actionID: action.proposal.id, text: text) }
            }
        )
    }

    // MARK: Stan sesji (`.voice-status-line`)
    //
    // Bieżący stan i błąd mówi dock na dole (jeden przycisk, jeden napis).
    // Tutaj zostają wyłącznie treści, których dock nie mieści: słyszana
    // wypowiedź i tekst, który Emma właśnie wypowiada.
    private var statusBlock: some View {
        VStack(spacing: 4) {
            if !store.voiceState.partialTranscript.isEmpty {
                Text("Słyszę: \(store.voiceState.partialTranscript)")
                    .font(EmmaTypography.emmaBody(store.voiceState.partialTranscript))
                    .foregroundStyle(EmmaTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.voiceState.turn == .speaking, !store.voiceState.agentText.isEmpty {
                Text("Emma mówi: \(store.voiceState.agentText)")
                    .font(EmmaTypography.emmaBody(store.voiceState.agentText))
                    .foregroundStyle(EmmaTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.voiceState.isPlaybackActive, store.isPlayingSummary {
                Text("Odsłuch: streszczenie.")
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.muted)
            }

            if store.voiceState.mode == .dictation {
                Text("Dyktowanie zapisuje tekst do pola. Nie wykonuje polecenia.")
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 19)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }

    // MARK: Skróty w rozmowie (`.small-suggestions`)

    private var smallSuggestions: some View {
        HStack(spacing: 7) {
            smallSuggestion("Notatka", systemImage: "square.and.pencil") { await store.runExample(.note) }
            smallSuggestion("Zadanie", systemImage: "checklist") { await store.runExample(.task) }
            smallSuggestion("Odpowiedź", systemImage: "bubble.left.and.bubble.right") { await store.runExample(.reply) }
            Spacer(minLength: 0)
        }
        .padding(.top, 9)
    }

    private func smallSuggestion(
        _ title: String,
        systemImage: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                Text(title)
                    .font(EmmaTypography.caption())
            }
            .foregroundStyle(EmmaTheme.emmaSmallSuggestionText)
            .padding(.horizontal, 10)
            .frame(minHeight: EmmaSpacing.hitTarget)
            .background(EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.emmaSmallSuggestion, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.emmaSmallSuggestion, style: .continuous)
                    .strokeBorder(EmmaTheme.emmaSmallSuggestionBorder, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: Uczciwa nota o demo (`.demo-foot`)
    //
    // W Demo to mock i nie ma integracji z dostawcą. Poza Demo rozmowa głosowa
    // naprawdę idzie przez backend do Gemini Live. Nadal mówimy wprost, co jest
    // demonstracyjne: wysyłka wiadomości i odsłuch tekstu (syntezator systemu,
    // nie głos Emmy); WhatsApp pozostaje niepodłączony.

    private var demoFoot: some View {
        Text(demoFootText)
            .font(EmmaTypography.caption())
            .foregroundStyle(EmmaTheme.emmaDemoFootText)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.top, 19)
    }

    private var demoFootText: String {
        if dependencies.configuration.usesMockServices {
            return "Emma działa na przykładowych scenariuszach. Głos jest demonstracyjny: "
                + "nie ma połączenia z backendem, więc rozmowa głosowa pozostaje scenariuszowa, "
                + "a wysyłka wiadomości jest symulowana. Odsłuch w demo jest scenariuszowy "
                + "(bez dźwięku); poza demo czyta go syntezator systemu, nie głos Emmy."
        }
        return "Rozmowa głosowa łączy się z Gemini Live przez serwer kancelarii "
            + "(klucz dostawcy nigdy nie trafia do aplikacji). Nadal demonstracyjne: "
            + "wysyłka wiadomości i zapisy akcji są symulowane, WhatsApp nie jest podłączony, "
            + "a odsłuch tekstu czyta syntezator systemu, nie głos Emmy."
    }

    // MARK: Kompozytor tekstu (`.assistant-compose`)
    //
    // Rozmowa ma jeden przycisk w docku („Rozmawiaj”/„Zakończ”); tutaj zostaje
    // wyłącznie droga tekstowa: pole polecenia i wysłanie nieaktywne dla pustego
    // pola. Przyciski „Dyktuj tekst” i wyciszenia usunięto z tego ekranu na
    // wniosek użytkownika — dyktowanie nadal działa w wątkach i formularzach.

    private var composer: some View {
        writingRow
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(EmmaTheme.bg)
    }

    /// Tryb pisania: pole polecenia i wysłanie.
    private var writingRow: some View {
        HStack(spacing: 6) {
            TextField("Napisz do Emmy…", text: $store.composer)
                .font(EmmaTypography.composerField)
                .foregroundStyle(EmmaTheme.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
                .submitLabel(.send)
                .onSubmit { Task { await store.sendComposer() } }
                .accessibilityLabel("Polecenie dla Emmy")
                .padding(.horizontal, 4)
                .frame(minHeight: EmmaSpacing.hitTarget)

            Button {
                Task { await store.sendComposer() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(EmmaTheme.primaryButtonText)
                    .frame(width: EmmaMetrics.emmaComposerButtonSize, height: EmmaMetrics.emmaComposerButtonSize)
                    .background(EmmaTheme.primaryButton)
                    .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.composerInner, style: .continuous))
            }
            .buttonStyle(.plain)
            // Puste pole nie wysyła — przycisk jest nieaktywny, a nie „cicho nic nie robi”.
            .disabled(!store.canSendComposer)
            .opacity(store.canSendComposer ? 1 : 0.4)
            .accessibilityLabel("Przekaż polecenie")
        }
        .padding(6)
        .background(EmmaTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.emmaComposer, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EmmaRadii.emmaComposer, style: .continuous)
                .strokeBorder(EmmaTheme.emmaComposerBorder, lineWidth: 1)
        }
    }
}

#Preview("Asystent Emmy") {
    AssistantScreen()
        .environmentObject(AppDependencies.demo())
}
