import SwiftUI

// MARK: - Wspólne elementy formularzy
//
// Review 24.09.2026: formularz terminu „brzydko wygląda” — daty i godziny
// wpisywało się jako tekst („2026-09-11”, „15:00”), a pola stały jedno pod
// drugim bez grupowania. Formularze składają się teraz z kart z wierszami
// (jak Ustawienia iOS), a data i godzina mają systemowe kontrolki.

/// Karta formularza: wiersze oddzielone cienką linią.
struct FormCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(EmmaTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
        }
        .emmaCardShadow()
    }
}

/// Wiersz karty formularza: ikona, etykieta i treść po prawej.
struct FormRow<Trailing: View>: View {
    private let systemImage: String
    private let title: String
    private let trailing: Trailing

    init(systemImage: String, title: String, @ViewBuilder trailing: () -> Trailing) {
        self.systemImage = systemImage
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(EmmaTheme.accent)
                .frame(width: 30, height: 30)
                .background(EmmaTheme.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            if title.isEmpty {
                // Wiersz z samym polem (np. miejsce) — pole zajmuje całą szerokość.
                trailing
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(title)
                    .font(EmmaTypography.ui(15))
                    .foregroundStyle(EmmaTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                trailing
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
    }
}

/// Linia między wierszami karty (wcięta pod ikonę).
struct FormDivider: View {
    var body: some View {
        Divider()
            .overlay(EmmaTheme.rowSeparator)
            .padding(.leading, 56)
    }
}

/// Nagłówek grupy formularza: „KIEDY”, „Z KIM”.
struct FormSectionLabel: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(EmmaTypography.caption(.semibold))
            .tracking(0.6)
            .foregroundStyle(EmmaTheme.mutedSoft)
            .padding(.horizontal, 4)
            .padding(.top, 18)
            .padding(.bottom, 7)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Chip szybkiego wyboru („Jutro”, „Online”).
struct QuickChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            EmmaHaptics.selection()
            action()
        } label: {
            Text(title)
                .font(EmmaTypography.caption(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? EmmaTheme.primaryButtonText : EmmaTheme.secondaryButtonText)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(isSelected ? EmmaTheme.primaryButton : EmmaTheme.secondaryButton, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(EmmaCardButtonStyle())
        .animation(EmmaMotion.snappy, value: isSelected)
        .frame(minHeight: EmmaSpacing.hitTarget)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Chipy zawijane do kolejnej linii — wybór jednym dotknięciem bez przewijania
/// w bok (rodzaj sprawy, etap, rola klienta).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// Kontener chipów zawijanych do kolejnej linii (`FlowLayout`).
struct ChipFlow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        FlowLayout().callAsFunction { content }
    }
}

/// Chip wyboru z ikoną. Ponowne dotknięcie wybranego odznacza go (pole
/// profilu sprawy może zostać nieustalone).
struct ChoiceChip: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            EmmaHaptics.selection()
            action()
        } label: {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(EmmaTypography.ui(14, isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? EmmaTheme.primaryButtonText : EmmaTheme.secondaryButtonText)
            .padding(.horizontal, 13)
            .frame(minHeight: 38)
            .background(isSelected ? EmmaTheme.primaryButton : EmmaTheme.secondaryButton, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(EmmaCardButtonStyle())
        .animation(EmmaMotion.snappy, value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Data i godzina w strefie kancelarii

/// Zamiana `LocalDate` + `TimeOfDay` ↔ `Date` dla systemowych kontrolek.
///
/// Kontrolki działają w strefie kancelarii (`Europe/Warsaw`), tak jak cała
/// aplikacja (§2.2) — telefon w innej strefie nie przesuwa terminu o godzinę.
enum FirmDateTime {
    static var timeZone: TimeZone {
        TimeZone(identifier: EmmaTime.referenceTimeZone) ?? .current
    }

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "pl_PL")
        calendar.firstWeekday = 2
        return calendar
    }

    static func date(day: LocalDate, time: TimeOfDay) -> Date {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = time.hour
        components.minute = time.minute
        return calendar.date(from: components) ?? Date()
    }

    static func day(of date: Date) -> LocalDate {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return LocalDate(year: parts.year ?? 2026, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    static func time(of date: Date) -> TimeOfDay {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0)) ?? TimeOfDay(minutes: 0)!
    }
}

// MARK: - Dyktowanie do pola

/// Przycisk dyktowania do pola tekstowego.
///
/// Review 24.09.2026: „klikam »rozpocznij dyktowanie«, a i tak muszę nacisnąć
/// mikrofon na klawiaturze”. Trzy przyczyny:
///   1. tekst częściowy nie trafiał do pola — pole było puste aż do końca,
///   2. „Zakończ dyktowanie” zwalniało rozpoznawanie przed wynikiem końcowym,
///      więc tekst przepadał (poprawka w `AppleSpeechDictationService.finish`),
///   3. notatka była rozpoznawana w **języku klienta** (np. ukraińskim), a mówi
///      ją adwokat — po polsku; rozpoznawanie oddawało bełkot albo nic.
/// Teraz tekst pojawia się w polu na bieżąco, dopisuje się do tego, co już
/// było, a język to język interfejsu użytkownika.
struct DictationButton: View {

    @EnvironmentObject private var dependencies: AppDependencies

    @Binding var text: String
    let target: DictationTarget

    @State private var isActive = false
    /// Treść pola sprzed dyktowania — dyktowany tekst się do niej dopisuje.
    @State private var base = ""
    @State private var previousHandler: ((DictationTarget, String) -> Void)?

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isActive ? EmmaTheme.danger : EmmaTheme.primaryButton)
                        .frame(width: 40, height: 40)
                    Image(systemName: isActive ? "stop.fill" : "mic.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(EmmaTheme.primaryButtonText)
                }
                .overlay {
                    if isActive {
                        Circle()
                            .strokeBorder(EmmaTheme.danger.opacity(0.35), lineWidth: 3)
                            .frame(width: 50, height: 50)
                            .phaseAnimator([false, true]) { view, phase in
                                view.scaleEffect(phase ? 1.12 : 0.92).opacity(phase ? 0.2 : 0.9)
                            } animation: { _ in .easeInOut(duration: 0.8) }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(isActive ? "Słucham… dotknij, aby zakończyć" : "Podyktuj")
                        .font(EmmaTypography.ui(15, .semibold))
                        .foregroundStyle(EmmaTheme.ink)
                    Text(isActive ? "Tekst wpisuje się do pola na bieżąco." : "Mów — tekst sam wpisze się w pole.")
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.mutedSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                    .strokeBorder(isActive ? EmmaTheme.danger.opacity(0.5) : EmmaTheme.cardBorder, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(EmmaCardButtonStyle())
        .accessibilityLabel(isActive ? "Zakończ dyktowanie" : "Podyktuj")
        .accessibilityIdentifier("dictation-button")
        .onChange(of: dependencies.voiceState.partialTranscript) { _, partial in
            guard isActive, !partial.isEmpty else { return }
            text = Self.joined(base, partial)
        }
        .onChange(of: dependencies.voiceState.mode) { _, mode in
            // Błąd albo anulowanie kończą dyktowanie bez wyniku — przycisk
            // wraca do stanu spoczynku, a komunikat pokazuje powłoka.
            if isActive, mode != .dictation {
                isActive = false
                restoreHandler()
            }
        }
        .onDisappear {
            guard isActive else { return }
            isActive = false
            restoreHandler()
            Task { await dependencies.voice.cancelDictation() }
        }
    }

    private func toggle() async {
        if isActive {
            EmmaHaptics.tap()
            await dependencies.voice.finishDictation()
            isActive = false
            restoreHandler()
            return
        }
        EmmaHaptics.tap()
        base = text
        previousHandler = dependencies.voice.onDictationResult
        let binding = $text
        let start = text
        dependencies.voice.onDictationResult = { _, dictated in
            binding.wrappedValue = Self.joined(start, dictated)
        }
        isActive = true
        await dependencies.voice.startDictation(
            target: target,
            language: dependencies.currentUser.interfaceLanguage,
            service: dependencies.makeDictationService()
        )
    }

    private func restoreHandler() {
        dependencies.voice.onDictationResult = previousHandler
        previousHandler = nil
    }

    /// Dopisanie do istniejącej treści ze spacją, ale bez podwójnych odstępów.
    static func joined(_ base: String, _ addition: String) -> String {
        let trimmedAddition = addition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddition.isEmpty else { return base }
        guard !base.isEmpty else { return trimmedAddition }
        let separator = base.last.map { $0.isWhitespace } == true ? "" : " "
        return base + separator + trimmedAddition
    }
}
