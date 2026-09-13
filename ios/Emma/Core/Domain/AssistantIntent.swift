import Foundation

// MARK: - Intencja jednej wypowiedzi (F14)
//
// Audyt F14: `handleCommand` rozpoznawał słowa przez `contains`, wymagał
// dwukropka dla pełnej treści i obsługiwał „jutro” tylko w wąskiej ścieżce.
// Ten typ zastępuje tamto rozpoznawanie **jedną** regułą domenową: z wypowiedzi
// powstaje intencja z polami (rodzaj, treść, data, godzina, poprawka), a brak
// pola jest pytaniem, nie zgadywaniem.
//
// Parser jest czysty (bez UI i sieci), więc każdą regułę sprawdza test bez
// symulatora. Nazwiska nadal rozstrzyga `PersonResolver` w danych kancelarii —
// tutaj nie ma dopasowywania ludzi po literałach.

public struct AssistantIntent: Equatable, Sendable {

    public enum Kind: String, Equatable, Sendable {
        /// Pytanie odczytowe o dzień/kalendarz. Nie wymaga zgody i nie tworzy akcji.
        case briefing
        /// Podsumowanie sprawy (odczyt).
        case caseSummary
        case reply
        case note
        case task
        case event
        /// Zgoda: „wyślij”, „zatwierdź”, „zapisz”, „tak”.
        case confirm
        case cancel
        /// Poprawka oczekującej propozycji: „zmień na 20 minut”, „nie, na poniedziałek”.
        case correction
        case unknown
    }

    public var kind: Kind
    /// Treść do zapisania/wysłania. `nil`, gdy użytkownik jeszcze jej nie podał.
    public var text: String?
    /// Termin wyliczony ze słów („jutro”, „na poniedziałek”, „12 września”).
    public var dueDate: LocalDate?
    /// Godzina („do 14”, „o 11:30”, „o jedenastej”).
    public var dueTime: TimeOfDay?
    /// Poprawka oczekującej propozycji.
    public var revision: Revision?

    /// Nowa wartość w poprawce. Wszystkie pola są opcjonalne, bo poprawka może
    /// zmieniać jedno z nich — reszta propozycji zostaje.
    public struct Revision: Equatable, Sendable {
        /// Liczba z jednostką („20 minut”, „2 godziny”) — do podmiany w treści.
        public var quantity: Int?
        public var unit: String?
        public var date: LocalDate?
        public var time: TimeOfDay?
        /// Pełna nowa treść podana wprost po dwukropku.
        public var text: String?
        /// Wskazany odbiorca („nie, do Dmytro”). Sama zmiana osoby nie niesie
        /// ani treści, ani terminu, a mimo to jest poprawką.
        public var recipient: String?

        public init(
            quantity: Int? = nil,
            unit: String? = nil,
            date: LocalDate? = nil,
            time: TimeOfDay? = nil,
            text: String? = nil,
            recipient: String? = nil
        ) {
            self.quantity = quantity
            self.unit = unit
            self.date = date
            self.time = time
            self.text = text
            self.recipient = recipient
        }

        public var isEmpty: Bool {
            quantity == nil && date == nil && time == nil && text == nil && recipient == nil
        }
    }

    public init(
        kind: Kind,
        text: String? = nil,
        dueDate: LocalDate? = nil,
        dueTime: TimeOfDay? = nil,
        revision: Revision? = nil
    ) {
        self.kind = kind
        self.text = text
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.revision = revision
    }

    /// Odczyt informacji nie wymaga zatwierdzenia (§5).
    public var isReadOnly: Bool {
        kind == .briefing || kind == .caseSummary || kind == .unknown
    }

    /// Rodzaj akcji silnika dla tej intencji. `nil` dla odczytu i zgody —
    /// one nie tworzą propozycji. Spotkanie ma własną drogę (formularz wydarzenia),
    /// bo akcje zapisu w tym prototypie obsługują wiadomość, notatkę i zadanie.
    public var commandKind: ActionKind? {
        switch kind {
        case .reply: return .reply
        case .note: return .note
        case .task: return .task
        default: return nil
        }
    }

    /// Czy intencja wymaga odbiorcy. Zadanie może być „do listy”, reszta nie.
    public var requiresRecipient: Bool {
        switch kind {
        case .reply, .note, .caseSummary, .event: return true
        default: return false
        }
    }
}

// MARK: - Parser

public enum AssistantIntentParser {

    /// Formy zgody. Tylko krótkie, samodzielne wypowiedzi — „tak” w środku zdania
    /// o czymś innym nie jest zgodą.
    private static let confirmForms = ["wyślij", "zatwierdź", "zatwierdzam", "zapisz", "tak", "potwierdzam", "ok", "dobrze"]
    private static let cancelForms = ["anuluj", "rezygnuję", "porzuć", "nie"]

    private static let creationVerbs = ["dodaj", "dodać", "dopisz", "zaplanuj", "ustaw", "wpisz", "stwórz", "stworz"]

    /// Jednostki, po których liczba jest **ilością**, a nie godziną („20 minut” ≠ 20:00).
    private static let quantityUnits = ["minut", "min", "godzin", "godz", "h", "dni", "dzień", "dnia", "tygodni", "tydzień", "osób"]
    /// Nazwy rodzaju na początku treści („zadanie wyślij dokumenty” → „wyślij dokumenty”).
    private static let kindNouns = ["zadanie", "zadania", "notatkę", "notatka", "notatki", "spotkanie", "wydarzenie", "wiadomość", "wiadomosc", "odpowiedź", "odpowiedz"]

    private static let weekdayForms: [(form: String, index: Int)] = [
        ("poniedziałek", 0), ("poniedziałku", 0), ("poniedziałek", 0),
        ("wtorek", 1), ("wtorku", 1),
        ("środę", 2), ("środa", 2), ("środy", 2),
        ("czwartek", 3), ("czwartku", 3),
        ("piątek", 4), ("piątku", 4),
        ("sobotę", 5), ("sobota", 5), ("soboty", 5),
        ("niedzielę", 6), ("niedziela", 6), ("niedzieli", 6)
    ]
    private static let monthNames = [
        "stycznia", "lutego", "marca", "kwietnia", "maja", "czerwca",
        "lipca", "sierpnia", "września", "października", "listopada", "grudnia"
    ]
    private static let hourWords: [(form: String, hour: Int)] = [
        ("pierwszej", 1), ("drugiej", 2), ("trzeciej", 3), ("czwartej", 4), ("piątej", 5),
        ("szóstej", 6), ("siódmej", 7), ("ósmej", 8), ("dziewiątej", 9), ("dziesiątej", 10),
        ("jedenastej", 11), ("dwunastej", 12), ("trzynastej", 13), ("czternastej", 14),
        ("piętnastej", 15), ("szesnastej", 16), ("siedemnastej", 17), ("osiemnastej", 18),
        ("dziewiętnastej", 19), ("dwudziestej", 20)
    ]

    public static func parse(_ raw: String, today: LocalDate) -> AssistantIntent {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = normalized(text)
        guard !lowered.isEmpty else { return AssistantIntent(kind: .unknown) }

        // 1. Zgoda i anulowanie mają pierwszeństwo — są krótkie i rozstrzygające.
        if confirmForms.contains(lowered) { return AssistantIntent(kind: .confirm) }
        if cancelForms.contains(lowered) { return AssistantIntent(kind: .cancel) }

        let date = relativeDate(in: lowered, today: today)
        let time = timeOfDay(in: lowered)

        // 2. Poprawka. „Nie, na poniedziałek” to poprawka, nie anulowanie —
        //    dlatego sprawdzamy ją przed zwykłymi rodzajami i wymagamy wartości.
        if let revision = revision(in: lowered, text: text, date: date, time: time) {
            return AssistantIntent(kind: .correction, dueDate: date, dueTime: time, revision: revision)
        }

        // 3. Rodzaj czynności. Kolejność jest istotna: „dodaj spotkanie” to nie
        //    briefing, choć zawiera słowo „termin”; „wyślij Olenie wiadomość” to
        //    odpowiedź, a nie zgoda (zgoda jest tylko samodzielna, punkt 1).
        let kind = self.kind(of: lowered)
        return AssistantIntent(kind: kind, text: payloadText(of: text, kind: kind), dueDate: date, dueTime: time)
    }

    // MARK: Rodzaj

    private static func kind(of lowered: String) -> AssistantIntent.Kind {
        let hasCreationVerb = creationVerbs.contains { lowered.contains($0) }

        // „Przypomnij mi o spotkaniu” to zadanie-przypomnienie, nie tworzenie
        // wydarzenia — dlatego przypomnienie sprawdzamy przed nazwą spotkania.
        let wantsReminder = lowered.contains("przypomnij")
        if !wantsReminder,
           lowered.contains("spotkani") || lowered.contains("wydarzeni") || lowered.contains("wizyt") {
            return .event
        }
        if lowered.contains("notatk") { return .note }
        if lowered.contains("zadani") || wantsReminder || lowered.contains("do zrobienia") {
            return .task
        }
        if lowered.contains("odpow") || lowered.contains("wiadomo") || lowered.contains("whatsapp")
            || lowered.contains("sms") || lowered.contains("napisz do")
            || (hasCreationVerb && lowered.contains("wyślij")) {
            return .reply
        }
        if lowered.contains("spraw") || lowered.contains("przygotuj mnie") { return .caseSummary }
        if lowered.contains("plan") || lowered.contains("termin") || lowered.contains("kalendarz")
            || lowered.contains("dzisiejsz") || lowered.contains("dzisiaj") || lowered.contains("dziś")
            || lowered.contains("jutro") || lowered.contains("dzień") || lowered.contains("dniu") {
            return .briefing
        }
        return .unknown
    }

    // MARK: Treść

    /// Treść z wypowiedzi. Po dwukropku bierzemy całość, a dla wiadomości także
    /// zdanie po „że”/„iż” — bo tak mówi się polecenie wysłania (§6-A).
    private static func payloadText(of text: String, kind: AssistantIntent.Kind) -> String? {
        if let colon = text.firstIndex(of: ":") {
            let tail = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { return tail }
        }
        if kind == .reply {
            for marker in ["że ", "iż "] {
                if let range = text.range(of: marker, options: [.caseInsensitive]) {
                    let tail = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !tail.isEmpty { return tail }
                }
            }
            return trailingClause(of: text, after: ["napisz do", "napisz", "odpowiedz", "wyślij"])
        }
        guard kind == .task || kind == .note || kind == .event else { return nil }
        return trailingClause(of: text, after: creationVerbs)
    }

    /// Reszta zdania po pierwszym z podanych czasowników, z odcięciem adresata,
    /// kanału i nazwy rodzaju („Olenie WhatsApp, że …” → „że …”).
    private static func trailingClause(of text: String, after verbs: [String]) -> String? {
        for verb in verbs {
            guard let range = text.range(of: verb, options: [.caseInsensitive]) else { continue }
            let tail = stripLeadingRecipientAndChannel(String(text[range.upperBound...]))
            if !tail.isEmpty { return tail }
        }
        return nil
    }

    private static func stripLeadingRecipientAndChannel(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let removable = ["whatsapp", "whats app", "sms", "mailem", "maile", "e-mail", "email"] + kindNouns
        var changed = true
        var guardCounter = 0
        while changed && guardCounter < 8 {
            changed = false
            guardCounter += 1
            for token in removable + ["do", "dla", "że", "iż"] {
                let lowered = result.lowercased()
                guard lowered.hasPrefix(token + " ") || lowered == token else { continue }
                result = String(result.dropFirst(token.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
            }
            // Adresat w wołaczu (jedno słowo) przed przecinkiem.
            if let comma = result.firstIndex(of: ",") {
                let head = result[result.startIndex..<comma].trimmingCharacters(in: .whitespaces)
                let words = head.split(separator: " ")
                if !head.isEmpty, words.count == 1, (head.first?.isUppercase ?? false) {
                    result = String(result[result.index(after: comma)...])
                    changed = true
                }
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: " ,."))
    }

    // MARK: Data

    /// Data ze słów: relatywna, dzień tygodnia albo „12 września” / „12.09”.
    public static func relativeDate(in lowered: String, today: LocalDate) -> LocalDate? {
        if lowered.contains("pojutrze") { return today.adding(days: 2) }
        if lowered.contains("jutro") { return today.adding(days: 1) }
        if lowered.contains("dzisiaj") || lowered.contains("dziś") { return today }
        if lowered.contains("za tydzień") || lowered.contains("w przyszłym tygodniu") {
            return today.adding(days: 7)
        }
        // Dzień tygodnia: najbliższy **po** dzisiejszym, żeby „na poniedziałek”
        // w poniedziałek znaczyło za tydzień, a nie „już”.
        for entry in weekdayForms where lowered.contains(entry.form) {
            let delta = ((entry.index - today.weekdayIndexMondayFirst) + 7) % 7
            return today.adding(days: delta == 0 ? 7 : delta)
        }
        // „12 września” — najbliższa taka data (w tym roku albo w następnym).
        for (index, month) in monthNames.enumerated() {
            guard let range = lowered.range(of: month) else { continue }
            let before = String(lowered[lowered.startIndex..<range.lowerBound])
            guard let day = lastNumber(in: before), (1...31).contains(day) else { continue }
            let candidate = LocalDate(year: today.year, month: index + 1, day: day)
            if candidate < today { return LocalDate(year: today.year + 1, month: index + 1, day: day) }
            return candidate
        }
        // „12.09” albo „12.09.2026”.
        if let dotted = firstMatch(in: lowered, pattern: #"(\d{1,2})\.(\d{1,2})(?:\.(\d{4}))?"#),
           let day = Int(dotted[0]), let month = Int(dotted[1]),
           (1...31).contains(day), (1...12).contains(month) {
            let year = dotted.count > 2 ? Int(dotted[2]) ?? today.year : today.year
            let candidate = LocalDate(year: year, month: month, day: day)
            if year == today.year, candidate < today {
                return LocalDate(year: today.year + 1, month: month, day: day)
            }
            return candidate
        }
        return nil
    }

    // MARK: Godzina

    /// Godzina ze słów: „do 14”, „o 11:30”, „o jedenastej”. Liczby z jednostką
    /// („20 minut”) nie są godziną.
    public static func timeOfDay(in lowered: String) -> TimeOfDay? {
        if let hhmm = firstMatch(in: lowered, pattern: #"\b(\d{1,2}):(\d{2})\b"#),
           let hour = Int(hhmm[0]), let minute = Int(hhmm[1]),
           (0...23).contains(hour), (0...59).contains(minute),
           let time = TimeOfDay(minutes: hour * 60 + minute) {
            return time
        }
        for entry in hourWords where lowered.contains("o \(entry.form)") || lowered.contains("na \(entry.form)") {
            return TimeOfDay(minutes: entry.hour * 60)
        }
        for match in allMatches(in: lowered, pattern: #"\b(?:do|na|o|godzinie)\s+(\d{1,2})(?:\s*([a-ząćęłńóśźż]+))?"#) {
            guard let hour = Int(match[0]), (0...23).contains(hour) else { continue }
            // „na 20 minut” to ilość, nie godzina.
            if match.count > 1, quantityUnits.contains(where: { match[1].hasPrefix($0) }) {
                continue
            }
            return TimeOfDay(minutes: hour * 60)
        }
        return nil
    }

    // MARK: Poprawka

    private static func revision(
        in lowered: String,
        text: String,
        date: LocalDate?,
        time: TimeOfDay?
    ) -> AssistantIntent.Revision? {
        let markers = ["zmień", "zmien", "popraw", "zamiast", "jednak", "przesuń", "przesun", "zamiast"]
        let startsWithNo = lowered.hasPrefix("nie")
        let hasMarker = markers.contains { lowered.contains($0) }
        guard startsWithNo || hasMarker else { return nil }

        var revision = AssistantIntent.Revision()
        if let colon = text.firstIndex(of: ":") {
            let tail = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { revision.text = tail }
        }
        if let quantity = firstMatch(in: lowered, pattern: #"\b(\d{1,3})\s*([a-ząćęłńóśźż]+)\b"#),
           let value = Int(quantity[0]),
           quantityUnits.contains(where: { quantity[1].hasPrefix($0) }) {
            revision.quantity = value
            revision.unit = quantity[1]
        }
        // Odbiorcę wyłuskujemy z „do/dla <imię>”: to najkrótsza sensowna poprawka
        // („nie, do Dmytro”) i nie zawiera ani treści, ani terminu.
        if let person = firstMatch(in: lowered, pattern: #"\b(?:do|dla)\s+([a-ząćęłńóśźż]{3,})\b"#) {
            revision.recipient = person[0]
        }
        revision.time = time
        revision.date = date
        return revision.isEmpty ? nil : revision
    }

    // MARK: Pomocnicze

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .!?"))
    }

    private static func lastNumber(in value: String) -> Int? {
        allMatches(in: value, pattern: #"\b(\d{1,2})\b"#).last.flatMap { Int($0[0]) }
    }

    private static func firstMatch(in value: String, pattern: String) -> [String]? {
        allMatches(in: value, pattern: pattern).first
    }

    /// Dopasowania jako **grupy przechwytujące** (bez całego dopasowania), więc
    /// `match[0]` jest pierwszą grupą z wzorca. Grupa opcjonalna bez trafienia
    /// jest pomijana — dzięki temu `match.count` mówi, czy jednostka wystąpiła.
    private static func allMatches(in value: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range).map { match in
            guard match.numberOfRanges > 1 else { return [] }
            return (1..<match.numberOfRanges).compactMap { index in
                guard match.range(at: index).location != NSNotFound,
                      let sub = Range(match.range(at: index), in: value) else { return nil }
                return String(value[sub])
            }
        }
    }
}
