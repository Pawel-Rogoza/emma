import XCTest
@testable import Emma

// MARK: - Zadania w kalendarzu (11.10.2026)
//
// „Zadania i terminy mają być w kalendarzu”: zadanie z datą trafia do dnia
// w siatce i na listę dnia, odhaczenie działa z kalendarza, a „+ Zadanie”
// dziedziczy wybrany dzień.

@MainActor
final class CalendarTasksTests: XCTestCase {

    func testNewTaskAppearsOnItsDayInCalendar() async throws {
        let dependencies = AppDependencies.demo()
        let store = CalendarStore()
        let day = dependencies.today.adding(days: 3)

        let created = try await dependencies.repository.createTask(
            NewTaskDraft(title: "Złożyć wniosek o akta", clientID: nil, caseID: nil, dueDate: day)
        )
        await store.load(dependencies)
        await store.select(day, dependencies: dependencies)

        let model = try XCTUnwrap(store.phase.value)
        XCTAssertTrue(model.dayTasks.contains { $0.id == created.id }, "Zadanie nie trafiło na listę swojego dnia")
        XCTAssertTrue(model.tasksByDay[day]?.contains { $0.id == created.id } == true, "Zadanie nie ma znacznika w siatce")
        XCTAssertFalse(model.tasksByDay[dependencies.today]?.contains { $0.id == created.id } == true)
    }

    func testToggleFromCalendarMarksTaskDone() async throws {
        let dependencies = AppDependencies.demo()
        let store = CalendarStore()
        let created = try await dependencies.repository.createTask(
            NewTaskDraft(title: "Oddzwonić do sądu", clientID: nil, caseID: nil, dueDate: dependencies.today)
        )
        await store.load(dependencies)
        let task = try XCTUnwrap(store.phase.value?.dayTasks.first { $0.id == created.id })

        await store.toggle(task, dependencies: dependencies)

        XCTAssertEqual(store.phase.value?.dayTasks.first { $0.id == created.id }?.isDone, true)
        let saved = try await dependencies.repository.task(id: created.id)
        XCTAssertEqual(saved?.isDone, true, "Odhaczenie w kalendarzu nie zapisało zadania")
        // Wykonane schodzą na koniec listy dnia.
        XCTAssertEqual(store.phase.value?.dayTasks.last?.id, created.id)
    }

    func testNewTaskRouteInheritsSelectedDay() async {
        let dependencies = AppDependencies.demo()
        let store = CalendarStore()
        let day = dependencies.today.adding(days: 9)
        await store.load(dependencies)
        await store.select(day, dependencies: dependencies)

        guard case .taskForm(nil, nil, nil, let initialDay) = store.newTaskRoute else {
            return XCTFail("„+ Zadanie” w kalendarzu nie otwiera formularza zadania")
        }
        XCTAssertEqual(initialDay, day)
    }

    func testDayContentText() {
        XCTAssertEqual(CalendarScreen.dayContentText(events: 2, tasks: 1), "2 terminy · 1 zadanie")
        XCTAssertEqual(CalendarScreen.dayContentText(events: 0, tasks: 5), "5 zadań")
        XCTAssertEqual(CalendarScreen.dayContentText(events: 1, tasks: 0), "1 termin")
        XCTAssertEqual(CalendarScreen.dayContentText(events: 0, tasks: 0), "wolne")
    }
}
