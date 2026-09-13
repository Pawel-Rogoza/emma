import Foundation
import SwiftUI

// MARK: - Zależności aplikacji
//
// Jedno miejsce, w którym powstają wszystkie obiekty współdzielone:
// repozytorium danych demo, koordynator sesji głosowej, zegar i konfiguracja.
// Ekrany nie tworzą własnych kopii tych obiektów i nie znają implementacji
// dostawców — dzięki temu jeden `VoiceSessionCoordinator` obsługuje rozmowę,
// dyktowanie i odsłuch (§5.3), a UI i głos korzystają z jednego silnika akcji (§8).

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
    public let repository: MockRepository
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
    /// Token dostępu do backendu. Do czasu wdrożenia logowania (etap 07) go nie ma —
    /// to jedyne miejsce, które ma go dostarczyć. Klucza dostawcy tu nie będzie nigdy.
    public var accessToken: String? { nil }

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
    /// Liczba nieprzeczytanych wiadomości pokazywana na zakładce „Rozmowy”.
    @Published public var unreadTotal: Int = 0

    /// Kontekst Emmy wybrany na innym ekranie (odpowiada `emmaContext` z referencji).
    @Published public var emmaContext: ClientID?
    /// Skrót do wykonania po wejściu na ekran Emmy (`assistantExample(action)`).
    @Published public var pendingEmmaAction: EmmaQuickAction?
    /// Pola spotkania rozpoznane głosem (F14). Formularz terminu zużywa je przy
    /// otwarciu, żeby „dodaj spotkanie … o 11” nie gubiło godziny i tytułu.
    @Published public var pendingEventDraft: EventDraftSeed?
    /// Tryb listy klientów: leady albo sprawy (odpowiada `clientMode`).
    @Published public var clientMode: ClientListMode = .leads
    /// Licznik zmian danych. Każdy ekran obserwuje go w `.task(id:)` i po
    /// operacji zapisu wczytuje dane ponownie — jedno miejsce zamiast wielu
    /// kanałów powiadamiania między ekranami.
    @Published public private(set) var dataVersion: Int = 0
    /// Żądanie rozpoczęcia rozmowy głosowej po wejściu na ekran Emmy
    /// (odpowiada `openEmma(…, start: true)` z referencji).
    @Published public var pendingVoiceStart = false

    public enum ClientListMode: String, Hashable, CaseIterable, Sendable {
        case leads = "Leady"
        case cases = "Sprawy"
    }

    private var toastTask: Task<Void, Never>?

    // MARK: Tworzenie

    public init(
        configuration: AppConfiguration = .current,
        clock: Clock? = nil,
        repository: MockRepository? = nil,
        fixtureName: String? = nil
    ) {
        self.configuration = configuration
        self.fixtureName = fixtureName

        // Zestaw danych rozstrzygamy raz, na starcie: dzień referencyjny, zalogowany
        // prawnik i scenariusz głosu pochodzą z jednego, nazwanego źródła.
        let resolution = DemoFixtureCatalog.resolve(fixtureName)
        self.fixture = resolution.fixture

        let resolvedClock: Clock = clock ?? DemoClock(
            referenceDate: resolution.fixture.referenceDay,
            hour: resolution.fixture.referenceHour,
            minute: resolution.fixture.referenceMinute
        )
        self.clock = resolvedClock
        self.referenceDay = AppDependencies.localDate(from: resolvedClock.now())

        let dataset = DemoFixtures.dataset()
        self.repository = repository ?? MockRepository(
            dataset: dataset,
            clock: resolvedClock,
            artificialLatency: 0
        )

        self.currentUser = dataset.user
        self.fixtureNotice = resolution.notice

        self.voice = VoiceSessionCoordinator(
            sessionRepository: self.repository,
            actionRepository: self.repository,
            clock: resolvedClock,
            // Uzgodnienie z backendem: przejęcie sesji przez inne urządzenie kończy
            // u nas prawo zapisu głosem (plan §5.6, linia 342). Zapytanie jest tanie
            // i idzie tym samym repozytorium, co reszta aplikacji.
            sessionStatus: { [repository = self.repository] sessionID in
                try? await repository.fetchStatus(sessionID: sessionID)
            }
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
            mockScenarioName: voiceScenarioName
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
        VoiceServicesFactory.makePlaybackService()
    }

    /// Zakończenie sesji przez limit czasu musi być widoczne dla użytkownika:
    /// inaczej rozmowa „sama się rozłącza”, co wygląda jak awaria.
    private func observeSessionEnd() {
        _ = voice.addObserver { [weak self] state in
            guard let self else { return }
            // Jedno lustro stanu dla powłoki: pasek zakładek i arkusze czytają
            // `voiceState`, a nie subskrybują koordynatora po swojemu (F06).
            self.voiceState = state
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
        appendingToClients(.person(clientID))
    }

    public func openCase(_ caseID: CaseID) {
        appendingToClients(.legalCase(caseID))
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
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_800_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
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

    /// Wywoływane po każdej udanej operacji zapisu.
    public func dataChanged() {
        dataVersion &+= 1
        refreshUnreadTotal()
    }

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
        await repository.reset()
        let dataset = DemoFixtures.dataset()
        currentUser = dataset.user
        navigation = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, TabNavigation()) })
        tab = .today
        sheet = nil
        emmaContext = nil
        pendingEmmaAction = nil
        pendingVoiceStart = false
        clientMode = .leads
        refreshUnreadTotal()
        dataChanged()
        showToast("Przywrócono dane przykładowe.")
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
