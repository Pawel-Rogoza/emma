import Foundation

// MARK: - Kontrakt danych aplikacji (F05)
//
// Aplikacja ma zależeć od **kontraktu**, nie od implementacji. Do etapu 5
// `AppDependencies.repository` miał konkretny typ `MockRepository`, więc podmiana
// na prawdziwe usługi oznaczała zmianę typu w każdym ekranie. Ten protokół jest
// sumą istniejących, wąskich kontraktów domenowych: ekrany nadal wołają tylko
// swoje `ClientRepository` czy `MessagingRepository`, a zależności przyjmują
// cokolwiek, co spełnia całość.
//
// Reguły:
//   • Demo nadal używa `MockRepository` i jawnie się tak nazywa. Ten kontrakt
//     **nie** usuwa oznaczeń demo — usuwa tylko przywiązanie do klasy.
//   • Adapter produkcyjny ma spełnić `EmmaRepository` (te same reguły wersji,
//     idempotencji i rozdzielenia propozycji od wyniku), a nie obchodzić go
//     własną ścieżką.
//   • Kontrakt nie zawiera metod wyłącznie testowych (`reset`, `dataset`) ani
//     scenariuszy mocka — te zostają w `MockRepository`.

/// Pełny kontrakt danych i akcji, którego wymaga aplikacja.
///
/// Pusty zbiór wymagań jest celowy: składamy istniejące protokoły zamiast
/// powtarzać ich metody, żeby nie powstała druga definicja tego samego API.
public protocol EmmaRepository:
    ClientRepository,
    CaseRepository,
    TaskRepository,
    AgendaRepository,
    NoteRepository,
    ActivityRepository,
    MessagingRepository,
    UserRepository,
    VoiceSessionRepository,
    AssistantActionRepository
{}

/// Zdolność **tylko demo**: przywrócenie danych przykładowych do stanu początkowego.
///
/// Świadomie poza `EmmaRepository`: prawdziwe dane nie mają „resetu do fixture”,
/// a aplikacja nie może wymagać od adaptera produkcyjnego metody, której nie ma.
/// Ekran demo pyta o tę zdolność wprost, a gdy jej nie ma — nie udaje, że
/// przywrócił dane.
public protocol DemoFixtureRepository: Sendable {
    func reset() async
}
