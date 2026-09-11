import Foundation
import SwiftUI

// MARK: - Zależności aplikacji
//
// Jedno miejsce, w którym powstają wszystkie obiekty współdzielone:
// repozytorium danych demo, koordynator sesji głosowej, zegar i konfiguracja.
// Ekrany nie tworzą własnych kopii tych obiektów i nie znają implementacji
// dostawców — dzięki temu jeden `VoiceSessionCoordinator` obsługuje rozmowę,
// dyktowanie i odsłuch (§5.3), a UI i głos korzystają z jednego silnika akcji (§8).

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

    // MARK: Stan wspólny

    @Published public private(set) var currentUser: User
    @Published public var tab: AppTab = .today
    @Published public var navigation: [AppTab: TabNavigation] = [:]
    @Published public var sheet: AppSheet?
    @Published public var toast: String?
    /// Liczba nieprzeczytanych wiadomości pokazywana na zakładce „Rozmowy”.
    @Published public var unreadTotal: Int = 0

    /// Kontekst Emmy wybrany na innym ekranie (odpowiada `emmaContext` z referencji).
    @Published public var emmaContext: ClientID?
    /// Skrót do wykonania po wejściu na ekran Emmy (`assistantExample(action)`).
    @Published public var pendingEmmaAction: EmmaQuickAction?
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

        var dataset = DemoFixtures.dataset()
        dataset.currentUserID = resolution.fixture.currentUserID
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
            clock: resolvedClock
        )

        self.navigation = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, TabNavigation()) })
        self.voice.onDictationFailure = { [weak self] failure in
            self?.showToast(failure.safeMessage)
        }
        refreshUnreadTotal()
    }

    /// Uproszczony start dla podglądów i testów interfejsu.
    public static func demo(fixtureName: String? = nil) -> AppDependencies {
        AppDependencies(
            configuration: AppConfiguration(environment: .demo, apiBaseURL: nil, defaultLocale: "pl-PL"),
            fixtureName: fixtureName
        )
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
        } catch let error as DomainError {
            showToast(error.safeMessage)
            return nil
        } catch {
            showToast("Nie udało się wykonać operacji.")
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

    public func switchUser(to userID: UserID) async {
        guard let user = await perform({ try await self.repository.switchUser(to: userID) }) else { return }
        currentUser = user
        navigation = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, TabNavigation()) })
        sheet = nil
        emmaContext = nil
        pendingEmmaAction = nil
        pendingVoiceStart = false
        await voice.handleAccountSwitched()
        refreshUnreadTotal()
        showToast("Przełączono na \(user.displayName).")
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
