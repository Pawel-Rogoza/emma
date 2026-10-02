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

    /// Doprecyzowanie, którego Emma nie może rozstrzygnąć sama (F14): kilka osób
    /// o tym samym imieniu. Trzymamy kandydatów i treść polecenia, żeby odpowiedź
    /// głosem dokończyła **to samo** zadanie, a nie zaczynała go od nowa.
    struct PendingClarification: Hashable {
        var kind: ActionKind
        var candidates: [ClientID]
        var text: String?
        var dueDate: LocalDate?
        var question: String
    }

    /// Skąd przyszła tura. Rozróżnienie jest istotne dla F15: jedna tura nie może
    /// być przetworzona i lokalnie, i u dostawcy.
    enum CommandOrigin {
        case typed
        case voice
    }

    // MARK: Stan publikowany

    @Published private(set) var turns: [Turn] = []
    /// Lustro stanu koordynatora. Ekran nie czyta koordynatora bezpośrednio w ciele
    /// widoku, żeby zmiany stanu były widoczne w SwiftUI.
    @Published private(set) var voiceState = VoiceUIState()
    @Published var composer = ""
    @Published var speaksReplies = true
    @Published private(set) var awaitingInput: AwaitingInput?
    @Published private(set) var pendingClarification: PendingClarification?
    @Published private(set) var clients: [Client] = []
    /// Czy trwa właśnie odsłuch streszczenia.
    @Published private(set) var isPlayingSummary = false
    /// Emma pisze odpowiedź na pytanie wpisane bez rozmowy głosowej.
    @Published private(set) var isAwaitingTextReply = false
    /// Rozmowa pisemna na serwerze — kolejne pytania mają jej historię.
    private var textConversationID: Int?

    // MARK: Zależności wewnętrzne

    private(set) weak var dependencies: AppDependencies?
    private var voiceObserver: UUID?
    private var sequence = 0
    /// Ślady zużytych tur (F04). Historia nie dopisuje tej samej tury dwa razy,
    /// a karta propozycji powstaje raz na identyfikator propozycji.
    private var consumedUserTurnID: String?
    private var consumedAgentTurnID: String?
    /// Karta w historii, do której trafia bieżąca (strumieniowana) tura Emmy.
    private var agentHistoryMessageID: String?
    private var localAnswerTurnID: String?
    private var localProposalTurnID: String?
    private var adoptedProposalID: ActionID?
    /// Klienci z ostatnio przedstawionej listy terminów (§6-B).
    private var lastBriefedClientIDs: [ClientID] = []
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
        // Narzędzia `app_*` Gemini Live wykonuje ten ekran: to on pokazuje
        // karty propozycji i zna powiązania klient → sprawa.
        dependencies.appToolHandler = self
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
        // Klient może mieć kilka prowadzonych spraw. `uniqueKeysWithValues`
        // zatrzymywał wtedy aplikację (duplikat klucza), więc świadomie wiążemy
        // kontekst z najnowszą sprawą.
        linkedCases = Dictionary(
            cases.filter { $0.status.isActive }
                .sorted { $0.createdAt > $1.createdAt }
                .map { ($0.clientID, $0.id) },
            uniquingKeysWith: { newest, _ in newest }
        )
        caseNumbers = Dictionary(cases.map { ($0.id, $0.number) }, uniquingKeysWith: { first, _ in first })
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

    func handleCommand(
        _ raw: String,
        origin: CommandOrigin = .typed,
        turnID: String? = nil
    ) async {
        guard let dependencies else { return }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if origin == .typed { await stopVoiceModes() }
        appendUserTurn(text)

        // W rozmowie Gemini Live turą rządzi model: słyszy wypowiedź i steruje
        // aplikacją narzędziami `app_*`. Lokalny parser tej samej transkrypcji
        // (która przychodzi dopiero po odpowiedzi modelu) tworzył drugą,
        // niezależną reakcję — np. kartę, o której model nic nie wiedział.
        // Parser zostaje dla tekstu wpisanego i dla trybu Demo.
        if origin == .voice, providerOwnsVoice { return }

        // Odpowiedź na pytanie Emmy („Olena Kovalenko czy Olena Nowak?”) kończy
        // to samo polecenie, zamiast zaczynać nowe (F14).
        if let clarification = pendingClarification {
            if await resolveClarification(clarification, with: text) { return }
            await answer(clarification.question)
            return
        }

        let intent = AssistantIntentParser.parse(text, today: dependencies.today)
        switch intent.kind {
        case .confirm:
            // Wpisane „tak” to działanie w interfejsie (`.directUIButton`). „Tak”
            // z transkrypcji mowy nim nie jest — mógł je powiedzieć telewizor albo
            // klient na głośniku — więc idzie jako `.authenticatedVoiceTurn`
            // i podlega regułom głosu: uzbrojona prezentacja, cofnięte zapisy.
            if let pending = pendingAction {
                await confirmFromTypedCommand(
                    pending,
                    origin: origin == .voice ? .authenticatedVoiceTurn : .directUIButton
                )
            } else {
                await answer("Nie ma przygotowanego działania do zatwierdzenia.")
            }
            return

        case .cancel:
            if let pending = pendingAction {
                await cancel(actionID: pending.proposal.id)
            } else {
                awaitingInput = nil
                await answer("Anulowano. Możemy przejść do kolejnego polecenia.")
            }
            return

        case .correction:
            guard await applyCorrection(intent, original: text) else {
                await answer("Nie mam czego poprawić. Podaj pełne polecenie, a przygotuję propozycję.")
                return
            }
            return

        case .briefing:
            // Pytanie odczytowe nie kasuje szkicu i nie wymaga zgody (F15).
            await answer(await briefing(for: intent.dueDate), isSummary: true)
            return

        case .caseSummary:
            await runCaseSummary(text, intent: intent, origin: origin, turnID: turnID)
            return

        case .unknown:
            // Jedna tura ma jednego właściciela (F15): polecenie, którego lokalny
            // dialog nie rozpoznaje, dostaje dostawca — ale tylko wtedy, gdy
            // istnieje sesja. Lokalnie odpowiadamy wyłącznie jako zastępstwo.
            if origin == .typed, hasActiveSession {
                if let turnID { localAnswerTurnID = turnID }
                await forwardTypedTurn(text)
                return
            }
            if origin == .voice, providerOwnsVoice {
                // W produkcyjnej rozmowie dostawca usłyszał tę turę i odpowiada.
                // Lokalne „nie rozumiem" dopisywałoby drugą odpowiedź na to samo
                // pytanie i odbierało Emmie prawo do odpowiedzi (localAnswerTurnID).
                return
            }
            // Bez rozmowy głosowej pytanie dostaje Emma pisemnie (model tekstowy
            // na serwerze z odczytem danych kancelarii). Wcześniej kończyło się
            // „nie rozpoznałam polecenia” — działały tylko sztywne komendy.
            if origin == .typed, await askEmmaInWriting(text) { return }
            if let turnID { localAnswerTurnID = turnID }
            await answer(unrecognizedMessage)
            return

        case .reply, .note, .task, .event:
            break
        }

        // Nowa czynność przy oczekującej propozycji: nie tworzymy drugiej karty,
        // ale mówimy wprost, co można zrobić (poprawić, odsłuchać, anulować).
        if pendingAction != nil {
            await answer("Najpierw zatwierdź albo anuluj przygotowane działanie. Możesz je też poprawić, np. „zmień na 20 minut”.")
            return
        }

        // Treść do przygotowanego szkicu (notatka, zadanie, spotkanie).
        if let awaiting = awaitingInput {
            awaitingInput = nil
            let kind = intent.commandKind ?? awaiting.kind
            if await newAction(kind: kind, clientID: awaiting.clientID, text: text) != nil, readsAutomatically {
                await speak("Przygotowałam treść do zatwierdzenia.", language: .pl, isSummary: false, sourceID: nextSourceID("emma-note"))
            }
            return
        }

        await startIntent(intent, original: text, origin: origin, turnID: turnID)
    }

    /// Polecenie tworzące akcję: rozwiązanie odbiorcy, brakujące pola i propozycja.
    private func startIntent(
        _ intent: AssistantIntent,
        original: String,
        origin: CommandOrigin,
        turnID: String?
    ) async {
        guard let dependencies else { return }
        let lowered = original.lowercased()
        let resolution = resolveClient(in: original, lowered: lowered)
        var clientID: ClientID?
        switch resolution {
        case .multiple(let candidates):
            if intent.kind == .event || intent.kind == .task {
                // Zadanie i spotkanie mogą poczekać na osobę — pytamy raz i kończymy
                // to samo polecenie po odpowiedzi, zamiast otwierać selektor.
                let names = candidates.map { client(id: $0)?.displayName ?? "?" }
                let question = "Która osoba? " + names.joined(separator: " czy ") + "?"
                pendingClarification = PendingClarification(
                    kind: intent.commandKind ?? .task,
                    candidates: candidates,
                    text: intent.text,
                    dueDate: intent.dueDate,
                    question: question
                )
                await answer(question)
                return
            }
            await answer("Polecenie dotyczy kilku osób. Wybierz jednego klienta w polu kontekstu.")
            return
        case .unknown:
            await answer("Nie rozpoznałam wskazanego klienta. Wybierz go w polu kontekstu.")
            return
        case .resolved(let id):
            clientID = id
        case .context:
            clientID = dependencies.emmaContext
        }

        if case .event = intent.kind {
            await openEventDraft(intent, clientID: clientID)
            return
        }

        if intent.requiresRecipient, clientID == nil {
            await answer("Wybierz klienta w polu kontekstu, żeby powiązać z nim polecenie.")
            return
        }
        dependencies.emmaContext = clientID

        // Brak treści to pytanie, nie zgadywanie (F14).
        guard let payload = intent.text?.trimmingCharacters(in: .whitespacesAndNewlines), !payload.isEmpty else {
            if let kind = intent.commandKind, kind == .reply, let clientID {
                await noteLocalOwnership(origin: origin, turnID: turnID)
                await prepareReply(clientID)
                return
            }
            let kind = intent.commandKind ?? .note
            awaitingInput = AwaitingInput(kind: kind, clientID: clientID)
            await answer(slotQuestion(for: kind, clientID: clientID))
            return
        }

        await noteLocalOwnership(origin: origin, turnID: turnID)
        let kind = intent.commandKind ?? .note
        await newAction(kind: kind, clientID: clientID, text: payload, dueDate: intent.dueDate)
        await answer(await proposalSummary(kind: kind, intent: intent, clientID: clientID))
    }

    /// Pytanie o brakujące pole. Jedno pytanie na turę (§5).
    private func slotQuestion(for kind: ActionKind, clientID: ClientID?) -> String {
        let who = clientID.flatMap { client(id: $0)?.displayName }
        switch kind {
        case .note:
            return who.map { "Co zapisać w notatce dla \($0)? Podyktuj lub wpisz treść." }
                ?? "Co zapisać w notatce? Podyktuj lub wpisz treść."
        case .task:
            return who.map { "Jakie zadanie dodać dla \($0)? Wpisz lub podyktuj treść." }
                ?? "Jakie zadanie dodać? Wpisz lub podyktuj treść."
        case .reply:
            return who.map { "Co napisać do \($0)? Podyktuj treść wiadomości." }
                ?? "Co napisać? Podyktuj treść wiadomości."
        }
    }

    /// Potwierdzenie przygotowanej propozycji z podaniem **bezwzględnego** terminu
    /// (§6-C). Godzina jest jawnie pokazana, a ograniczenie listy zadań wypowiedziane.
    private func proposalSummary(kind: ActionKind, intent: AssistantIntent, clientID: ClientID?) async -> String {
        guard let dependencies else { return "Sprawdź treść i zatwierdź." }
        var parts: [String] = []
        switch kind {
        case .reply: parts.append("Wiadomość gotowa do sprawdzenia.")
        case .note: parts.append("Notatka gotowa do sprawdzenia.")
        case .task: parts.append("Zadanie gotowe do sprawdzenia.")
        }
        if let dueDate = intent.dueDate {
            parts.append("Termin: \(dueDate.isoString).")
        }
        if let dueTime = intent.dueTime {
            parts.append("Godzina \(dueTime.hhmm) jest w treści polecenia; lista zadań pokazuje samą datę.")
        }
        _ = dependencies
        return parts.joined(separator: " ")
    }

    /// „Dodaj spotkanie”: otwiera **formularz nowego terminu** z rozpoznanymi
    /// polami (F14), zamiast odpowiadać briefingiem albo udawać zapis.
    private func openEventDraft(_ intent: AssistantIntent, clientID: ClientID?) async {
        guard let dependencies else { return }
        let title = intent.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        dependencies.pendingEventDraft = EventDraftSeed(
            title: (title?.isEmpty == false) ? title : nil,
            day: intent.dueDate,
            time: intent.dueTime
        )
        dependencies.present(.eventForm(
            editing: nil,
            clientID: clientID,
            caseID: clientID.flatMap { linkedCases[$0] },
            initialDay: intent.dueDate
        ))
        var parts = ["Otwieram formularz nowego terminu"]
        if let day = intent.dueDate { parts.append("na \(day.isoString)") }
        if let time = intent.dueTime { parts.append("o \(time.hhmm)") }
        parts.append("- sprawdź pola i zapisz, żeby termin powstał naprawdę.")
        await answer(parts.joined(separator: " "))
    }

    /// Zapisanie właściciela tury: lokalny dialog odpowiedział i utworzył propozycję,
    /// więc propozycja dostawcy z tej samej tury nie zrobi drugiej karty (F15).
    private func noteLocalOwnership(origin: CommandOrigin, turnID: String?) {
        guard origin == .voice, let turnID else { return }
        localAnswerTurnID = turnID
        localProposalTurnID = turnID
    }

    private var unrecognizedMessage: String {
        "Nie rozpoznałam tego polecenia. Powiedz na przykład: „jakie mam dzisiaj terminy”, „przygotuj odpowiedź do Oleny” albo „dodaj zadanie na jutro”."
    }

    private var hasActiveSession: Bool {
        guard let dependencies else { return false }
        let state = dependencies.voice.state
        return state.sessionID != nil && state.connection == .connected
    }

    /// Czy w aktywnej rozmowie mówi Emma od dostawcy. Wtedy lokalny syntezator
    /// systemowy musi milczeć: jedna sesja ma jeden głos. W Demo transport jest
    /// mockiem bez własnego audio, więc systemowy odsłuch pozostaje jedynym głosem.
    var providerOwnsVoice: Bool {
        guard let dependencies, !dependencies.configuration.usesMockServices else { return false }
        return hasActiveSession
    }

    /// Pytanie odczytowe o dzień. „A jutro?” zmienia zakres daty, nie rodzaj.
    private func briefing(for date: LocalDate?) async -> String {
        guard let dependencies else { return "" }
        let day = date ?? dependencies.today
        if day != dependencies.today {
            return await briefing(on: day)
        }
        return await briefing()
    }

    private func runCaseSummary(
        _ text: String,
        intent: AssistantIntent,
        origin: CommandOrigin,
        turnID: String?
    ) async {
        guard let dependencies else { return }
        let lowered = text.lowercased()
        let resolution = resolveClient(in: text, lowered: lowered)
        var clientID: ClientID?
        switch resolution {
        case .resolved(let id): clientID = id
        case .context: clientID = dependencies.emmaContext
        case .multiple:
            await answer("Polecenie dotyczy kilku osób. Wybierz jednego klienta w polu kontekstu.")
            return
        case .unknown:
            clientID = dependencies.emmaContext
        }
        // „Przygotuj mnie do pierwszego” dotyczy pierwszego terminu z ostatniej
        // listy, a nie dowolnego klienta (F14/§6-B). Granice listy są znane.
        if text.lowercased().contains("pierwsz"), let first = lastBriefedClientIDs.first {
            clientID = first
        }
        guard let clientID else {
            await answer("Wybierz klienta w polu kontekstu, żeby powiązać z nim polecenie.")
            return
        }
        dependencies.emmaContext = clientID
        await noteLocalOwnership(origin: origin, turnID: turnID)
        await answer(await caseSummary(clientID), isSummary: true)
    }

    /// Odpowiedź na pytanie doprecyzowujące: nazwisko, numer opcji albo „pierwszy”.
    /// Zwraca `true`, gdy odpowiedź rozstrzygnęła i polecenie poszło dalej.
    private func resolveClarification(_ clarification: PendingClarification, with text: String) async -> Bool {
        guard let dependencies else { return false }
        let lowered = text.lowercased()
        var chosen: ClientID?

        if let index = ordinalIndex(in: lowered), clarification.candidates.indices.contains(index) {
            chosen = clarification.candidates[index]
        } else {
            let names = clarification.candidates.compactMap { client(id: $0) }
            chosen = matchCandidate(in: lowered, among: names)
        }

        guard let clientID = chosen, let client = client(id: clientID) else {
            return false
        }
        pendingClarification = nil
        dependencies.emmaContext = clientID
        let kind = clarification.kind
        if let payload = clarification.text, !payload.isEmpty {
            await newAction(kind: kind, clientID: clientID, text: payload, dueDate: clarification.dueDate)
            await answer("Dobrze, \(client.displayName). Sprawdź treść i zatwierdź.")
        } else {
            awaitingInput = AwaitingInput(kind: kind, clientID: clientID)
            await answer(slotQuestion(for: kind, clientID: clientID))
        }
        return true
    }

    /// Wybór osoby spośród kandydatów. Nazwisko rozstrzyga, bo `PersonResolver`
    /// celowo łączy osoby po imieniu — przy dwóch Olenach imię nie wystarcza,
    /// a to właśnie ten przypadek kazał Emmie dopytać (F14).
    private func matchCandidate(in lowered: String, among candidates: [Client]) -> ClientID? {
        let tokens = { (client: Client) in
            client.displayName
                .lowercased()
                .split(whereSeparator: { $0 == " " || $0 == "-" })
                .map(String.init)
        }
        // 1. Nazwisko (ostatni człon) jest najmocniejszym sygnałem.
        let bySurname = candidates.filter { candidate in
            guard let surname = tokens(candidate).last, surname.count >= 4 else { return false }
            return lowered.contains(surname)
        }
        if bySurname.count == 1 { return bySurname[0].id }
        // 2. Pełne imię i nazwisko razem.
        let byFullName = candidates.filter { lowered.contains($0.displayName.lowercased()) }
        if byFullName.count == 1 { return byFullName[0].id }
        // 3. Inicjał nazwiska: „nowak” albo „N.” — ostatnia deska ratunku.
        if case .resolved(let id) = PersonResolver.resolve(lowered, among: candidates) { return id }
        return nil
    }

    /// „pierwsza”, „druga”, „trzecia” — wybór pozycji bez dotykania ekranu (§5).
    private func ordinalIndex(in lowered: String) -> Int? {
        let ordinals = ["pierwsz": 0, "drug": 1, "trzeci": 2, "czwart": 3, "piąt": 4]
        for (form, index) in ordinals where lowered.contains(form) { return index }
        return nil
    }

    /// Poprawka oczekującej propozycji: treść, termin albo odbiorca (§6-A, §6-C).
    @discardableResult
    private func applyCorrection(_ intent: AssistantIntent, original: String) async -> Bool {
        guard let dependencies, let pending = pendingAction, let revision = intent.revision else { return false }
        let actionID = pending.proposal.id
        var didSomething = false

        // Zmiana odbiorcy („nie, do Dmytro”) to inna zgoda niż nowa treść: dotyczy
        // innej osoby, więc silnik akcji unieważnia uzbrojenie (F14).
        if let recipient = revision.recipient,
           case .resolved(let newClient) = PersonResolver.resolve(recipient, among: clients),
           newClient != pending.proposal.clientID {
            if let changed = await dependencies.voice.changeActionContext(
                actionID: actionID,
                clientID: newClient,
                caseID: linkedCases[newClient],
                threadID: nil
            ) {
                replaceProposal(changed)
                let name = client(id: newClient)?.displayName ?? Client.unknownDisplayName
                await answer("Zmieniłam odbiorcę na \(name). Zgoda na poprzednią wersję nie obowiązuje.")
                return true
            }
        }

        if let newText = revision.text {
            if let revised = await dependencies.voice.reviseAction(actionID: actionID, newText: newText) {
                replaceProposal(revised)
                didSomething = true
                await answer("Poprawiłam treść. Zgoda na poprzednią wersję nie obowiązuje.")
            }
        } else if let quantity = revision.quantity, let unit = revision.unit,
                  let replaced = replacingQuantity(in: pending.proposal.text, with: quantity, unit: unit) {
            if let revised = await dependencies.voice.reviseAction(actionID: actionID, newText: replaced) {
                replaceProposal(revised)
                didSomething = true
                await answer("Poprawiłam na \(quantity) \(unit). Zgoda na poprzednią wersję nie obowiązuje.")
            }
        }

        if let date = revision.date, pending.proposal.kind == .task {
            if let rescheduled = await dependencies.voice.rescheduleAction(actionID: actionID, dueDate: date) {
                replaceProposal(rescheduled)
                didSomething = true
                await answer("Nowy termin to \(date.isoString). Zgoda na poprzednią wersję nie obowiązuje.")
            }
        }

        return didSomething
    }

    /// Podmiana ilości w treści („spóźnię się 15 minut” → „spóźnię się 20 minut”).
    /// Nie zmieniamy nic, gdy w treści nie ma liczby z tą samą jednostką.
    private func replacingQuantity(in text: String, with value: Int, unit: String) -> String? {
        let pattern = #"\b(\d{1,3})(\s*)([a-ząćęłńóśźż]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 3), in: text),
              text[unitRange].lowercased().hasPrefix(String(unit.prefix(3))) else { return nil }
        var replaced = text
        replaced.replaceSubrange(numberRange, with: String(value))
        return replaced
    }

    private func replaceProposal(_ proposal: ActionProposal) {
        guard let index = actionIndex(proposal.id), case .action(var action) = turns[index] else { return }
        action.proposal = proposal
        turns[index] = .action(action)
    }

    private enum ClientResolution {
        case resolved(ClientID)
        case multiple([ClientID])
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
        case .multiple(let candidates):
            return .multiple(candidates)
        case .unknown, .none:
            let addressed = ["do ", "dla ", "klienta "].contains { lowered.contains($0) }
            return addressed ? .unknown : .context
        }
    }

    private func isBare(_ lowered: String, _ forms: [String]) -> Bool {
        let stripped = lowered.trimmingCharacters(in: CharacterSet(charactersIn: " .!"))
        return forms.contains(stripped)
    }

    /// Pytanie do Emmy pisemnie. `false`, gdy nie ma serwera z modelem
    /// (Demo, starszy backend) — wtedy zostaje lokalna odpowiedź.
    private func askEmmaInWriting(_ text: String) async -> Bool {
        guard let dependencies, let repository = dependencies.repository as? BackendRepository else { return false }
        isAwaitingTextReply = true
        defer { isAwaitingTextReply = false }
        let context = dependencies.emmaContext.flatMap { client(id: $0) }
        do {
            let result = try await repository.askEmma(text, conversationID: textConversationID, context: context)
            textConversationID = result.conversationID
            await answer(result.reply, read: false)
            return true
        } catch BackendRepositoryError.notAvailableInBackend {
            return false
        } catch {
            await answer(ScreenLoad.message(for: error, fallback: "Emma chwilowo nie odpowiada. Spróbuj ponownie za chwilę."), read: false)
            return true
        }
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

        let replyThread = kind == .reply ? await replyThreadID(for: clientID) : nil
        let proposal = await dependencies.voice.prepareAction(
            kind: kind,
            clientID: clientID,
            caseID: clientID.flatMap { linkedCases[$0] },
            threadID: replyThread,
            text: trimmed,
            actor: dependencies.currentUser,
            presentationID: nextPresentationID(kind: kind),
            taskDueDate: kind == .task ? (dueDate ?? dependencies.today) : nil
        )
        guard let proposal else {
            // Backend odrzucił propozycję — powód musi trafić do rozmowy,
            // inaczej polecenie „znika” bez śladu.
            if let reason = dependencies.voice.state.lastError {
                await answer(reason)
            }
            return nil
        }

        awaitingInput = nil
        let turn = ActionTurn(proposal: proposal, execution: nil)
        turns.append(.action(turn))
        projectExpiredProposals()
        return turn
    }

    /// Wątek, do którego trafi odpowiedź: prawdziwy wątek klienta z repozytorium.
    /// Audyt 29.09.2026: identyfikator był sklejany ze wzorca danych demo
    /// („thread-client-…”), więc po podłączeniu WhatsApp odpowiedź celowałaby
    /// w nieistniejący wątek. Wzorzec zostaje wyłącznie jako zapas, gdy klient
    /// nie ma jeszcze żadnego wątku.
    private func replyThreadID(for clientID: ClientID?) async -> ThreadID? {
        guard let clientID, let dependencies else { return nil }
        let threads = (try? await dependencies.repository.threads()) ?? []
        return threads.first { $0.clientID == clientID }?.id ?? DemoFixtures.threadID(for: clientID)
    }

    func prepareReply(_ clientID: ClientID) async {
        guard let client = client(id: clientID) else { return }
        // Backend nie przyjmuje karty „Wiadomość” (422 — wysyłka idzie z pola
        // rozmowy, z bramką okna 24 h). Szkic trafia więc tam, gdzie się go
        // wysyła, zamiast kończyć skrót komunikatem o błędzie.
        if let dependencies, dependencies.repository is BackendRepository {
            guard let threadID = await conversationID(for: clientID, dependencies: dependencies) else {
                await answer("Nie ma jeszcze rozmowy WhatsApp z \(client.displayName) — odpisać można dopiero, gdy klient napisze pierwszy.")
                return
            }
            // Szkic pisze model na serwerze z treści rozmowy, prosto w polu
            // odpowiedzi — zamiast szablonu niezwiązanego z pytaniem klienta.
            dependencies.openThreadWithEmmaDraft(threadID)
            await answer("Piszę szkic odpowiedzi do \(client.displayName) w rozmowie WhatsApp — przeczytaj i wyślij.")
            return
        }
        guard let turn = await newAction(kind: .reply, clientID: clientID, text: await draftText(clientID)) else { return }
        if readsAutomatically {
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

    private func confirmFromTypedCommand(
        _ pending: ActionTurn,
        origin: ActionEngine.Confirmation.Origin
    ) async {
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
        await performConfirmation(pending.proposal, origin: origin)
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

    /// „Rozmawiaj”: nowa rozmowa z Emmą od czystego stanu.
    ///
    /// Nie dziedziczymy wątku klienta ani historii poprzedniej rozmowy: kontekst
    /// wraca do całej kancelarii, a prezentacja (tury, propozycje, doprecyzowania,
    /// szkic w polu) jest czyszczona. Koordynator odrzuca też zachowany szkic,
    /// żeby zakończenie nowej sesji nie wskrzesiło starej propozycji. Dzięki temu
    /// przycisk nie odtwarza scenki klienta (np. Oleny) z danych demo.
    func startNewConversation() async {
        guard let dependencies else { return }
        dependencies.emmaContext = nil
        dependencies.pendingEmmaAction = nil
        dependencies.pendingVoiceStart = false
        resetPresentation()
        dependencies.voice.discardPreservedPresentation()
        await startConversation()
    }

    /// Wylogowanie albo zmiana konta: historia rozmowy i dane klientów nie mogą
    /// przetrwać do następnej sesji. Magazyn jest współdzielony przez cały
    /// proces, więc bez tego nowy użytkownik widział poprzednią rozmowę.
    func clearForSignOut() {
        resetPresentation()
        clients = []
        linkedCases = [:]
        caseNumbers = [:]
    }

    /// Czyszczenie stanu prezentacji przed nową rozmową. Numeracja identyfikatorów
    /// zostaje — ma rosnąć w obrębie procesu, a nie zaczynać się od nowa.
    private func resetPresentation() {
        turns.removeAll()
        composer = ""
        awaitingInput = nil
        pendingClarification = nil
        consumedUserTurnID = nil
        consumedAgentTurnID = nil
        agentHistoryMessageID = nil
        localAnswerTurnID = nil
        localProposalTurnID = nil
        adoptedProposalID = nil
        lastBriefedClientIDs = []
        isPlayingSummary = false
    }

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
            // Jeden identyfikator instalacji dla całej aplikacji (FIX A): ten sam,
            // którym podpisuje się logowanie (`AuthStore`). Wcześniej warstwa głosu
            // generowała własny identyfikator, więc backend odrzucał każde
            // `POST /voice/sessions` jako należące do innej instalacji (403).
            installationID: InstallationIdentity.current(),
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
        // Jedna ścieżka zakończenia dla docku i globalnego mini-panelu (F06).
        await dependencies.endVoiceSession()
    }

    /// Wyciszenie mikrofonu z docku Emmy. Ta sama metoda, której używa mini-panel.
    func toggleMicrophone() async {
        guard let dependencies else { return }
        await dependencies.toggleVoiceMicrophone()
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
        return await briefing(on: dependencies.today)
    }

    /// Briefing wskazanego dnia („A jutro?” zmienia zakres daty, §6-B).
    /// Lista pierwszego dnia zapamiętuje klientów, żeby „przygotuj mnie do
    /// pierwszego” odnosiło się do tego, co użytkownik właśnie usłyszał.
    func briefing(on day: LocalDate) async -> String {
        guard let dependencies else { return "" }
        // Brak odpisu błędu na pustą kolekcję: `nil` jedzie do `EmmaBriefing` i znaczy
        // „nie udało się sprawdzić”, a `[]` znaczy „sprawdzone, nic nie ma” (F02).
        let events = try? await dependencies.repository.events(in: .day(day))
        let tasks = try? await dependencies.repository.tasks(
            filter: TaskFilter(scope: .open, dueOnOrBefore: day)
        )
        let names = Dictionary(clients.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        lastBriefedClientIDs = (events ?? [])
            .sorted { ($0.day, $0.time) < ($1.day, $1.time) }
            .compactMap { $0.clientID }
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
            // Tylko nadchodzące: szkic nie może pisać klientowi o terminie, który minął.
            .filter { $0.clientID == clientID && $0.status != .finished && $0.day >= today }
        let event = events.min { ($0.day, $0.time) < ($1.day, $1.time) }
        // Data dla klienta „12.09”, a nie zapis techniczny „2026-09-12”.
        func shortDate(_ day: LocalDate) -> String {
            String(format: "%02d.%02d", day.day, day.month)
        }

        if clientID == DemoFixtures.andriiID {
            return "Здравствуйте. Получил Ваше обращение по поводу задержания брата. Пожалуйста, сообщите, где он находится, и пришлите имеющиеся документы. После уточнения обстоятельств согласуем дальнейший контакт."
        }
        // Po polsku albo po rosyjsku — wg tego, jak klient pisze; nigdy po ukraińsku.
        switch await replyLanguage(for: client, dependencies: dependencies) {
        case .ru, .uk:
            let schedule = event.map {
                "Вижу Вашу запись на \(shortDate($0.day)) в \($0.time.hhmm). "
                    + ($0.status == .confirmed ? "Встреча подтверждена." : "Время ещё ожидает подтверждения.")
            } ?? "Сообщите, пожалуйста, удобное время для разговора."
            return "Здравствуйте! \(schedule)"
        case .pl:
            let schedule = event.map {
                "Widzę termin \(shortDate($0.day)), godz. \($0.time.hhmm). "
                    + ($0.status == .confirmed ? "Spotkanie jest potwierdzone." : "Termin oczekuje jeszcze na potwierdzenie.")
            } ?? "Proszę o podanie dogodnego terminu kontaktu."
            return "Dziękuję za wiadomość. \(schedule)"
        }
    }

    /// Język odpowiedzi z ostatnich wiadomości klienta (`ReplyLanguage`).
    private func replyLanguage(for client: Client, dependencies: AppDependencies) async -> LanguageCode {
        guard let threadID = await conversationID(for: client.id, dependencies: dependencies) else {
            return ReplyLanguage.forReply(clientLanguage: client.language, lastIncomingText: nil)
        }
        let messages = (try? await dependencies.repository.latestMessages(threadID: threadID, limit: 20)) ?? []
        return ReplyLanguage.forReply(clientLanguage: client.language, messages: MessageOrdering.sorted(messages))
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

    var isMicrophoneCapturing: Bool { voiceState.isCapturingMicrophone }

    var isDictating: Bool { voiceState.mode == .dictation }

    /// Puste pole nie wysyła (F07/§4). Reguła w jednym miejscu, żeby przycisk
    /// i `sendComposer()` nie mogły się rozjechać.
    var canSendComposer: Bool {
        !composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
        consumeVoiceTurn(state)
        adoptProviderProposal(state)
    }

    /// Domknięcie przepływu głos → historia (F04).
    ///
    /// Jedna wypowiedź to jedna tura: rozstrzyga identyfikator tury, nie treść,
    /// więc powtórzona publikacja tego samego stanu nic nie dopisze, a to samo
    /// „tak” wypowiedziane dwa razy to dwie osobne tury.
    private func consumeVoiceTurn(_ state: VoiceUIState) {
        if let turnID = state.committedUserTurnID,
           turnID != consumedUserTurnID,
           !state.committedUserTranscript.isEmpty {
            consumedUserTurnID = turnID
            let transcript = state.committedUserTranscript
            Task { await self.handleCommand(transcript, origin: .voice, turnID: turnID) }
        }
        guard let agentTurnID = state.agentTurnID, !state.agentText.isEmpty else { return }
        // Ta sama tura Emmy przychodzi fragmentami (transkrypcja strumieniowa).
        // Aktualizujemy jej jedną kartę, zamiast dopisywać nową przy każdym
        // fragmencie — to był powód wielokrotnie powielonych odpowiedzi.
        if agentTurnID == consumedAgentTurnID {
            if let messageID = agentHistoryMessageID {
                updateAssistantTurn(messageID, text: state.agentText)
            }
            return
        }
        consumedAgentTurnID = agentTurnID
        agentHistoryMessageID = nil
        // Jeden właściciel tury (F15): gdy lokalny dialog już odpowiedział na tę
        // wypowiedź, tekst dostawcy nie dubluje odpowiedzi w historii.
        guard localAnswerTurnID != consumedUserTurnID else { return }
        agentHistoryMessageID = appendAssistantTurn(state.agentText, isSummary: false)
    }

    private func updateAssistantTurn(_ id: String, text: String) {
        guard let index = turns.lastIndex(where: { $0.id == id }),
              case .message(var message) = turns[index],
              message.text != text else { return }
        message.text = text
        turns[index] = .message(message)
    }

    /// Propozycja dostawcy trafia do historii jako karta (F04). Jedna propozycja
    /// to jedna karta: ten sam identyfikator aktualizuje istniejącą, nie tworzy
    /// drugiej. Propozycja z tury, którą lokalny dialog już obsłużył, nie tworzy
    /// drugiej karty na tę samą wypowiedź (F15).
    private func adoptProviderProposal(_ state: VoiceUIState) {
        guard let proposal = state.activeProposal else { return }
        guard proposal.id != adoptedProposalID else { return }
        if let turnID = consumedUserTurnID, turnID == localProposalTurnID { return }
        adoptedProposalID = proposal.id
        if let index = actionIndex(proposal.id), case .action(var action) = turns[index] {
            action.proposal = proposal
            turns[index] = .action(action)
        } else {
            turns.append(.action(ActionTurn(proposal: proposal, execution: nil)))
        }
        projectExpiredProposals()
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
    ///
    /// Automatyczna odpowiedź nie jest czytana na głos, gdy trwa rozmowa
    /// z Emmą od dostawcy: wtedy mówi Emma, a systemowy syntezator byłby
    /// drugim, obcym głosem w tej samej sesji (zgłoszenie „prototyp gada").
    /// Świadomy odsłuch („Odsłuchaj", `readTurn`/`speakAction`) nadal działa.
    private func answer(_ text: String, isSummary: Bool = false, read: Bool = true) async {
        let id = appendAssistantTurn(text, isSummary: isSummary)
        guard read, readsAutomatically else { return }
        await speak(text, language: .pl, isSummary: isSummary, sourceID: "emma-turn-\(id)")
    }

    /// Czy odpowiedź czytać na głos sama z siebie. Poza Demo — nigdy: głosem
    /// Emmy jest rozmowa („Rozmawiaj”), a systemowy syntezator iOS brzmiał
    /// jak robot i odzywał się np. po skrócie „Odpowiedź z Emmą” (02.10.2026).
    /// Świadomy odsłuch („Odsłuchaj”) działa jak dotąd.
    private var readsAutomatically: Bool {
        guard speaksReplies, !providerOwnsVoice else { return false }
        return dependencies?.configuration.usesMockServices ?? false
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

// Identyfikator instalacji ma jedno źródło: `InstallationIdentity`
// (`Features/Auth/KeychainMobileSessionStore.swift`). Trzymanie drugiego,
// niezależnego identyfikatora dla głosu („demo-installation-…”) dawało dwa
// różne `installation_id` w jednej instalacji i backend odpowiadał 403.
