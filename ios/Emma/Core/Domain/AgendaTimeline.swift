import Foundation

// MARK: - Terminy w kontekście dnia
//
// Ekran „Dzisiaj” musi odróżnić termin, który już minął, od tego, który dopiero
// będzie — bez tego lista wygląda płasko i nie wiadomo, na co patrzeć. Reguła
// mieszka w rdzeniu (a nie w widoku), więc jest jednym źródłem prawdy i da się
// ją przetestować bez SwiftUI.

public extension TimeOfDay {

    /// Godzina dnia odczytana z konkretnego momentu, w strefie kancelarii.
    static func at(_ instant: Date, timeZoneIdentifier: String = EmmaTime.referenceTimeZone) -> TimeOfDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        let parts = calendar.dateComponents([.hour, .minute], from: instant)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        // Zakres jest przycięty do doby, więc wymuszenie jest bezpieczne —
        // a `init?(minutes:)` chroni ten warunek w jednym miejscu.
        return TimeOfDay(minutes: min(max(minutes, 0), 24 * 60 - 1)) ?? TimeOfDay(minutes: 0)!
    }
}

public extension ScheduledEvent {

    /// Czy termin już się zakończył względem godziny `now`.
    ///
    /// Zakłada pytanie o termin **z tego samego dnia** — tak używa tego ekran
    /// „Dzisiaj”. Dla innych dni potrzebne byłoby porównanie dat, którego ta
    /// funkcja świadomie nie udaje. Status „Zakończona” rozstrzyga niezależnie
    /// od godziny, bo bywa ustawiony ręcznie.
    func hasPassed(at now: TimeOfDay) -> Bool {
        if status == .finished { return true }
        return time.minutes + max(0, durationMinutes) <= now.minutes
    }

    /// Czy termin trwa dokładnie w tej chwili.
    func isHappening(at now: TimeOfDay) -> Bool {
        guard status != .finished else { return false }
        let end = time.minutes + max(0, durationMinutes)
        return time.minutes <= now.minutes && now.minutes < end
    }
}
