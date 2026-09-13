import Foundation
import SwiftUI

// MARK: - Stan prezentacji asystenta
//
// Jedno miejsce, w którym mieszka historia rozmowy z Emmą. Widok nie tworzy
// własnej sesji głosowej ani własnych tablic danych: rozmowa, dyktowanie i odsłuch
// należą do jednego `VoiceSessionCoordinator` (§5.3, §12.2), a dane kancelarii
// pochodzą z jednego `MockRepository`.
//
// Reguła zgody (§8.2): koordynator dostaje wyłącznie dowód w postaci dotknięcia
// przycisku w interfejsie (`.directUIButton`) albo — w przyszłości — finalnej
// wypowiedzi uwierzytelnionego użytkownika (`.authenticatedVoiceTurn`).
// Tekst wygenerowany przez model językowy nigdy nie jest zgodą.

@MainActor
final class AssistantStore: ObservableObject {

    // MARK: Model prezentacji

    struct MessageTurn: Identifiable, Hashable {
        let id: String
        var role: AssistantTurnRole
        var text: String
        /// Czy treść jest streszczeniem. Odsłuch musi to nazwać (§5.2).
        var isSummary: Bool
    }

    struct ActionTurn: Identifiable, Hashable {
        var proposal: ActionProposal
        var execution: ActionExecution?
        var id: String { proposal.id.rawValue }
    }

    enum Turn: Identifiable, Hashable {
        case message(MessageTurn)
        case action(ActionTurn)

        var id: String {
            switch self {
            case .message(let turn): return turn.id
            case .action(let turn): return turn.id
            }
        }
    }

    struct AwaitingInput: Hashable {
        var kind: ActionKind
        var clientID: ClientID?
    }

    // MARK: Stan publikowany

    @Published private(set) var turns: [Turn] = []
    /// Lustro stanu koordynatora. Ekran nie czyta koordynatora bezpośrednio w ciele
    /// widoku, żeby zmiany stanu były widoczne w SwiftUI.
    @Published private(set) var voiceState = VoiceUIState()
    @Published var composer = ""
    @Published var speaksReplies = true
    @Published private(set) var awaitingInput: AwaitingInput?
    @Published private(set) var clients: [Client] = []
    /// Czy trwa właśnie odsłuch streszczenia.
    @Published private(set) var isPlayingSummary = false

    // MARK: Zależności wewnętrzne

    private weak var dependencies: AppDependencies?
    private var voiceObserver: UUID?
    private var sequence = 0
    private var linkedCases: [ClientID: CaseID] = [:]
    private var caseNumbers: [CaseID: String] = [:]

    // MARK: Podłączenie

    func attach(_ dependencies: AppDependencies) {
        guard self.dependencies !== dependencies else { return }
        self.dependencies = dependencies
        if let voiceObserver {
            dependencies.voice.removeObserver(voiceObserver)
        }
        voiceObserver = dependencies.voice.addObserver { [weak self] state in
            self?.apply(voiceState: state)
        }
    }

    /// Wejście na ekran: dane prezentacji plus odłożony skrót z innego ekranu.
    func activate(_ dependencies: AppDependencies) async {
        attach(dependencies)
        await reload()
        await consumePendingRequest()
    }

    func reload() async {
        guard let dependencies else { return }
        clients = (try? await dependencies.repository.clients(matching: "", stage: nil)) ?? []
        let cases = (try? await dependencies.repository.cases(status: nil)) ?? []
        linkedCases = Dictionary(
            uniqueKeysWithValues: cases.filter { $0.status.isActive }.map { ($0.clientID, $0.id) }
        )
        caseNumbers = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, $0.number) })
        projectExpiredProposals()
    }

    /// Zmiana kontekstu Emmy na innym ekranie (arkusz wyboru kontekstu).
    func contextChanged() async {
        awaitingInput = nil
        await consumePendingRequest()
    }

    // MARK: Odłożone żądania z innych ekranów

    /// Odpowiada `openEmma(pid, action, start)` z referencji: zużywa `pendingEmmaAction`
    /// i `pendingVoiceStart`, a następnie czyści je w zależnościach.
    func consumePendingRequest() async {
        guard let dependencies else { return }
        let action = dependencies.pendingEmmaAction
        let shouldStartVoice = dependencies.pendingVoiceStart
        dependencies.pendingEmmaAction = nil
        dependencies.pendingVoiceStart = false

        if let action {
            await runExample(action)
        }
        if shouldStartVoice {
            await startConversation()
        }
    }

    // MARK: Skróty (`assistantExample`)

    func runExample(_ action: EmmaQuickAction) async {
        guard let dependencies else { return }
        await stopVoiceModes()

        // Najpierw brief: nie wymaga klienta, więc działa także bez kontekstu.
        if action == .brief {
            appendUserTurn("Podsumuj dzisiejszy dzień.")
            await answer(await briefing(), isSummary: true)
            return
        }
        if pendingAction != nil {
            await answer("Najpierw zatwierdź albo anuluj przygotowane działanie.")
            return
        }
        guard let clientID = dependencies.emmaContext else {
            // Skrót wymaga klienta: pytamy o kontekst i wracamy z nim (jak `chooseContext`).
            dependencies.present(.emmaContextSelection(action: action))
            return
        }
        guard let client = client(id: clientID) else { return }

        switch action {
        case .prepareCase:
            appendUserTurn("Przygotuj mnie do rozmowy: \(client.displayName).")
            await answer(await caseSummary(clientID), isSummary: true)
        case .reply:
            appendUserTurn("Przygotuj odpowiedź do \(client.displayName).")
            await prepareReply(clientID)
        case .note, .task:
            let kind: ActionKind = action == .note ? .note : .task
            appendUserTurn(action == .note ? "Chcę zapisać notatkę." : "Chcę dodać zadanie.")
            awaitingInput = AwaitingInput(kind: kind, clientID: clientID)
            await answer(
                action == .note
                    ? "Co zapisać w notatce dla \(client.displayName)? Podyktuj lub wpisz treść."
                    : "Jakie zadanie dodać dla \(client.displayName)? Wpisz lub podyktuj treść. Przygotuję je na dziś dla Ciebie; osobę i termin możesz zmienić po zapisaniu."
            )
        case .brief:
            break
        }
    }

    // MARK: Komenda tekstowa (`handleCommand`)

    func sendComposer() async {
        let text = composer
        composer = ""
        await handleCommand(text)
    }

    func handleCommand(_ raw: String) async {
        guard let dependencies else { return }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await stopVoiceModes()
        appendUserTurn(text)
        let lowered = text.lowercased()

        // 1. Anulowanie.
        if isBare(lowered, ["anuluj", "rezygnuję"]) {
            if let pending = pendingAction {
                await cancel(actionID: pending.proposal.id)
            } else {
                awaitingInput = nil
                await answer("Anulowano. Możemy przejść do kolejnego polecenia.")
            }
            return
        }

        // 2. Potwierdzenie. Zgoda pochodzi z interfejsu, więc dowodem jest
        //    `.directUIButton` — nadal dla prezentacji, którą użytkownik widzi.
        if isBare(lowered, ["zatwierdź", "wyślij", "zapisz", "tak"]) {
            if let pending = pendingAction {
                await confirmFromTypedCommand(pending)
            } else {
                await answer("Nie ma przygotowanego działania do zatwierdzenia.")
            }
            return
        }

        // Zwykłe polecenie w aktywnej sesji trafia też do transportu jako tura tekstowa.
        await forwardTypedTurn(text)

        // 3. Jedno przygotowane działanie blokuje kolejne polecenia.
        if pendingAction != nil {
            await answer("Działanie czeka na zatwierdzenie. Możesz je poprawić, odsłuchać albo anulować.")
            return
        }

        // 4. Treść do przygotowanego szkicu (notatka albo zadanie).
        if let awaiting = awaitingInput {
            awaitingInput = nil
            await newAction(kind: awaiting.kind, clientID: awaiting.clientID, text: text)
            if speaksReplies {
                await speak("Przygotowałam treść do zatwierdzenia.", language: .pl, isSummary: false, sourceID: nextSourceID("emma-note"))
            }
            return
        }

        // 5. Plan dnia.
        let wantsBriefing = ["plan", "dzisiejsz", "dzień", "dniu", "kalendarz"].contains { lowered.contains($0) }
        let excludesBriefing = ["notatk", "wiadomo", "odpow", "zadani"].contains { lowered.contains($0) }
        if wantsBriefing && !excludesBriefing {
            await answer(await briefing(), isSummary: true)
            return
        }

        // 6. Rozpoznanie klienta — regułą domenową, nie własnym wyrażeniem regularnym.
        let resolution = resolveClient(in: text, lowered: lowered)
        switch resolution {
        case .multiple:
            await answer("Wybierz jednego klienta w polu kontekstu. Polecenie dotyczy kilku osób.")
            return
        case .unknown:
            await answer("Nie rozpoznałam wskazanego klienta. Wybierz go w polu kontekstu.")
            return
        case .resolved, .context:
            break
        }
        let clientID: ClientID? = {
            if case .resolved(let id) = resolution { return id }
            return dependencies.emmaContext
        }()

        // 7. Rodzaj polecenia. `case` z referencji to podsumowanie sprawy, a nie
        //    rodzaj akcji, więc obsługujemy je osobno (`ActionKind` go nie zna).
        let detected: DetectedCommand? = {
            if lowered.contains("notatk") { return .action(.note) }
            if lowered.contains("zadani") || lowered.contains("przypomnij") { return .action(.task) }
            if lowered.contains("odpow") || lowered.contains("wiadomo") { return .action(.reply) }
            if lowered.contains("podsum") || lowered.contains("przygotuj") || lowered.contains("spraw") { return .caseSummary }
            return nil
        }()
        guard let detected else {
            await answer("W prototypie mogę omówić dzień lub sprawę, przygotować wiadomość, notatkę i zadanie. Wybierz skrót albo podaj klienta i polecenie.")
            return
        }

        // Podsumowanie sprawy zawsze wymaga klienta; akcja może być firmowa tylko
        // wtedy, gdy nie dotyczy adresata (zadanie „do listy”).
        if case .caseSummary = detected {
            guard let clientID else {
                await answer("Wybierz klienta w polu kontekstu, żeby powiązać z nim polecenie.")
                return
            }
            dependencies.emmaContext = clientID
            await answer(await caseSummary(clientID), isSummary: true)
            return
        }

        guard case .action(let kind) = detected else { return }
        if clientID == nil && kind != .task {
            await answer("Wybierz klienta w polu kontekstu, żeby powiązać z nim polecenie.")
            return
        }
        dependencies.emmaContext = clientID

        // 8. Treść po dwukropku od razu tworzy propozycję.
        if let colon = text.firstIndex(of: ":"), colon < text.endIndex {
            let tail = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                let dueDate = kind == .task && lowered.contains("jutro")
                    ? dependencies.today.adding(days: 1)
                    : dependencies.today
                await newAction(kind: kind, clientID: clientID, text: tail, dueDate: dueDate)
                if speaksReplies {
                    await speak("Treść jest gotowa. Sprawdź ją i zatwierdź.", language: .pl, isSummary: false, sourceID: nextSourceID("emma-draft"))
                }
                return
            }
        }

        if kind == .reply, let clientID {
            await prepareReply(clientID)
            return
        }

        awaitingInput = AwaitingInput(kind: kind, clientID: clientID)
        await answer(
            kind == .note
                ? "Podyktuj treść notatki."
                : "Podyktuj treść zadania. Domyślnie przypiszę je Tobie na dziś."
        )
    }

    /// Rodzaj polecenia rozpoznany z treści (odpowiada `kind` z referencji, gdzie
    /// `'case'` oznaczało podsumowanie sprawy).
    private enum DetectedCommand {
        case action(ActionKind)
        case caseSummary
    }

    private enum ClientResolution {
        case resolved(ClientID)
        case multiple
        case unknown
        case context
    }

    /// `resolvePerson` z referencji, ale na regule domenowej `PersonResolver` (§4.3).
    /// Gdy nikt nie został rozpoznany, a polecenie nie wskazuje wprost odbiorcy,
    /// używamy kontekstu Emmy — dokładnie jak w prototypie.
    private func resolveClient(in text: String, lowered: String) -> ClientResolution {
        switch PersonResolver.resolve(text, among: clients) {
        case .resolved(let clientID):
            return .resolved(clientID)
        case .multiple:
            return .multiple
        case .unknown, .none:
            let addressed = ["do ", "dla ", "klienta "].contains { lowered.contains($0) }
            return addressed ? .unknown : .context
        }
    }

    private func isBare(_ lowered: String, _ forms: [String]) -> Bool {
        let stripped = lowered.trimmingCharacters(in: CharacterSet(charactersIn: " .!"))
        return forms.contains(stripped)
    }

    private func forwardTypedTurn(_ text: String) async {
        guard let dependencies else { return }
        let state = dependencies.voice.state
        // Tylko aktywna sesja: bez niej koordynator nie ma dokąd wysłać tury.
        guard state.sessionID != nil, state.connection == .connected else { return }
        await dependencies.voice.sendTextTurn(
            text: text,
            language: dependencies.currentUser.interfaceLanguage,
            inputID: nextID("input")
        )
    }

    // MARK: Akcje

    @discardableResult
    func newAction(
        kind: ActionKind,
        clientID: ClientID?,
        text: String,
        dueDate: LocalDate? = nil
    ) async -> ActionTurn? {
        guard let dependencies else { return nil }
        guard pendingAction == nil else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let proposal = await dependencies.voice.prepareAction(
            kind: kind,
            clientID: clientID,
            caseID: clientID.flatMap { linkedCases[$0] },
            threadID: kind == .reply ? clientID.map { DemoFixtures.threadID(for: $0) } : nil,
            text: trimmed,
            actor: dependencies.currentUser,
            presentationID: nextPresentationID(kind: kind),
            taskDueDate: kind == .task ? (dueDate ?? dependencies.today) : nil
        )
        guard let proposal else { return nil }

        awaitingInput = nil
        let turn = ActionTurn(proposal: proposal, execution: nil)
        turns.append(.action(turn))
        projectExpiredProposals()
        return turn
    }

    func prepareReply(_ clientID: ClientID) async {
        guard let client = client(id: clientID) else { return }
        guard let turn = await newAction(kind: .reply, clientID: clientID, text: await draftText(clientID)) else { return }
        if speaksReplies {
            await speak(
                "Przygotowałam wiadomość do \(client.displayName). Sprawdź treść lub odsłuchaj ją przed zatwierdzeniem.",
                language: .pl,
                isSummary: false,
                sourceID: nextSourceID("emma-action")
            )
        }
        _ = turn
    }

    /// Rewizja treści unieważnia wcześniejszą zgodę (§1.10) — koordynator robi to sam.
    func edit(actionID: ActionID, text: String) async {
        guard let dependencies else { return }
        guard let index = actionIndex(actionID) else { return }
        guard case .action(var action) = turns[index] else { return }
        guard action.proposal.state == .proposed else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != action.proposal.text else { return }
        guard let revised = await dependencies.voice.reviseAction(actionID: actionID, newText: trimmed) else { return }
        action.proposal = revised
        turns[index] = .action(action)
    }

    func cancel(actionID: ActionID) async {
        guard let dependencies else { return }
        guard let index = actionIndex(actionID), case .action(var action) = turns[index] else { return }
        guard action.proposal.state == .proposed else { return }
        if let cancelled = await dependencies.voice.cancelAction(actionID: actionID) {
            action.proposal = cancelled
        } else {
            action.proposal.state = .rejected
        }
        turns[index] = .action(action)
        await answer("Anulowałam działanie.")
    }

    /// Potwierdzenie z karty na ekranie — jedyna droga wykonania, gdy prezentacja
    /// nie jest uzbrojona dla głosu.
    ///
    /// `text` to treść **widoczna** w karcie w chwili dotknięcia. Jeśli różni się od
    /// ostatniej wersji znanej koordynatorowi (np. użytkownik pisał i od razu
    /// zatwierdził, przed odroczoną korektą), najpierw wysyłamy rewizję i zatwierdzamy
    /// dokładnie ją. Dzięki temu wykonana treść zawsze równa się widocznej (F03).
    func confirm(actionID: ActionID, text: String) async {
        guard let index = actionIndex(actionID), case .action(var action) = turns[index] else { return }
        guard action.proposal.state == .proposed else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed != action.proposal.text {
            guard let revised = await dependencies?.voice.reviseAction(actionID: actionID, newText: trimmed) else {
                await answer("Nie udało się zapisać poprawki treści. Spróbuj ponownie.")
                return
            }
            action.proposal = revised
            turns[index] = .action(action)
        }
        await performConfirmation(action.proposal, origin: .directUIButton)
    }

    private func confirmFromTypedCommand(_ pending: ActionTurn) async {
        guard let dependencies else { return }
        guard pending.proposal.state == .proposed else {
            await answer("Ta propozycja nie jest już aktualna.")
            return
        }
        guard !pending.proposal.isExpired(at: dependencies.clock.now()) else {
            projectExpiredProposals()
            await answer("Okno potwierdzenia minęło. Przygotuj działanie ponownie.")
            return
        }
        // Treść wpisana w polu jest świadomym działaniem w interfejsie, ale musi
        // dotyczyć tej samej prezentacji, którą pokazuje ekran. Jeśli koordynator
        // zna nowszą prezentację **tej samej** akcji, nie zatwierdzamy starej.
        if let active = dependencies.voice.state.activeProposal,
           active.id == pending.proposal.id,
           active.presentationID != pending.proposal.presentationID {
            await answer("Propozycja zmieniła się od czasu jej pokazania. Sprawdź treść i zatwierdź przyciskiem w karcie.")
            return
        }
        await performConfirmation(pending.proposal, origin: .directUIButton)
    }

    /// Jedno miejsce, w którym powstaje zgoda. `.languageModelArgument` nie jest
    /// dowodem zgody i nie występuje w tym kodzie.
    private func performConfirmation(
        _ proposal: ActionProposal,
        origin: ActionEngine.Confirmation.Origin
    ) async {
        guard let dependencies else { return }
        guard origin == .directUIButton || origin == .authenticatedVoiceTurn else { return }
        guard let execution = await dependencies.voice.confirmAction(
            actionID: proposal.id,
            presentationID: proposal.presentationID,
            origin: origin,
            actor: dependencies.currentUser
        ) else {
            if let error = dependencies.voice.state.lastError {
                await answer("Nie udało się potwierdzić działania: \(error)")
            }
            return
        }
        updateExecution(execution)
        // Dane kancelarii mogły się zmienić — pozostałe ekrany wczytają je ponownie.
        dependencies.dataChanged()
        await report(execution: execution, kind: proposal.kind)
    }

    private func report(execution: ActionExecution, kind: ActionKind) async {
        guard let dependencies else { return }
        switch execution.state {
        case .accepted:
            await answer(successMessage(kind))
        case .queued, .claimed, .dispatching:
            await answer(queuedMessage(kind, state: execution.state))
        case .unknown:
            // Niepewny wynik: pytamy o status **raz** i nie ma automatycznego ponowienia (§8.3).
            await dependencies.voice.refreshExecutionState(actionID: execution.actionID)
            await answer("Nie znam jeszcze wyniku tego działania. Sprawdziłam status wysyłki; automatycznego ponowienia nie ma.")
        case .failed:
            await answer("Wykonanie nie powiodło się. Treść zostaje na ekranie — możesz przygotować działanie ponownie.")
        }
    }

    private func successMessage(_ kind: ActionKind) -> String {
        switch kind {
        case .reply: return "Wiadomość dodana do rozmowy. Wysyłka jest symulowana."
        case .note: return "Notatka jest już w karcie klienta."
        case .task: return "Zadanie jest już na wspólnej liście."
        }
    }

    /// Stan z referencji, ale z jawnym rozróżnieniem: zatwierdzone ≠ wykonane.
    private func queuedMessage(_ kind: ActionKind, state: ExecutionState) -> String {
        let status = "(stan: \(state.displayName))"
        switch kind {
        case .reply:
            return "Wiadomość zatwierdzona i przekazana do wysyłki \(status). Wysyłka jest symulowana — dostarczenia jeszcze nie potwierdzam."
        case .note:
            return "Notatka zatwierdzona i przekazana do zapisu \(status). Zapis jest symulowany — potwierdzenia jeszcze nie mam."
        case .task:
            return "Zadanie zatwierdzone i przekazane do zapisu \(status). Zapis jest symulowany — potwierdzenia jeszcze nie mam."
        }
    }

    // MARK: Głos: sesja, dyktowanie, odsłuch

    /// Jedna sesja na proces. Wznowienie nie tworzy drugiego połączenia (§5.3).
    func startConversation() async {
        guard let dependencies else { return }
        let state = dependencies.voice.state
        if state.sessionID != nil, state.connection == .connected || state.connection == .connecting {
            await dependencies.voice.updateContext(currentContext())
            return
        }
        // Scenariusz mocka wynika z zestawu danych demo (`--fixture`), a nie z zaszytej
        // nazwy: inaczej schematy „voice-reconnect” czy „voice-barge-in” nie miałyby
        // żadnego wpływu na działanie aplikacji. Wybór należy do fabryki usług.
        await dependencies.voice.startConversation(
            context: currentContext(),
            user: dependencies.currentUser,
            installationID: InstallationIdentifier.current,
            // Jedna decyzja „mock czy dostawca” dla całej aplikacji. W Demo zawsze
            // mock (bez sieci i bez kont), ale to fabryka o tym mówi, a nie ekran.
            transportFactory: { [dependencies] configuration in
                dependencies.makeVoiceTransport(configuration: configuration)
            }
        )
    }

    /// Mikrofon: start sesji albo wyciszenie nasłuchu. Wyciszony mikrofon **nie**
    /// kończy rozmowy i nie zmienia stanu połączenia (§5.5).
    func toggleListening() async {
        guard let dependencies else { return }
        let state = dependencies.voice.state
        if state.sessionID == nil || state.connection == .failed || state.connection == .ended {
            await startConversation()
            return
        }
        switch state.microphone {
        case .capturing:
            await dependencies.voice.setMicrophoneMuted(true)
        case .muted, .unavailable:
            await dependencies.voice.setMicrophoneMuted(false)
        }
    }

    func interrupt() async {
        guard let dependencies else { return }
        await dependencies.voice.interrupt(InterruptionRequest(reason: .userRequested))
    }

    func endSession() async {
        guard let dependencies else { return }
        isPlayingSummary = false
        await dependencies.voice.end(reason: .userRequested, preserveDraft: true, revokedCapability: false)
    }

    /// Przełączenie odpowiedzi głosowych. Referencja przy tej okazji zatrzymuje
    /// bieżące odtwarzanie (`toggleSpeech` → `stopVoice`).
    func toggleSpeech() async {
        speaksReplies.toggle()
        await stopVoiceModes()
    }

    /// Dyktowanie zapisuje tekst do pola polecenia i **nie** wykonuje polecenia (§5.1).
    func startDictation() async {
        guard let dependencies else { return }
        let prefix = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        dependencies.voice.onDictationResult = { [weak self] target, text in
            // Cel jest zamrożony na czas nagrania; reagujemy tylko na własne polecenie.
            guard case .assistantCommand = target else { return }
            guard let self else { return }
            self.composer = [prefix, text].filter { !$0.isEmpty }.joined(separator: " ")
        }
        await dependencies.voice.startDictation(
            // Brak przypadku `.assistantComposer` w `DictationTarget`; najbliższy
            // i jedyny właściwy dla pola polecenia jest `.assistantCommand`.
            target: .assistantCommand,
            language: dependencies.currentUser.interfaceLanguage,
            service: dependencies.makeDictationService()
        )
    }

    func finishDictation() async {
        guard let dependencies else { return }
        await dependencies.voice.finishDictation()
    }

    func readTurn(id: String) async {
        guard let turn = turns.compactMap({ turn -> MessageTurn? in
            if case .message(let message) = turn, message.id == id { return message }
            return nil
        }).first else { return }
        await speak(
            turn.text,
            language: .pl,
            isSummary: turn.isSummary,
            sourceID: nextSourceID("emma-turn")
        )
    }

    /// `speakAction` z referencji: wiadomość czytamy w języku klienta, resztę po polsku.
    /// Odsłuch czyta **bieżący szkic** przekazany z karty, nie wersję sprzed edycji (F03).
    func speakAction(actionID: ActionID, text: String) async {
        guard let index = actionIndex(actionID), case .action(let action) = turns[index] else { return }
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return }
        let clientLanguage = action.proposal.clientID
            .flatMap { clientID in clients.first { $0.id == clientID }?.language }
        await speak(
            spoken,
            language: action.proposal.kind == .reply ? (clientLanguage ?? .pl) : .pl,
            isSummary: false,
            sourceID: nextSourceID("emma-action")
        )
    }

    /// Odsłuch nie otwiera mikrofonu i nie mutuje danych (§5.1).
    private func speak(
        _ text: String,
        language: LanguageCode,
        isSummary: Bool,
        sourceID: String
    ) async {
        guard let dependencies else { return }
        isPlayingSummary = isSummary
        await dependencies.voice.startPlayback(
            SpeechPlaybackRequest(text: text, language: language, isSummary: isSummary, sourceID: sourceID),
            service: dependencies.makePlaybackService()
        )
    }

    /// Zatrzymuje odsłuch i dyktowanie przed nowym poleceniem (`stopVoice` z referencji).
    private func stopVoiceModes() async {
        guard let dependencies else { return }
        if dependencies.voice.state.mode == .dictation {
            await dependencies.voice.cancelDictation()
        }
        if dependencies.voice.state.mode == .playback || dependencies.voice.state.isPlaybackActive {
            await dependencies.voice.stopPlayback()
        }
        isPlayingSummary = false
    }

    // MARK: Treści (`briefing`, `caseSummary`, `draftText`)

    func briefing() async -> String {
        guard let dependencies else { return "" }
        let today = dependencies.today
        // Brak odpisu błędu na pustą kolekcję: `nil` jedzie do `EmmaBriefing` i znaczy
        // „nie udało się sprawdzić”, a `[]` znaczy „sprawdzone, nic nie ma” (F02).
        let events = try? await dependencies.repository.events(in: .day(today))
        let tasks = try? await dependencies.repository.tasks(
            filter: TaskFilter(scope: .open, dueOnOrBefore: today)
        )
        let names = Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0.displayName) })
        return EmmaBriefing.briefing(
            events: events,
            tasks: tasks,
            waitingForReply: clients.filter { $0.needsReply },
            clientNames: names
        )
    }

    func caseSummary(_ clientID: ClientID) async -> String {
        guard let dependencies else { return "" }
        let today = dependencies.today
        guard let client = client(id: clientID) else { return "Nie znalazłam tego klienta." }
        let legalCase = (try? await dependencies.repository.caseForClient(clientID)) ?? nil
        let notes = ((try? await dependencies.repository.notes(clientID: clientID, caseID: nil)) ?? [])
        let tasks = ((try? await dependencies.repository.tasks(
            filter: TaskFilter(scope: .open, clientID: clientID)
        )) ?? [])
        let events = ((try? await dependencies.repository.events(
            in: DateIntervalFilter(from: today, through: today.adding(days: 180))
        )) ?? [])
            .filter { $0.clientID == clientID && $0.status != .finished }
        let nextEvent = events.min { ($0.day, $0.time) < ($1.day, $1.time) }

        var parts: [String] = []
        if let legalCase {
            parts.append("\(client.displayName). \(legalCase.title). Status: \(legalCase.status.rawValue).")
        } else {
            parts.append("\(client.displayName). \(client.topic). Zgłoszenie: \(client.stage.rawValue).")
        }
        parts.append("")
        parts.append(legalCase?.summary ?? client.briefing)
        parts.append("")
        parts.append(notes.last.map { "Ostatnia notatka: \($0.text)" } ?? "Nie ma jeszcze notatki z rozmowy.")
        parts.append("")
        if let nextEvent {
            parts.append("Najbliższy termin: \(dependencies.dateText.dayLabel(nextEvent.day).lowercased()), \(nextEvent.time.hhmm). \(nextEvent.title). \(nextEvent.status.rawValue).")
        } else {
            parts.append("Brak kolejnego terminu.")
        }
        parts.append("")
        if tasks.isEmpty {
            parts.append("Nie ma otwartych zadań.")
        } else {
            parts.append("Otwarte zadania: " + tasks.map(\.title).joined(separator: "; ") + ".")
        }
        return parts.joined(separator: "\n")
    }

    /// `draftText(pid)` z referencji: treść w języku klienta, z najbliższym terminem.
    func draftText(_ clientID: ClientID) async -> String {
        guard let dependencies, let client = client(id: clientID) else { return "" }
        let today = dependencies.today
        let events = ((try? await dependencies.repository.events(
            in: DateIntervalFilter(from: today.adding(days: -30), through: today.adding(days: 180))
        )) ?? [])
            .filter { $0.clientID == clientID && $0.status != .finished }
        let event = events.min { ($0.day, $0.time) < ($1.day, $1.time) }

        if clientID == DemoFixtures.andriiID {
            return "Доброго дня. Отримав Ваше звернення щодо затримання брата. Будь ласка, повідомте, де він перебуває, та надішліть наявні документи. Після уточнення обставин узгодимо подальший контакт."
        }
        switch client.language {
        case .uk:
            let schedule = event.map {
                "Бачу нашу консультацію о \($0.time.hhmm). "
                    + ($0.status == .confirmed ? "Зустріч підтверджена." : "Час ще очікує на підтвердження.")
            } ?? "Отримав Ваше звернення."
            return "Доброго дня! \(schedule) Будь ласка, надішліть документи перед розмовою."
        case .ru:
            let schedule = event.map {
                "Вижу Вашу запись на \($0.day.isoString) в \($0.time.hhmm). "
                    + ($0.status == .confirmed ? "Встреча подтверждена." : "Время ещё ожидает подтверждения.")
            } ?? "Сообщите, пожалуйста, удобное время для разговора."
            return "Здравствуйте! Да, консультацию можно провести на русском языке. \(schedule)"
        case .pl:
            let schedule = event.map {
                "Widzę termin \($0.day.isoString), godz. \($0.time.hhmm). "
                    + ($0.status == .confirmed ? "Spotkanie jest potwierdzone." : "Termin oczekuje jeszcze na potwierdzenie.")
            } ?? "Proszę o podanie dogodnego terminu kontaktu."
            return "Dziękuję za wiadomość. \(schedule)"
        }
    }

    // MARK: Pomocnicze dla widoku

    var pendingAction: ActionTurn? {
        for turn in turns {
            if case .action(let action) = turn, action.proposal.state == .proposed {
                return action
            }
        }
        return nil
    }

    var statusText: String { voiceState.statusHeadline }

    var isMicrophoneCapturing: Bool { voiceState.microphone == .capturing }

    var isDictating: Bool { voiceState.mode == .dictation }

    var contextTitle: String {
        // Nazwa kontekstu firmowego pochodzi z reguły domenowej, a nie z literału
        // powtórzonego w tym pliku i w arkuszu wyboru kontekstu.
        guard let client = contextClient else { return AssistantContext.firm.displayLabel }
        if let caseID = linkedCases[client.id], let number = caseNumbers[caseID] {
            return "\(client.displayName) · \(number)"
        }
        return client.displayName
    }

    var contextClient: Client? {
        guard let clientID = dependencies?.emmaContext else { return nil }
        return client(id: clientID)
    }

    func clientName(for clientID: ClientID) -> String? {
        client(id: clientID)?.displayName
    }

    func client(id clientID: ClientID) -> Client? {
        clients.first { $0.id == clientID }
    }

    func isArmed(_ proposal: ActionProposal) -> Bool {
        dependencies?.voice.armedPresentationID == proposal.presentationID
    }

    func dueDateLabel(for proposal: ActionProposal) -> String? {
        guard let dueDate = proposal.taskDueDate else { return nil }
        return dependencies?.dateText.dayLabel(dueDate)
    }

    // MARK: Wewnętrzne

    private func currentContext() -> AssistantContext {
        guard let dependencies else { return .firm }
        guard let clientID = dependencies.emmaContext else { return .firm }
        return AssistantContext.client(clientID, caseID: linkedCases[clientID])
    }

    private func apply(voiceState state: VoiceUIState) {
        voiceState = state
        if let execution = state.lastExecution {
            updateExecution(execution)
        }
        if !state.isPlaybackActive, state.mode != .playback {
            isPlayingSummary = false
        }
    }

    private func updateExecution(_ execution: ActionExecution) {
        guard let index = actionIndex(execution.actionID), case .action(var action) = turns[index] else { return }
        action.execution = execution
        turns[index] = .action(action)
    }

    private func actionIndex(_ actionID: ActionID) -> Int? {
        turns.firstIndex { turn in
            if case .action(let action) = turn { return action.proposal.id == actionID }
            return false
        }
    }

    /// Okno potwierdzenia mogło minąć, zanim użytkownik zdążył zareagować.
    /// Pokazujemy ten stan od razu, żeby karta nie obiecywała możliwości, której nie ma.
    private func projectExpiredProposals() {
        guard let dependencies else { return }
        let now = dependencies.clock.now()
        for index in turns.indices {
            guard case .action(var action) = turns[index] else { continue }
            guard action.proposal.state == .proposed, action.proposal.isExpired(at: now) else { continue }
            action.proposal.state = .expired
            turns[index] = .action(action)
        }
    }

    @discardableResult
    private func appendUserTurn(_ text: String) -> String {
        let id = nextID("user")
        turns.append(.message(MessageTurn(id: id, role: .user, text: text, isSummary: false)))
        return id
    }

    @discardableResult
    private func appendAssistantTurn(_ text: String, isSummary: Bool) -> String {
        let id = nextID("emma")
        turns.append(.message(MessageTurn(id: id, role: .assistant, text: text, isSummary: isSummary)))
        return id
    }

    /// `answer(text, read)` z referencji.
    private func answer(_ text: String, isSummary: Bool = false, read: Bool = true) async {
        let id = appendAssistantTurn(text, isSummary: isSummary)
        guard read, speaksReplies else { return }
        await speak(text, language: .pl, isSummary: isSummary, sourceID: "emma-turn-\(id)")
    }

    private func nextID(_ prefix: String) -> String {
        sequence += 1
        return "\(prefix)-\(sequence)"
    }

    private func nextSourceID(_ prefix: String) -> String {
        nextID(prefix)
    }

    private func nextPresentationID(kind: ActionKind) -> String {
        "presentation-\(kind.rawValue)-\(nextID("p"))"
    }
}

// MARK: - Trwałość prezentacji
//
// Powłoka renderuje wyłącznie wybraną zakładkę (`RootShell.content`), więc widok
// Emmy powstaje na nowo przy każdym powrocie na zakładkę. Historia rozmowy należy
// do sesji, nie do widoku (§12.2), dlatego trzymamy ją w jednej instancji na proces.

enum AssistantStoreRegistry {
    @MainActor static let shared = AssistantStore()
}

// MARK: - Identyfikator instalacji
//
// Stabilny, lokalny i jawny — nie jest sekretem i nie jest kluczem dostawcy (§1.8).

enum InstallationIdentifier {
    private static let key = "emma.installation-id"

    static var current: String {
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let created = "demo-installation-\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(created, forKey: key)
        return created
    }
}
