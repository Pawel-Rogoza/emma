import Foundation

// MARK: - Grupowanie zadań w kontekście dnia
//
// Etap 3 audytu UX: lista zadań na „Dzisiaj” i na ekranie „Zadania” ma pokazywać
// **zaległe** oddzielnie od dzisiejszych i późniejszych. Wcześniej wszystko leżało
// w jednej płaskiej liście, więc pilne zadanie z zeszłego tygodnia wyglądało tak
// samo jak zadanie na przyszły miesiąc.
//
// Reguła mieszka w rdzeniu (nie w widoku), żeby oba ekrany dzieliły jedno źródło
// prawdy i żeby dało się ją sprawdzić bez SwiftUI.

public enum TaskGrouping {

    /// Kubełek zadania względem dnia referencyjnego.
    public enum Bucket: String, Sendable, Equatable, CaseIterable {
        case overdue
        case today
        case later

        public var title: String {
            switch self {
            case .overdue: return "Zaległe"
            case .today: return "Na dziś"
            case .later: return "Później"
            }
        }
    }

    public struct Group: Equatable, Sendable {
        public let bucket: Bucket
        public let tasks: [TaskItem]

        public init(bucket: Bucket, tasks: [TaskItem]) {
            self.bucket = bucket
            self.tasks = tasks
        }
    }

    /// Liczby pokazywane przy nagłówku sekcji.
    public struct Summary: Equatable, Sendable {
        public let open: Int
        public let overdue: Int

        public init(open: Int, overdue: Int) {
            self.open = open
            self.overdue = overdue
        }

        public var hasOverdue: Bool { overdue > 0 }
    }

    /// Dzieli zadania na zaległe, dzisiejsze i późniejsze. Puste kubełki znikają,
    /// a kolejność wewnątrz każdego jest zachowana (ekran najpierw sortuje).
    public static func groups(_ tasks: [TaskItem], today: LocalDate) -> [Group] {
        let overdue = tasks.filter { $0.dueDate < today }
        let todayTasks = tasks.filter { $0.dueDate == today }
        let later = tasks.filter { $0.dueDate > today }
        return [
            Group(bucket: .overdue, tasks: overdue),
            Group(bucket: .today, tasks: todayTasks),
            Group(bucket: .later, tasks: later)
        ].filter { !$0.tasks.isEmpty }
    }

    public static func summary(_ tasks: [TaskItem], today: LocalDate) -> Summary {
        Summary(open: tasks.count, overdue: tasks.filter { $0.dueDate < today }.count)
    }
}
