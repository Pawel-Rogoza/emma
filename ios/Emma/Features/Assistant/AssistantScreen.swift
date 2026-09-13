import SwiftUI

// MARK: - Ekran Emmy (`emmaPage()` + `dock()`)
//
// Ekran nie jest właścicielem sesji głosowej: subskrybuje stan jednego
// koordynatora, a opuszczenie ekranu **nie** kończy rozmowy (§5.6). Nie ma tu
// drugiego transportu, drugiego subskrybenta ani drugiego silnika audio.
//
// Demo działa na deterministycznych mockach i mówi o tym wprost: nie ma kont
// dostawców, nie ma integracji z ElevenLabs ani z WhatsApp, wysyłka jest symulowana.


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
                .onChange(of: store.turns.count) { _, _ in
                    guard let last = store.turns.last else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            VoiceDock(
                state: store.voiceState,
                speaksReplies: store.speaksReplies,
                onToggleSpeech: { Task { await store.toggleSpeech() } },
                onInterrupt: { Task { await store.interrupt() } },
                onEndSession: { Task { await store.endSession() } }
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
        HStack(alignment: .top, spacing: 10) {
            ScreenHeader(
                kicker: "TWÓJ ASYSTENT",
                title: "Emma",
            )
            IconButton(
                systemName: store.speaksReplies ? "speaker.wave.2" : "speaker.slash",
                accessibilityLabel: store.speaksReplies ? "Wyłącz odpowiedzi głosowe" : "Włącz odpowiedzi głosowe",
                isSelected: store.speaksReplies,
                action: { Task { await store.toggleSpeech() } }
            )
        }
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
                        .font(EmmaTypography.ui(12))
                        .foregroundStyle(EmmaTheme.ink)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(EmmaTypography.ui(10))
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
                    .font(EmmaTypography.ui(10, .semibold))
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
                            .font(EmmaTypography.ui(11))
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

    private var statusBlock: some View {
        VStack(spacing: 4) {
            Text(store.statusText)
                .font(EmmaTypography.ui(11))
                .foregroundStyle(EmmaTheme.emmaStatusText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Stan Emmy: \(store.statusText)")

            if let error = store.voiceState.lastError {
                Text(error)
                    .font(EmmaTypography.ui(11))
                    .foregroundStyle(EmmaTheme.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Problem: \(error)")
            }

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
                    .font(EmmaTypography.ui(11))
                    .foregroundStyle(EmmaTheme.muted)
            }

            if store.voiceState.mode == .dictation {
                Text("Dyktowanie zapisuje tekst do pola. Nie wykonuje polecenia.")
                    .font(EmmaTypography.ui(11))
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
                    .font(EmmaTypography.ui(11))
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

    private var demoFoot: some View {
        Text(
            "Emma działa na przykładowych scenariuszach. Głos jest demonstracyjny: "
                + "nie ma kont dostawców, więc nie ma integracji z ElevenLabs ani z WhatsApp, "
                + "a wysyłka wiadomości jest symulowana."
        )
        .font(EmmaTypography.ui(10))
        .foregroundStyle(EmmaTheme.emmaDemoFootText)
        .multilineTextAlignment(.center)
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.top, 19)
    }

    // MARK: Kompozytor (`.assistant-compose`)

    private var composer: some View {
        HStack(spacing: 6) {
            Button {
                Task { await store.toggleListening() }
            } label: {
                // Nasłuch zatrzymuje wyraźny znak „stop”, a nie „checkmark”:
                // haczyk sugerował zatwierdzenie, choć przycisk wycisza mikrofon.
                Image(systemName: store.isMicrophoneCapturing ? "stop.fill" : "mic")
                    .font(.system(size: store.isMicrophoneCapturing ? 16 : 19, weight: .regular))
                    .foregroundStyle(store.isMicrophoneCapturing ? Color.white : EmmaTheme.emmaMicText)
                    .frame(width: EmmaMetrics.emmaComposerButtonSize, height: EmmaMetrics.emmaComposerButtonSize)
                    .background(store.isMicrophoneCapturing ? EmmaTheme.primaryButton : EmmaTheme.contextStripBackground)
                    .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.composerInner, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.isMicrophoneCapturing ? "Zatrzymaj nasłuch" : "Rozpocznij wypowiedź")
            .accessibilityValue(store.isMicrophoneCapturing ? "Nasłuch aktywny" : "Nasłuch wyłączony")

            TextField("Napisz do Emmy…", text: $store.composer)
                .font(EmmaTypography.composerField)
                .foregroundStyle(EmmaTheme.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
                .submitLabel(.send)
                .onSubmit { Task { await store.sendComposer() } }
                .accessibilityLabel("Polecenie dla Emmy")
                .padding(.horizontal, 2)

            Button {
                Task {
                    if store.isDictating {
                        await store.finishDictation()
                    } else {
                        await store.startDictation()
                    }
                }
            } label: {
                Image(systemName: "waveform")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(store.isDictating ? Color.white : EmmaTheme.emmaMicText)
                    .frame(width: EmmaMetrics.emmaComposerButtonSize, height: EmmaMetrics.emmaComposerButtonSize)
                    .background(store.isDictating ? EmmaTheme.primaryButton : EmmaTheme.contextStripBackground)
                    .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.composerInner, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.isDictating ? "Zakończ dyktowanie" : "Dyktuj polecenie do pola")

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
            .accessibilityLabel("Przekaż polecenie")
        }
        .padding(6)
        .background(EmmaTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.emmaComposer, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EmmaRadii.emmaComposer, style: .continuous)
                .strokeBorder(EmmaTheme.emmaComposerBorder, lineWidth: 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(EmmaTheme.bg)
    }
}

#Preview("Asystent Emmy") {
    AssistantScreen()
        .environmentObject(AppDependencies.demo())
}
