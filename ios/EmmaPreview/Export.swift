// Eksport danych demo do podglądu na Linuksie.
//
// Po co: na Linuksie nie ma SwiftUI, więc nie da się zbudować aplikacji ani zrobić
// zrzutu ekranu. Można natomiast uruchomić **prawdziwy kod danych aplikacji** —
// `MockRepository`, `DemoFixtures`, zegar demo i logikę domenową — i wypisać to,
// co widzą ekrany. Podgląd HTML (`scripts/build-preview.py`) składa z tego obraz
// w stylach referencji.
//
// Czego to NIE jest:
//   * to nie jest render SwiftUI — układ, typografia i gesty są odtworzone w HTML,
//   * to nie jest dowód kompilacji widoków (te nadal wymagają macOS/Xcode),
//   * to nie jest zrzut ekranu iPhone'a.
//
// Czytamy dane wyłącznie przez publiczne API repozytorium, tą samą drogą co widoki.
// Wyjście trafia na stdout jako JSON (klucze sortowane), żeby wynik był powtarzalny.

import Emma
import Foundation

@main
struct EmmaPreviewExport {

    struct Payload: Encodable {
        var generatedFrom = "MockRepository + DemoFixtures (ten sam kod co aplikacja)"
        var referenceDay: LocalDate
        var referenceTime: String
        var currentUser: User
        var fixtureName: String
        var fixtureSummary: String
        var voiceScenario: String
        var clients: [Client]
        var cases: [LegalCase]
        var tasks: [TaskItem]
        var events: [ScheduledEvent]
        var notes: [CaseNote]
        var activity: [ActivityEvent]
        var threads: [ConversationThread]
        var messagesByThread: [String: [Message]]
        var unreadByThread: [String: Int]
        var unreadTotal: Int
        var screenStates: [String]
        /// Sformatowane napisy z **logiki aplikacji** (`DateTextFormatter`, `EmmaPlural`,
        /// `OwnerName`), a nie z formatowania w Pythonie. Podgląd pokazuje więc dokładnie
        /// te napisy, które zobaczy użytkownik.
        var labels: [String: String]
        /// Podsumowanie „Dzisiaj” policzone tymi samymi filtrami co `TodayStore`
        /// (kopia tej jednej selekcji jest tu świadoma — patrz nota w nagłówku pliku).
        var todaySummary: TodaySummary
    }

    struct TodaySummary: Encodable {
        var greetingName: String
        var userInitials: String
        var briefing: String
        var leadCount: Int
        var activeCaseCount: Int
        var tasksDueToday: [TaskItem]
        var tasksDueTodayLabel: String
        var nextConsultation: ScheduledEvent?
        var nextConsultationLabel: String
        var unreadLabel: String
    }

    static func main() async throws {
        let fixture = DemoFixtureCatalog.defaultFixture
        var dataset = DemoFixtures.dataset()
        dataset.currentUserID = fixture.currentUserID

        let clock = DemoClock(
            referenceDate: fixture.referenceDay,
            hour: fixture.referenceHour,
            minute: fixture.referenceMinute
        )
        let repository = MockRepository(dataset: dataset, clock: clock, artificialLatency: 0)

        let user = try await repository.currentUser()
        let clients = try await repository.clients(matching: "", stage: nil)
        let cases = try await repository.cases(status: nil)
        let tasks = try await repository.tasks(filter: TaskFilter(scope: .all))
        // Zakres obejmuje cały tydzień demo — podgląd pokazuje plan, nie tylko jeden dzień.
        let events = try await repository.events(
            in: DateIntervalFilter(from: DemoFixtures.weekStart, through: LocalDate(year: 2026, month: 9, day: 18)),
            ownerID: nil
        )
        let threads = try await repository.threads()

        var notes: [CaseNote] = []
        var activity: [ActivityEvent] = []
        var messagesByThread: [String: [Message]] = [:]
        for legalCase in cases {
            notes += (try? await repository.notes(clientID: legalCase.clientID, caseID: legalCase.id)) ?? []
            activity += (try? await repository.activity(caseID: legalCase.id)) ?? []
        }
        for thread in threads {
            messagesByThread[thread.id.rawValue] = (try? await repository.latestMessages(threadID: thread.id, limit: 50)) ?? []
        }

        let unread = try await repository.unreadCounts(userID: user.id)
        let unreadByThread = Dictionary(uniqueKeysWithValues: unread.map { ($0.key.rawValue, $0.value) })

        let formatter = DateTextFormatter(today: clock.today())
        let openTasksDueToday = try await repository.tasks(
            filter: TaskFilter(scope: .open, dueOnOrBefore: clock.today())
        )
        let todayEvents = try await repository.events(in: .day(clock.today()), ownerID: nil)
        let nextConsultation = todayEvents
            .filter { $0.kind == .consultation && $0.status != .finished && $0.ownerID == user.id }
            .min { $0.time < $1.time }
        let unreadTotal = try await repository.unreadTotal(userID: user.id)

        let payload = Payload(
            referenceDay: clock.today(),
            referenceTime: DateTextFormatter(today: clock.today()).clockTime(clock.now()),
            currentUser: user,
            fixtureName: fixture.name,
            fixtureSummary: fixture.summary,
            voiceScenario: fixture.voiceScenarioName,
            clients: clients,
            cases: cases,
            tasks: tasks,
            events: events,
            notes: notes,
            activity: activity,
            threads: threads,
            messagesByThread: messagesByThread,
            unreadByThread: unreadByThread,
            unreadTotal: unreadTotal,
            // Stany, które podgląd potrafi pokazać poza danymi referencyjnymi.
            screenStates: ["ładowanie", "puste dane", "błąd wczytywania", "offline z kolejką"],
            labels: [
                "kicker": formatter.headline(for: clock.today()),
                "dayLabel": formatter.dayLabel(clock.today()),
                "monthTitle": formatter.monthTitle(for: clock.today()),
                "weekdayShort": formatter.weekdayShort(for: clock.today()),
                "clock": formatter.clockTime(clock.now()),
                "clientCount": EmmaPlural.form(clients.count, "klient", "klientów", "klientów"),
                "caseCount": EmmaPlural.form(cases.count, "sprawa", "sprawy", "spraw"),
                "taskCount": EmmaPlural.form(openTasksDueToday.count, "zadanie", "zadania", "zadań"),
                "owner": OwnerName.of(user.id),
                "unassigned": OwnerName.unassigned,
                "eventTimes": events.map { formatter.timeAndDuration($0.time, minutes: $0.durationMinutes) }.joined(separator: " · ")
            ],
            todaySummary: TodaySummary(
                greetingName: user.displayName,
                userInitials: user.initials,
                briefing: EmmaBriefing.briefing(
                    events: todayEvents,
                    tasks: openTasksDueToday,
                    waitingForReply: clients.filter(\.needsReply),
                    clientNames: Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0.displayName) })
                ),
                leadCount: clients.filter { $0.stage != .client }.count,
                activeCaseCount: cases.filter { $0.status != .closed }.count,
                tasksDueToday: openTasksDueToday,
                tasksDueTodayLabel: EmmaPlural.form(openTasksDueToday.count, "zadanie na dziś", "zadania na dziś", "zadań na dziś"),
                nextConsultation: nextConsultation,
                nextConsultationLabel: nextConsultation.map {
                    formatter.timeAndDuration($0.time, minutes: $0.durationMinutes)
                } ?? "Brak zaplanowanej konsultacji",
                unreadLabel: EmmaPlural.form(unreadTotal, "nieprzeczytana", "nieprzeczytane", "nieprzeczytanych")
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        FileHandle.standardOutput.write(try encoder.encode(payload))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
