import Foundation
import SwiftUI

// MARK: - Zależności aplikacji
//
// Jedno miejsce, w którym powstają wszystkie obiekty współdzielone:
// repozytorium danych demo, koordynator sesji głosowej, zegar i konfiguracja.
// Ekrany nie tworzą własnych kopii tych obiektów i nie znają implementacji
// dostawców — dzięki temu jeden `VoiceSessionCoordinator` obsługuje rozmowę,
// dyktowanie i odsłuch (§5.3), a UI i głos korzystają z jednego silnika akcji (§8).

/// Wynik zapisu z formularza (`AppDependencies.submit`).
public enum SubmitOutcome<T> {
    case saved(T)
    case failed(String)

    public var value: T? {
        if case .saved(let value) = self { return value }
        return nil
    }

    public var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Pola spotkania rozpoznane z wypowiedzi (F14). Wszystkie opcjonalne: brak pola
/// znaczy „zostaw domyślną wartość formularza”, nie „zgaduj”.
public struct EventDraftSeed: Equatable, Sendable {
    public var title: String?
    public var day: LocalDate?
    public var time: TimeOfDay?

    public init(title: String? = nil, day: LocalDate? = nil, time: TimeOfDay? = nil) {
        self.title = title
        self.day = day
        self.time = time
    }
}

@MainActor
public final class AppDependencies: ObservableObject {

    // MARK: Trwałe zależności

    public let configuration: AppConfiguration
    public let clock: Clock
    /// Kontrakt danych, nie klasa: patrz `EmmaRepository` (F05).
    public let repository: any EmmaRepository
    public let voice: VoiceSessionCoordinator
    /// Nazwa zestawu danych demo wybrana na starcie (`--fixture`).
    public let fixtureName: String?
    /// Zestaw danych demo faktycznie używany (rozstrzygnięty z `fixtureName`).
    public let fixture: DemoFixture
    /// Zgłoszenie, gdy przekazano nieznaną nazwę zestawu. Pokazywane właścicielowi,
    /// żeby literówka w schemacie nie wyglądała jak „demo działa inaczej”.
    @Published public var fixtureNotice: String?
    /// Scenariusz mocka głosowego wynikający z zestawu danych.
    public var voiceScenarioName: String { fixture.voiceScenarioName }
    /// Dzień referencyjny prezentacji: piątek 11 września 2026.
    public let referenceDay: LocalDate
    /// Jeden kontroler sesji audio dla rozmowy, dyktowania i odsłuchu (§5.3).
    public let audioSession = AudioSessionController()
    /// Token dostępu do backendu. Dostarcza go `AuthStore` (M1: logowanie mobilne);
    /// w Demo pozostaje `nil`, bo żaden request nie ma prawa wyjść z telefonu.
    /// Klucza dostawcy tu nie będzie nigdy.
    ///
    /// Typ jest `@MainActor`, bo `AuthStore` żyje na głównym aktorze: odczyt tokenu
    /// z wątku tła byłby wyścigiem, a nie skrótem.
    private let accessTokenProvider: (@MainActor @Sendable () -> String?)?

    /// Token dla warstw API z możliwością odnowienia (FIX C). W odróżnieniu od
    /// synchronicznego `accessTokenProvider` (migawka dla transportu głosu) ten
    /// dostawca czeka na aktora sesji i **odnawia access token z wyprzedzeniem**,
    /// zamiast wysyłać wygasły. Zwraca `nil`, gdy sesji naprawdę nie ma.
    private let sessionTokenProvider: (@MainActor @Sendable () async -> String?)?
    /// Wymuszone odnowienie po 401 z zasobu danych. Zwraca nowy token albo `nil`;
    /// `nil` po nieudanym odnowieniu oznacza koniec sesji (401), a nie brak sieci.
    private let sessionTokenRefresher: (@MainActor @Sendable () async -> String?)?
    /// Token dla rozmowy głosowej: te same źródła co dla danych, pytane przy
    /// każdym użyciu — rozmowa trwa dłużej niż token dostępu.
    private let voiceTokens: VoiceAccessTokenSource

    /// Token, którym warstwy zależne od API podpisują żądania. To wartość
    /// z ostatniego logowania/odnowienia — odświeżaniem zajmuje się `AuthStore`.
    public var accessToken: String? { accessTokenProvider?() }

    // MARK: Stan wspólny

    @Published public private(set) var currentUser: User
    @Published public var tab: AppTab = .today
    /// Lustro stanu głosu dla widoków powłoki (etap 4 audytu, F06).
    ///
    /// Źródłem prawdy pozostaje `voice` — jeden koordynator i jedna sesja (§5.3).
    /// To tylko publikacja jego stanu, żeby pasek zakładek i arkusze mogły
    /// pokazać mini-panel bez tworzenia drugiego obserwatora w każdym widoku.
    @Published public private(set) var voiceState = VoiceUIState()
    @Published public var navigation: [AppTab: TabNavigation] = [:]
    @Published public var sheet: AppSheet?
    @Published public var toast: String?
    /// Akcja dołączona do bieżącego komunikatu (np. „Cofnij” po obsłużeniu leada).
    @Published public private(set) var toastAction: ToastAction?
    /// Liczba nieprzeczytanych wiadomości pokazywana na zakładce „Rozmowy”.
    @Published public var unreadTotal: Int = 0
    /// Liczba zgłoszeń czekających na ruch kancelarii (etap `new`) — plakietka
    /// na zakładce „Klienci”. Nowy lead jest widoczny z każdego ekranu.
    @Published public var leadsNeedingAction: Int = 0
    /// Filtr listy leadów, który ma się otworzyć po przejściu z innego ekranu
    /// (np. „Wszystkie” przy leadach na „Dzisiaj” otwiera „Do obsługi”).
    @Published var pendingLeadFilter: LeadListFilter?

    // MARK: Pamięć ekranów zakładek
    //
    // Zakładki są przełączane wymianą widoku, więc `@StateObject` ekranu ginął
    // przy każdym przejściu: lista mrugała „Wczytuję…”, a przewinięcie
    // przepadało. Magazyny zakładek żyją tutaj — powrót na zakładkę pokazuje
    // od razu ostatni stan i odświeża go w tle.
    let todayStore: TodayStore
    let clientsStore: ClientsStore
    let calendarStore: CalendarStore
    /// Przypomnienia o terminach (lokalne powiadomienia telefonu).
    let reminders: EventReminderScheduler

    /// Kontekst Emmy wybrany na innym ekranie (odpowiada `emmaContext` z referencji).
    @Published public var emmaContext: ClientID?
    /// Skrót do wykonania po wejściu na ekran Emmy (`assistantExample(action)`).
    @Published public var pendingEmmaAction: EmmaQuickAction?
    /// Pola spotkania rozpoznane głosem (F14). Formularz terminu zużywa je przy
    /// otwarciu, żeby „dodaj spotkanie … o 11” nie gubiło godziny i tytułu.
    @Published public var pendingEventDraft: EventDraftSeed?
    /// Tryb listy klientów: leady, kartoteka klientów albo sprawy (`clientMode`).
    @Published public var clientMode: ClientListMode = .leads
    /// Ostatnio otwierane karty osób — pasek „Ostatnio otwierani” w kartotece.
    /// Przeżywa ponowne uruchomienie (`UserDefaults`), bo po to jest: wrócić
    /// jednym dotknięciem do klienta, nad którym pracowało się wczoraj.
    @Published public private(set) var recentClients = RecentClients(
        ids: (UserDefaults.standard.stringArray(forKey: AppDependencies.recentClientsKey) ?? []).map(ClientID.init)
    )
    static let recentClientsKey = "emma.recentClientIDs"
    /// Licznik zmian danych. Każdy ekran obserwuje go w `.task(id:)` i po
    /// operacji zapisu wczytuje dane ponownie — jedno miejsce zamiast wielu
    /// kanałów powiadamiania między ekranami.
    @Published public private(set) var dataVersion: Int = 0
    /// Żądanie rozpoczęcia rozmowy głosowej po wejściu na ekran Emmy
    /// (odpowiada `openEmma(…, start: true)` z referencji).
    @Published public var pendingVoiceStart = false

    public enum ClientListMode: String, Hashable, CaseIterable, Sendable {
        case leads = "Leady"
        /// Kartoteka klientów kancelarii — review 27.09.2026: wcześniej osoba
        /// z etapu „Klient” była osiągalna wyłącznie przez wyszukiwanie.
        case clients = "Klienci"
        case cases = "Sprawy"
    }

    /// Akcja komunikatu. Wykonuje się na głównym aktorze, jak cały stan powłoki.
    public struct ToastAction {
        public let title: String
        public let handler: @MainActor () -> Void

        public init(title: String, handler: @escaping @MainActor () -> Void) {
            self.title = title
            self.handler = handler
        }
    }

    private var toastTask: Task<Void, Never>?
    /// Wykonawca narzędzi `app_*` dla Gemini Live. Podpina go ekran Emmy
    /// (`AssistantStore.attach`); słaba referencja, żeby nie trzymać ekranu.
    public weak var appToolHandler: (any VoiceAppToolHandling)?

    // MARK: Tworzenie

    public init(
        configuration: AppConfiguration = .current,
        clock: Clock? = nil,
        repository: (any EmmaRepository)? = nil,
        fixtureName: String? = nil,
        accessTokenProvider: (@MainActor @Sendable () -> String?)? = nil,
        sessionTokenProvider: (@MainActor @Sendable () async -> String?)? = nil,
        sessionTokenRefresher: (@MainActor @Sendable () async -> String?)? = nil,
        currentUserProvider: (@MainActor @Sendable () -> User?)? = nil
    ) {
        self.configuration = configuration
        self.fixtureName = fixtureName
        self.todayStore = TodayStore()
        self.clientsStore = ClientsStore()
        self.calendarStore = CalendarStore()
        self.reminders = EventReminderScheduler(
            isEnabled: !configuration.usesMockServices
                && !ProcessInfo.processInfo.arguments.contains("--skip-auth")
        )
        self.accessTokenProvider = accessTokenProvider
        self.sessionTokenProvider = sessionTokenProvider
        self.sessionTokenRefresher = sessionTokenRefresher

        // Zestaw danych rozstrzygamy raz, na starcie: dzień referencyjny, zalogowany
        // prawnik i scenariusz głosu pochodzą z jednego, nazwanego źródła.
        let resolution = DemoFixtureCatalog.resolve(fixtureName)
        self.fixture = resolution.fixture

        // FIX D: zegar demo (stały dzień fixture, np. 2026-09-11) obowiązuje
        // **wyłącznie** w Demo. W Staging/Production „dziś” musi pochodzić
        // z prawdziwego zegara, bo inaczej `from`/`through` i `due_on_or_before`
        // pytają backend o dzień z fixture, a ekran „Dziś” pokazuje nie ten dzień.
        let resolvedClock: Clock
        if let clock {
            resolvedClock = clock
        } else if configuration.usesMockServices {
            resolvedClock = DemoClock(
                referenceDate: resolution.fixture.referenceDay,
                hour: resolution.fixture.referenceHour,
                minute: resolution.fixture.referenceMinute
            )
        } else {
            resolvedClock = SystemClock()
        }
        self.clock = resolvedClock
        self.referenceDay = AppDependencies.localDate(from: resolvedClock.now())

        let dataset = resolution.fixture.usesLongNames
            ? DemoFixtures.datasetWithLongNames()
            : DemoFixtures.dataset()

        // FIX C: warstwy API pytają o token asynchronicznie (świeży albo odnowiony),
        // a po 401 mogą raz wymusić odnowienie i ponowić żądanie. Gdy aplikacja nie
        // wstrzyknęła dostawcy sesji (podglądy, testy), zostaje dawna migawka.
        let apiTokenProvider: @Sendable () async -> String? = {
            if let sessionTokenProvider { return await sessionTokenProvider() }
            return await accessTokenProvider?()
        }
        let apiTokenRefresher: (@Sendable () async -> String?)?
        if let sessionTokenRefresher {
            apiTokenRefresher = { await sessionTokenRefresher() }
        } else {
            apiTokenRefresher = nil
        }
        self.voiceTokens = VoiceAccessTokenSource(current: apiTokenProvider, refresh: apiTokenRefresher)

        if let repository {
            self.repository = repository
        } else if !configuration.usesMockServices, let baseURL = configuration.apiBaseURL {
            // Gdy backend jest skonfigurowany, dane muszą pochodzić z sieci.
            // Zostawienie tu `MockRepository` znaczyłoby, że przykładowe sprawy
            // są pokazywane jako prawdziwe. Demo i brak adresu nadal używają mocka.
            self.repository = BackendRepository(
                baseURL: baseURL,
                accessTokenProvider: apiTokenProvider,
                tokenRefresher: apiTokenRefresher,
                // Użytkownik pochodzi z sesji mobilnej (odtworzonej albo świeżo
                // zalogowanej). Bez niej repozytorium zgłasza brak sesji zamiast
                // podstawiać konto demo.
                currentUser: { await currentUserProvider?() }
            )
        } else {
            self.repository = MockRepository(
                dataset: dataset,
                clock: resolvedClock,
                artificialLatency: 0
            )
        }

        // Sesja głosu to osobny, wąski kontrakt. Poza Demo rozmawia z prawdziwym
        // backendem; w Demo i przy wstrzykniętym repozytorium (testy/podglądy)
        // zostaje to samo repozytorium, którego używa reszta aplikacji.
        let voiceRepository: VoiceSessionRepository
        if let repository {
            voiceRepository = repository
        } else if !configuration.usesMockServices, let baseURL = configuration.apiBaseURL {
            voiceRepository = BackendVoiceSessionRepository(
                baseURL: baseURL,
                accessTokenProvider: apiTokenProvider,
                tokenRefresher: apiTokenRefresher
            )
        } else {
            voiceRepository = self.repository
        }

        // Bieżący użytkownik: najpierw sesja mobilna, a dopiero gdy jej nie ma —
        // konto demo. W Demo provider jest `nil`, więc zostaje konto przykładowe.
        self.currentUser = currentUserProvider?() ?? dataset.user
        self.fixtureNotice = resolution.notice

        // Zgoda na mikrofon pytana przed startem produkcyjnej rozmowy. W Demo
        // mikrofonu nie ma w ogóle (mock bez audio), więc port zostaje pusty.
        #if canImport(UIKit)
        let microphonePermission: (any MicrophonePermissionProviding)? = configuration.usesMockServices
            ? nil
            : SystemMicrophonePermission()
        #else
        let microphonePermission: (any MicrophonePermissionProviding)? = nil
        #endif

        self.voice = VoiceSessionCoordinator(
            sessionRepository: voiceRepository,
            actionRepository: self.repository,
            clock: resolvedClock,
            // 2 minuty bez mowy kończą rozmowę: otwarty mikrofon wysyła ciszę,
            // a Live API nalicza ją jak mowę. Wznowienie to jedno dotknięcie.
            idleTimeout: 2 * 60,
            // Uzgodnienie z backendem: przejęcie sesji przez inne urządzenie kończy
            // u nas prawo zapisu głosem (plan §5.6, linia 342). Zapytanie jest tanie
            // i idzie tym samym repozytorium głosu, które otwiera sesję — nie tym
            // od danych kancelarii, bo to ono zna trasę statusu.
            sessionStatus: { [voiceRepository] sessionID in
                try? await voiceRepository.fetchStatus(sessionID: sessionID)
            },
            // Bez zgody na mikrofon nie ma rozmowy: SDK dostawcy połączyłby ją
            // bez wejścia audio i użytkownik mówiłby w pustkę (szczegóły portu
            // w `MicrophonePermission`). W Demo port jest pusty.
            microphonePermission: microphonePermission
        )

        self.navigation = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, TabNavigation()) })
        self.voice.onDictationFailure = { [weak self] failure in
            self?.showToast(failure.safeMessage)
        }
        wireAudioSessionEvents()
        observeSessionEnd()
        refreshUnreadTotal()
    }

    /// Uproszczony start dla podglądów i testów interfejsu.
    public static func demo(fixtureName: String? = nil) -> AppDependencies {
        AppDependencies(
            configuration: AppConfiguration(environment: .demo, apiBaseURL: nil, defaultLocale: "pl-PL"),
            fixtureName: fixtureName
        )
    }

    // MARK: Tworzenie usług głosowych
    //
    // Aplikacja nie tworzy mocków ani adapterów samodzielnie: wszystkie decyzje
    // „mock czy dostawca” przechodzą przez `VoiceServicesFactory`. Wcześniej fabryka
    // istniała, ale nikt jej nie wołał — każdy ekran brał mocka wprost, więc build
    // bez Demo nadal mówiłby mockiem. To była nieosiągalna ścieżka dostawcy.

    /// Transport dla nowej sesji rozmowy.
    public func makeVoiceTransport(configuration: VoiceSessionConfiguration) -> VoiceTransport {
        VoiceServicesFactory.makeTransport(
            configuration: self.configuration,
            fixtureName: fixtureName,
            accessToken: accessToken,
            tokens: voiceTokens,
            appTools: { [weak self] in self?.appToolHandler },
            // Ten sam identyfikator instalacji co w logowaniu (FIX A).
            installationID: InstallationIdentity.current(),
            mockScenarioName: voiceScenarioName,
            // Sesja audio dla rozmowy (SDK jej nie ustawia) — bez tego mikrofon
            // po odsłuchu/dyktowaniu zostaje w kategorii bez wejścia.
            audioSession: audioSession
        )
    }

    /// Dyktowanie: w Demo scenariuszowe, na urządzeniu rozpoznawanie mowy systemu.
    public func makeDictationService() -> DictationService {
        VoiceServicesFactory.makeDictationService(
            configuration: configuration,
            audioSession: audioSession
        )
    }

    /// Odsłuch. Poza Demo mock jest nadal mockiem — patrz `VoiceServicesFactory`.
    public func makePlaybackService() -> SpeechPlaybackService {
        VoiceServicesFactory.makePlaybackService(
            configuration: configuration,
            audioSession: audioSession
        )
    }

    /// Zakończenie sesji przez limit czasu musi być widoczne dla użytkownika:
    /// inaczej rozmowa „sama się rozłącza”, co wygląda jak awaria.
    private func observeSessionEnd() {
        _ = voice.addObserver { [weak self] state in
            guard let self else { return }
            // Jedno lustro stanu dla powłoki: pasek zakładek i arkusze czytają
            // `voiceState`, a nie subskrybują koordynatora po swojemu (F06).
            self.voiceState = state
            // W produkcyjnej rozmowie sesję audio trzyma WebRTC dostawcy. Odsłuch
            // i dyktowanie muszą o tym wiedzieć, żeby nie przełączać kategorii ani
            // nie dezaktywować sesji w trakcie rozmowy (to zabiłoby mikrofon Emmy).
            self.audioSession.setProviderOwnsAudioSession(
                !self.configuration.usesMockServices
                    && (state.connection == .connected || state.connection == .connecting)
            )
            guard state.connection == .ended else { return }
            guard let reason = self.voice.lastEndReason else { return }
            guard reason == .idleTimeout || reason == .sessionExpired else { return }
            self.showToast(reason.displayName)
        }
    }

    // MARK: Zdarzenia systemu audio

    /// Zmiana trasy i przerwania z systemu trafiają do koordynatora, bo to on
    /// decyduje o odsłuchu. Politykę trasy ma `AudioRoutePolicy` — tutaj tylko
    /// przekazujemy zdarzenie.
    private func wireAudioSessionEvents() {
        // Zdarzenia systemowe przychodzą z wątków systemowych, a stan aplikacji żyje
        // na głównym aktorze — izolacja jest podana wprost, a nie domyślna.
        audioSession.onRouteChange = { [weak self] route in
            Task { @MainActor in
                await self?.voice.handleAudioRouteChange(to: route)
            }
        }
        audioSession.onInterruption = { [weak self] reason in
            Task { @MainActor in
                await self?.voice.handleSystemAudioInterruption(reason)
            }
        }
    }

    // MARK: Nawigacja

    public func binding(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(
            get: { self.navigation[tab]?.path ?? [] },
            set: { self.navigation[tab] = TabNavigation(path: $0) }
        )
    }

    /// Wypchnięcie ekranu w bieżącej zakładce.
    public func open(_ route: AppRoute) {
        var state = navigation[tab] ?? TabNavigation()
        state.push(route)
        navigation[tab] = state
    }

    /// Powrót o jeden ekran w bieżącej zakładce.
    public func back() {
        var state = navigation[tab] ?? TabNavigation()
        state.pop()
        navigation[tab] = state
    }

    /// Przejście do zakładki, opcjonalnie z ustawieniem jej stosu.
    public func go(to tab: AppTab, route: AppRoute? = nil, resetStack: Bool = false) {
        var state = navigation[tab] ?? TabNavigation()
        if let route {
            state.reset(to: route)
        } else if resetStack {
            state.popToRoot()
        }
        navigation[tab] = state
        self.tab = tab
    }

    public func openPerson(_ clientID: ClientID) {
        recentClients.record(clientID)
        UserDefaults.standard.set(recentClients.ids.map(\.rawValue), forKey: Self.recentClientsKey)
        appendingToClients(.person(clientID))
    }

    public func openCase(_ caseID: CaseID) {
        appendingToClients(.legalCase(caseID))
    }

    /// Lista leadów z wybranym filtrem — wejście z ekranu „Dzisiaj”.
    func openLeads(filter: LeadListFilter) {
        clientMode = .leads
        pendingLeadFilter = filter
        go(to: .clients, resetStack: true)
    }

    /// Kalendarz otwarty na wybranym dniu (np. z paska tygodnia na „Dzisiaj”).
    func openCalendar(on day: LocalDate) {
        go(to: .calendar, resetStack: true)
        Task { await calendarStore.select(day, dependencies: self) }
    }

    public func openTasks() {
        var state = navigation[.today] ?? TabNavigation()
        state.reset(to: .tasks)
        navigation[.today] = state
        tab = .today
    }

    public func openThread(_ threadID: ThreadID) {
        var state = navigation[.messages] ?? TabNavigation()
        state.reset(to: .thread(threadID))
        navigation[.messages] = state
        tab = .messages
    }

    /// Karta klienta i sprawa są wypychane na stosie zakładki „Klienci”
    /// dokładnie jak w referencji (`nav()` mapuje `person`/`case` na `clients`).
    private func appendingToClients(_ route: AppRoute) {
        var state = navigation[.clients] ?? TabNavigation()
        state.push(route)
        navigation[.clients] = state
        tab = .clients
    }

    // MARK: Arkusze i komunikaty

    public func present(_ sheet: AppSheet) {
        self.sheet = sheet
    }

    public func dismissSheet() {
        sheet = nil
    }

    // MARK: Sterowanie sesją z dowolnego miejsca (F06)

    /// Wyciszenie albo włączenie mikrofonu z mini-panelu. Wyciszony mikrofon
    /// **nie** kończy rozmowy i nie zmienia stanu połączenia (§5.5).
    public func toggleVoiceMicrophone() async {
        await voice.setMicrophoneMuted(voiceState.isCapturingMicrophone)
    }

    /// Zakończenie rozmowy z dowolnego ekranu. Jedna ścieżka dla docku Emmy
    /// i mini-panelu, żeby zakończenie nie miało dwóch implementacji (§5.3).
    public func endVoiceSession() async {
        await voice.end(reason: .userRequested, preserveDraft: true, revokedCapability: false)
    }

    /// Krótkie potwierdzenie operacji. Znika po 3,8 s — jak w referencji.
    public func showToast(_ message: String) {
        showToast(message, action: nil)
    }

    /// Komunikat z akcją (np. „Cofnij”). Zostaje dłużej, żeby dało się zdążyć.
    public func showToast(_ message: String, action: ToastAction?) {
        toast = message
        toastAction = action
        toastTask?.cancel()
        let duration: UInt64 = action == nil ? 3_800_000_000 : 6_000_000_000
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: duration)
            guard !Task.isCancelled else { return }
            self?.toast = nil
            self?.toastAction = nil
        }
    }

    /// Wykonanie akcji komunikatu i jego zamknięcie — jedno dotknięcie.
    public func runToastAction() {
        guard let action = toastAction else { return }
        toastTask?.cancel()
        toast = nil
        toastAction = nil
        action.handler()
    }

    // MARK: Emma

    /// Wejście do Emmy w kontekście klienta, z opcjonalnym skrótem.
    public func openEmma(clientID: ClientID?, action: EmmaQuickAction? = nil, startVoice: Bool = false) {
        emmaContext = clientID
        pendingEmmaAction = action
        pendingVoiceStart = startVoice
        go(to: .emma)
    }

    /// Skróty z ekranów, które wymagają najpierw wyboru kontekstu (np. odpowiedź).
    public func requestEmmaAction(_ action: EmmaQuickAction) {
        if emmaContext == nil && action != .brief {
            present(.emmaContextSelection(action: action))
            return
        }
        openEmma(clientID: emmaContext, action: action)
    }

    // MARK: Dane i operacje

    /// Wspólna obsługa operacji zapisu: pokazuje komunikat błędu zamiast go ukrywać.
    @discardableResult
    public func perform<T>(_ operation: () async throws -> T) async -> T? {
        do {
            let result = try await operation()
            dataChanged()
            return result
        } catch {
            showToast(ScreenLoad.message(for: error, fallback: "Nie udało się wykonać operacji."))
            return nil
        }
    }

    /// Zapis z arkusza: błąd **wraca do arkusza**, a nie do komunikatu pod nim.
    ///
    /// Review 24.09.2026 („zapisywanie notatek nie działa”, „dodawanie terminów
    /// nie działa”): `perform` pokazywał błąd w komunikacie powłoki, a ten rysuje
    /// się **pod** arkuszem. Odrzucony zapis wyglądał więc jak przycisk, który nic
    /// nie robi. Formularz dostaje teraz komunikat i pokazuje go przy przycisku.
    public func submit<T>(
        fallback: String = "Nie udało się zapisać.",
        _ operation: () async throws -> T
    ) async -> SubmitOutcome<T> {
        do {
            let result = try await operation()
            dataChanged()
            return .saved(result)
        } catch {
            EmmaHaptics.error()
            return .failed(ScreenLoad.message(for: error, fallback: fallback))
        }
    }

    /// Wywoływane po każdej udanej operacji zapisu.
    public func dataChanged() {
        dataVersion &+= 1
        refreshUnreadTotal()
        refreshLeadCount()
        reminders.scheduleRefresh(self)
    }

    /// Plakietka „Klienci”: zgłoszenia na etapie `new` (nowe i oczekujące).
    /// Błąd odczytu zostawia poprzednią liczbę — plakietka nie mruga zerem.
    public func refreshLeadCount() {
        Task { [weak self] in
            guard let self else { return }
            guard let leads = try? await self.repository.clients(matching: "", stage: .new) else { return }
            self.leadsNeedingAction = leads.count
        }
    }

    /// Chwila „teraz” według zegara aplikacji (w Demo — stały dzień referencyjny).
    public var now: Date { clock.now() }

    public func refreshUnreadTotal() {
        let userID = currentUser.id
        Task { [weak self] in
            guard let self else { return }
            let total = (try? await self.repository.unreadTotal(userID: userID)) ?? 0
            self.unreadTotal = total
        }
    }

    /// Przywrócenie danych przykładowych (odpowiada `resetDemo()` z referencji).
    public func resetDemoData() async {
        await voice.handleUserLoggedOut()
        // Reset danych przykładowych jest zdolnością demo, nie częścią kontraktu
        // produkcyjnego — pytamy o nią wprost (F05).
        await (repository as? any DemoFixtureRepository)?.reset()
        let dataset = DemoFixtures.dataset()
        currentUser = dataset.user
        navigation = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, TabNavigation()) })
        tab = .today
        sheet = nil
        emmaContext = nil
        pendingEmmaAction = nil
        pendingVoiceStart = false
        clientMode = .leads
        pendingLeadFilter = nil
        recentClients = RecentClients()
        UserDefaults.standard.removeObject(forKey: Self.recentClientsKey)
        refreshUnreadTotal()
        dataChanged()
        showToast("Przywrócono dane przykładowe.")
    }

    // MARK: Użytkownik z sesji mobilnej

    /// Zamiana użytkownika z odpowiedzi logowania (`MobileAuthUser`) na model
    /// aplikacji. Robimy to w jednym miejscu, żeby powłoka i repozytorium nie
    /// mogły się rozjechać w interpretacji pól.
    public static func mapRemoteUser(_ remote: MobileAuthUser) -> User {
        User(
            id: UserID(remote.id),
            displayName: remote.displayName,
            initials: remote.initials,
            // Kontrakt dopuszcza kody, których `LanguageCode` nie zna; wtedy
            // zostaje język kancelarii (interfejs) albo dotychczasowa reguła
            // języka rozmowy (rosyjski), zamiast pustego kodu.
            interfaceLanguage: LanguageCode(lenient: remote.interfaceLanguage) ?? .pl,
            assistantLanguage: LanguageCode(lenient: remote.assistantLanguage) ?? .ru
        )
    }

    /// Przyjęcie użytkownika z udanego logowania (albo z odtworzonej sesji).
    /// `nil` nie kasuje konta: po wylogowaniu powłoka i tak wraca do logowania.
    public func adoptRemoteUser(_ remote: MobileAuthUser?) {
        guard let remote else { return }
        currentUser = Self.mapRemoteUser(remote)
    }

    // MARK: Formatowanie

    /// Dziennik dat w stałej strefie kancelarii. Ekrany nie tworzą własnych
    /// formaterów, aby „Dzisiaj” znaczyło to samo w całej aplikacji.
    public var dateText: DateTextFormatter {
        DateTextFormatter(today: today)
    }

    /// Dzień bieżący według zegara aplikacji i strefy kancelarii.
    public var today: LocalDate {
        AppDependencies.localDate(from: clock.now())
    }

    /// Zamiana znacznika czasu na datę lokalną w strefie kancelarii.
    /// Świadomie nie używamy `Calendar.current`: prezentacja ma być deterministyczna
    /// niezależnie od ustawień telefonu (§2.2).
    public static func localDate(
        from date: Date,
        timeZoneIdentifier: String = EmmaTime.referenceTimeZone
    ) -> LocalDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return LocalDate(
            year: components.year ?? 2026,
            month: components.month ?? 1,
            day: components.day ?? 1
        )
    }
}
