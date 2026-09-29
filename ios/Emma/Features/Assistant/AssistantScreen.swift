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
//
// Przebudowa 29.09.2026 — ten sam język co „Dzisiaj” i „Klienci”:
//   • duży tytuł „Emma” z linijką stanu (gotowa / rozmowa trwa),
//   • kontekst jako karta z awatarem klienta w jego stałym kolorze,
//   • cztery polecenia jako kafelki 2×2, wchodzące kaskadowo,
//   • „Czekają na odpowiedź” — jedno dotknięcie i Emma szykuje odpowiedź
//     w języku klienta (do sprawdzenia, nic nie wysyła),
//   • wypowiedzi wchodzą od dołu, Emma ma przy nich swój portret, a gdy
//     przygotowuje odpowiedź — pulsują trzy kropki.


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
                        if store.voiceState.turn == .thinking {
                            EmmaThinkingBubble()
                                .padding(.top, 15)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
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
                .animation(EmmaMotion.smooth, value: store.voiceState.turn == .thinking)
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

    /// Tytuł jak na pozostałych zakładkach i jedna linijka stanu: czy Emma
    /// czeka, czy trwa rozmowa. Szczegóły stanu mówi dok na dole.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Emma")
                .font(EmmaTypography.welcome)
                .tracking(-0.9)
                .foregroundStyle(EmmaTheme.ink)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(isLive ? EmmaTheme.pillGreenText : EmmaTheme.accent)
                    .symbolEffect(.pulse, options: .repeating, isActive: isLive)
                Text(headerStatus)
                    .font(EmmaTypography.caption(.medium))
                    .foregroundStyle(EmmaTheme.mutedSoft)
                    .contentTransition(.opacity)
            }
            .animation(EmmaMotion.smooth, value: headerStatus)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isLive: Bool { store.voiceState.sessionID != nil }

    private var headerStatus: String {
        guard isLive else { return "Twoja asystentka · pisz albo mów" }
        switch store.voiceState.turn {
        case .speaking: return "Emma mówi…"
        case .thinking: return "Emma przygotowuje odpowiedź…"
        case .listening: return "Emma słucha…"
        case .waiting, .interrupted: return "Rozmowa głosowa trwa"
        }
    }

    // MARK: Wybór kontekstu (`.emma-context`)

    /// Kontekst jako karta: kto (awatar w stałym kolorze klienta albo
    /// kancelaria) i „Zmień”. Wcześniej był to wąski pasek, łatwy do przeoczenia,
    /// a od kontekstu zależy, o kim Emma mówi.
    private var contextSelector: some View {
        Button {
            dependencies.present(.emmaContextSelection(action: nil))
        } label: {
            HStack(spacing: 11) {
                if let client = store.contextClient {
                    PersonAvatar(initials: client.initials, style: .identity(client.id), diameter: 34)
                } else {
                    Image(systemName: "building.columns")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(EmmaTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(EmmaTheme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("ROZMAWIAMY O")
                        .font(EmmaTypography.caption(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(EmmaTheme.mutedSoft)
                    Text(store.contextTitle)
                        // Nazwa klienta może być cyrylicą — czcionka wg pisma.
                        .font(EmmaTypography.body(for: store.contextTitle, size: 14, weight: .semibold))
                        .foregroundStyle(EmmaTheme.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 8)
                Text("Zmień")
                    .font(EmmaTypography.caption(.semibold))
                    .foregroundStyle(EmmaTheme.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: EmmaMetrics.emmaContextMinHeight, alignment: .leading)
            .background(EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                    .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
            }
            .emmaCardShadow()
            .contentShape(Rectangle())
        }
        .buttonStyle(EmmaCardButtonStyle())
        .animation(EmmaMotion.smooth, value: store.contextTitle)
        .accessibilityLabel("Kontekst Emmy: \(store.contextTitle)")
        .accessibilityHint("Zmienia osobę albo sprawę, o której mówi Emma")
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
                .padding(.top, 26)
                .padding(.bottom, 20)

            Text(introHeading)
                .font(EmmaTypography.heading(22))
                .tracking(-0.7)
                .foregroundStyle(EmmaTheme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)

            Text(introParagraph)
                .font(EmmaTypography.emmaBody(introParagraph))
                .foregroundStyle(EmmaTheme.emmaIntroText)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)

            waitingStrip

            commandTiles
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    // MARK: Czekają na odpowiedź

    /// Osoby, które czekają na odpowiedź — dotknięcie ustawia kontekst i od
    /// razu prosi Emmę o szkic w języku klienta. Tylko w kontekście kancelarii.
    @ViewBuilder
    private var waitingStrip: some View {
        let waiting = store.clients.filter(\.needsReply)
        if store.contextClient == nil, !waiting.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("CZEKAJĄ NA ODPOWIEDŹ")
                    .font(EmmaTypography.caption(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(EmmaTheme.pillAmberText)
                    .accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(waiting.enumerated()), id: \.element.id) { index, client in
                            waitingChip(client)
                                .emmaAppear(index)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 14)
        }
    }

    private func waitingChip(_ client: Client) -> some View {
        Button {
            EmmaHaptics.tap()
            dependencies.openEmma(clientID: client.id, action: .reply, startVoice: false)
        } label: {
            HStack(spacing: 8) {
                PersonAvatar(initials: client.initials, style: .identity(client.id), diameter: 30)
                Text(client.displayName.split(separator: " ").first.map(String.init) ?? client.displayName)
                    .font(EmmaTypography.body(for: client.displayName, size: 14, weight: .semibold))
                    .foregroundStyle(EmmaTheme.ink)
                    .lineLimit(1)
                LanguageBadge(language: client.language)
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EmmaTheme.accent)
            }
            .padding(.leading, 5)
            .padding(.trailing, 12)
            .frame(minHeight: EmmaSpacing.hitTarget)
            .background(EmmaTheme.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(EmmaTheme.cardBorder, lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(EmmaCardButtonStyle())
        .accessibilityLabel("Przygotuj odpowiedź do \(client.displayName)")
    }

    // MARK: Polecenia

    /// Cztery polecenia jako kafelki 2×2 — duży cel dotyku, ikona w kolorze
    /// czynności, kaskadowe wejście. Etykiety dostępności bez zmian.
    private var commandTiles: some View {
        let inCase = store.contextClient != nil
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                commandTile(
                    index: 0,
                    systemImage: inCase ? "doc.text.magnifyingglass" : "sun.max",
                    tint: EmmaTheme.accent,
                    title: inCase ? "Podsumuj tę sprawę" : "Opowiedz mi o dzisiejszym dniu",
                    subtitle: inCase ? "Kontekst, notatki i otwarte zadania" : "Konsultacje i rzeczy do załatwienia"
                ) {
                    await store.runExample(inCase ? .prepareCase : .brief)
                }
                commandTile(
                    index: 1,
                    systemImage: "bubble.left.and.bubble.right",
                    tint: EmmaTheme.pillGreenText,
                    title: "Przygotuj odpowiedź",
                    subtitle: "W języku klienta, do sprawdzenia"
                ) {
                    await store.runExample(.reply)
                }
            }
            HStack(spacing: 10) {
                commandTile(
                    index: 2,
                    systemImage: "checklist",
                    tint: EmmaTheme.pillAmberText,
                    title: "Dodaj kolejne zadanie",
                    subtitle: "Przypisz osobę i termin"
                ) {
                    await store.runExample(.task)
                }
                commandTile(
                    index: 3,
                    systemImage: "square.and.pencil",
                    tint: EmmaTheme.caseEmmaIcon,
                    title: "Zapisz notatkę",
                    subtitle: "Trafi do karty klienta"
                ) {
                    await store.runExample(.note)
                }
            }
        }
    }

    private func commandTile(
        index: Int,
        systemImage: String,
        tint: Color,
        title: String,
        subtitle: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            EmmaHaptics.tap()
            Task { await action() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 34, height: 34)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EmmaTheme.emmaSuggestionChevron)
                }
                Text(title)
                    .font(EmmaTypography.ui(14, .semibold))
                    .foregroundStyle(EmmaTheme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.emmaSuggestionSubtitle)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .background(EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                    .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
            }
            .emmaCardShadow()
            .contentShape(Rectangle())
        }
        .buttonStyle(EmmaCardButtonStyle())
        .emmaAppear(index)
        .accessibilityLabel("\(title). \(subtitle)")
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

    // MARK: Rozmowa (`emma-thread`, `emma-proposal`)

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 15) {
            ForEach(store.turns) { turn in
                Group {
                    switch turn {
                    case .message(let message):
                        messageBubble(message)
                    case .action(let action):
                        actionCard(action)
                    }
                }
                // Nowa wypowiedź wjeżdża od dołu — widać, co właśnie doszło.
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .animation(EmmaMotion.smooth, value: store.turns.count)
        .padding(.top, 21)
    }

    private func messageBubble(_ message: AssistantStore.MessageTurn) -> some View {
        let isUser = message.role == .user
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if !isUser {
                    EmmaOrb(size: .inline)
                        .accessibilityHidden(true)
                }
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                smallSuggestion("Notatka", systemImage: "square.and.pencil", tint: EmmaTheme.caseEmmaIcon) {
                    await store.runExample(.note)
                }
                smallSuggestion("Zadanie", systemImage: "checklist", tint: EmmaTheme.pillAmberText) {
                    await store.runExample(.task)
                }
                smallSuggestion("Odpowiedź", systemImage: "bubble.left.and.bubble.right", tint: EmmaTheme.pillGreenText) {
                    await store.runExample(.reply)
                }
                smallSuggestion("Mój dzień", systemImage: "sun.max", tint: EmmaTheme.accent) {
                    await store.runExample(.brief)
                }
            }
            .padding(.vertical, 2)
        }
        .padding(.top, 9)
        .transition(.opacity)
    }

    private func smallSuggestion(
        _ title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            EmmaHaptics.tap()
            Task { await action() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(EmmaTypography.caption(.medium))
                    .foregroundStyle(EmmaTheme.emmaSmallSuggestionText)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: EmmaSpacing.hitTarget)
            .background(EmmaTheme.surface, in: Capsule())
            .overlay {
                Capsule().strokeBorder(EmmaTheme.emmaSmallSuggestionBorder, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(EmmaCardButtonStyle())
        .accessibilityLabel(title)
    }

    // MARK: Uczciwa nota o demo (`.demo-foot`)
    //
    // W Demo to mock i nie ma integracji z dostawcą. Poza Demo rozmowa głosowa
    // naprawdę idzie przez backend do Gemini Live. Nadal mówimy wprost, co jest
    // demonstracyjne: wysyłka wiadomości i odsłuch tekstu (syntezator systemu,
    // nie głos Emmy); WhatsApp pozostaje niepodłączony.

    private var demoFoot: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(EmmaTheme.emmaDemoFootText)
                .padding(.top, 1)
            Text(demoFootText)
                .font(EmmaTypography.caption())
                .foregroundStyle(EmmaTheme.emmaDemoFootText)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: EmmaRadii.button, style: .continuous)
                .strokeBorder(EmmaTheme.cardBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .accessibilityElement(children: .combine)
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

// MARK: - Emma myśli

/// Trzy kropki „Emma przygotowuje odpowiedź” w dymku Emmy. Przy „Ogranicz
/// ruch” kropki stoją, a stan mówi napis w nagłówku i w doku.
private struct EmmaThinkingBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            EmmaOrb(size: .inline)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(EmmaTheme.emmaTurnLabel)
                            .frame(width: 7, height: 7)
                            .opacity(reduceMotion ? 0.6 : 0.3 + 0.7 * max(0, sin(time * 5 - Double(index) * 0.7)))
                            .offset(y: reduceMotion ? 0 : -2 * max(0, sin(time * 5 - Double(index) * 0.7)))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(EmmaTheme.surface)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: EmmaRadii.emmaTurn,
                bottomLeadingRadius: EmmaRadii.emmaTurnTail,
                bottomTrailingRadius: EmmaRadii.emmaTurn,
                topTrailingRadius: EmmaRadii.emmaTurn,
                style: .continuous
            )
        )
        .overlay {
            UnevenRoundedRectangle(
                topLeadingRadius: EmmaRadii.emmaTurn,
                bottomLeadingRadius: EmmaRadii.emmaTurnTail,
                bottomTrailingRadius: EmmaRadii.emmaTurn,
                topTrailingRadius: EmmaRadii.emmaTurn,
                style: .continuous
            )
            .strokeBorder(EmmaTheme.emmaTurnBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Emma przygotowuje odpowiedź")
    }
}

#Preview("Asystent Emmy") {
    AssistantScreen()
        .environmentObject(AppDependencies.demo())
}
