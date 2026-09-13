import SwiftUI

// MARK: - Karta działania Emmy (`.emma-action`)
//
// Odpowiada `renderTurn()` z referencji (`reference/prototype/app.js`) dla tury
// typu `action`: nagłówek z ikoną i etykietą rodzaju, pigułka stanu, nazwa klienta,
// dla zadań prowadzący i termin, a w stanie `proposed` edytowalny szkic treści
// oraz przyciski „Zatwierdź” i „Anuluj”.
//
// Karta **nigdy** nie wykonuje zapisu samodzielnie. Przekazuje zdarzenie do
// koordynatora, a ten wymaga dowodu zgody (§8.2): dotknięcia przycisku w interfejsie
// (`.directUIButton`) albo finalnej wypowiedzi uwierzytelnionego użytkownika
// (`.authenticatedVoiceTurn`). Tekst wygenerowany przez model językowy
// (`.languageModelArgument`) nie jest zgodą i nie występuje w tym pliku.

private extension ActionKind {
    /// Ikona rodzaju działania. Referencja używa `chat` / `edit` / `tasks`.
    var emmaIconName: String {
        switch self {
        case .reply: return "bubble.left.and.bubble.right"
        case .note: return "square.and.pencil"
        case .task: return "checklist"
        }
    }
}

private extension String {
    var emmaTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
struct EmmaActionCard: View {

    private let proposal: ActionProposal
    private let clientName: String?
    private let execution: ActionExecution?
    private let isArmedForVoice: Bool
    /// Termin zadania sformatowany przez ekran (karta nie zna „dzisiaj” aplikacji).
    private let dueDateText: String?
    private let onEdit: (String) -> Void
    /// Potwierdzenie dostaje **bieżącą** treść szkicu, a nie wersję sprzed chwili.
    /// Bez tego szybkie „Zatwierdź” po edycji wykonywało poprzednią treść (F03).
    private let onConfirm: (String) -> Void
    private let onCancel: () -> Void
    /// Odsłuch treści (`speakAction`). Czyta bieżący szkic, nie wersję sprzed edycji (F03).
    private let onSpeak: ((String) -> Void)?

    @State private var draft: String
    /// Ostatnia treść wysłana do rewizji — chroni przed pętlą korekt.
    @State private var revisionSent: String

    init(
        proposal: ActionProposal,
        clientName: String?,
        execution: ActionExecution?,
        isArmedForVoice: Bool,
        onEdit: @escaping (String) -> Void,
        onConfirm: @escaping (String) -> Void,
        onCancel: @escaping () -> Void,
        dueDateText: String? = nil,
        onSpeak: ((String) -> Void)? = nil
    ) {
        self.proposal = proposal
        self.clientName = clientName
        self.execution = execution
        self.isArmedForVoice = isArmedForVoice
        self.dueDateText = dueDateText
        self.onEdit = onEdit
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.onSpeak = onSpeak
        _draft = State(initialValue: proposal.text)
        _revisionSent = State(initialValue: proposal.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
            // Nazwa klienta może być cyrylicą — czcionka wybierana jest wg pisma.
            Text(resolvedClientName)
                .font(EmmaTypography.body(for: resolvedClientName, size: 15, weight: .semibold))
                .foregroundStyle(EmmaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
                .padding(.bottom, 12)
            if proposal.kind == .task {
                taskMetaLine
            }
            if isActionable {
                editor
            } else {
                settled
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EmmaTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.actionCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EmmaRadii.actionCard, style: .continuous)
                .strokeBorder(EmmaTheme.actionCardBorder, lineWidth: 1)
        }
        .onChange(of: proposal.text) { _, newValue in
            // Treść zmieniła się poza kartą (np. korekta głosem) — pokazujemy nową wersję.
            guard newValue != revisionSent else { return }
            draft = newValue
            revisionSent = newValue
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Nagłówek i metadane

    /// Nazwa klienta z referencji; dla działania firmowego „Kancelaria”.
    private var resolvedClientName: String { clientName ?? Client.firmDisplayName }

    private var heading: some View {
        HStack(alignment: .center, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: proposal.kind.emmaIconName)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(EmmaTheme.actionHeadingText)
                Text(proposal.kind.displayName)
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.actionHeadingText)
            }
            Spacer(minLength: 7)
            StatusPill(stateText, kind: pillKind)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(proposal.kind.displayName). Stan: \(stateText)")
    }

    @ViewBuilder
    private var taskMetaLine: some View {
        if let meta = taskMeta {
            Text(meta)
                .font(EmmaTypography.caption())
                .foregroundStyle(EmmaTheme.actionMetaText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
        }
    }

    /// Termin zadania tworzonego przez Emmę. Akcje nie mają właściciela.
    private var taskMeta: String? {
        dueDateText
    }

    // MARK: Stan prezentacji

    /// Czy propozycja czeka na decyzję i wolno pokazać edytor oraz przyciski.
    private var isActionable: Bool { proposal.state == .proposed }

    private var stateText: String {
        if let execution {
            switch execution.state {
            case .accepted: return "Wykonano"
            case .failed: return ExecutionState.failed.displayName
            case .unknown: return ExecutionState.unknown.displayName
            case .queued, .claimed, .dispatching: return execution.state.displayName
            }
        }
        switch proposal.state {
        case .proposed: return ProposalState.proposed.displayName
        case .confirmed: return ProposalState.confirmed.displayName
        case .rejected: return "Anulowano"
        case .expired: return ProposalState.expired.displayName
        case .superseded: return ProposalState.superseded.displayName
        }
    }

    private var pillKind: StatusPill.Kind {
        if let execution {
            return execution.state == .accepted ? .green : .amber
        }
        return proposal.state == .proposed ? .neutral : .amber
    }

    // MARK: Edytor (stan `proposed`)

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $draft)
                .font(EmmaTypography.actionBody(draft))
                .foregroundStyle(EmmaTheme.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: EmmaMetrics.actionDraftMinHeight)
                .padding(9)
                .background(EmmaTheme.draftBackground)
                .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.button, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: EmmaRadii.button, style: .continuous)
                        .strokeBorder(EmmaTheme.draftBorder, lineWidth: 1)
                }
                .accessibilityLabel("Edytuj treść działania")
                .task(id: draft) { await sendRevisionAfterPause() }

            HStack(spacing: 8) {
                SecondaryButton(
                    "Odsłuchaj",
                    systemImage: "speaker.wave.2",
                    isEnabled: onSpeak != nil
                ) {
                    onSpeak?(draft)
                }
                .accessibilityLabel("Odsłuchaj treść działania")
                SecondaryButton("Anuluj") {
                    onCancel()
                }
                .accessibilityLabel("Anuluj działanie")
            }

            PrimaryButton(
                proposal.kind.confirmLabel,
                systemImage: "checkmark",
                isEnabled: !draft.emmaTrimmed.isEmpty
            ) {
                // Bieżący szkic jest wysyłany razem ze zgodą i od razu uznany za
                // wysłany do rewizji, żeby odroczona korekta nie zdążyła nadpisać
                // treści tuż po zatwierdzeniu (F03).
                revisionSent = draft
                onConfirm(draft)
            }
            .accessibilityLabel(proposal.kind.confirmLabel)

            consentNote
        }
    }

    /// Jawna informacja o drodze zgody. Bez uzbrojenia głos nie może wykonać akcji —
    /// wtedy jedyną drogą jest przycisk na ekranie (§8.2).
    private var consentNote: some View {
        Text(
            isArmedForVoice
                ? "Potwierdzenie głosem jest uzbrojone dla tej prezentacji. Nadal możesz użyć przycisku."
                : "Potwierdzenie głosem nie jest uzbrojone: wykonanie wymaga przycisku „\(proposal.kind.confirmLabel)” na ekranie."
        )
        .font(EmmaTypography.caption())
        .foregroundStyle(EmmaTheme.emmaListenText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(isArmedForVoice
            ? "Potwierdzenie głosem uzbrojone. Możesz też użyć przycisku."
            : "Potwierdzenie głosem nieuzbrojone. Wymagany przycisk na ekranie.")
    }

    /// Korekta treści unieważnia wcześniejszą zgodę (§1.10), dlatego wysyłamy ją
    /// dopiero po pauzie w pisaniu — nie przy każdym znaku.
    private func sendRevisionAfterPause() async {
        let pending = draft
        guard pending != revisionSent, !pending.emmaTrimmed.isEmpty else { return }
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard !Task.isCancelled else { return }
        revisionSent = pending
        onEdit(pending)
    }

    // MARK: Stan rozstrzygnięty (wysłane, anulowane, niepewny wynik)

    private var settled: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(proposal.text)
                .font(EmmaTypography.actionBody(proposal.text))
                .foregroundStyle(EmmaTheme.ink.opacity(0.9))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
            if let note = settledNote {
                Text(note)
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.actionMetaText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var settledNote: String? {
        if let execution {
            switch execution.state {
            case .accepted:
                return nil
            case .unknown:
                // Niepewny wynik: nie ogłaszamy sukcesu i nie oferujemy ponowienia (§8.3).
                return "Nie znam jeszcze wyniku tego działania. Sprawdzam status; automatycznego ponowienia nie ma."
            case .failed:
                return "Wykonanie nie powiodło się. Treść zostaje na ekranie — możesz przygotować działanie ponownie."
            case .queued, .claimed, .dispatching:
                return "Działanie jest w outboxie (stan: \(execution.state.displayName)). Wynik potwierdzę, gdy dostawca go zaraportuje."
            }
        }
        switch proposal.state {
        case .proposed:
            return nil
        case .confirmed:
            return "Zatwierdzone. Czekam na raport wykonania."
        case .rejected:
            return "Działanie anulowane. Nie zostało wysłane."
        case .expired:
            return "Okno potwierdzenia minęło. Przygotuj działanie ponownie."
        case .superseded:
            return "Zastąpiła je nowsza wersja treści."
        }
    }
}
