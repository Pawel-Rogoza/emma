import Foundation

// MARK: - Narzędzia aplikacji dla Gemini Live (`app_*`)
//
// Model rozmawia głosem i **steruje aplikacją** przez te narzędzia: otwiera
// ekrany, karty klientów i spraw, rozmowy WhatsApp, przygotowuje notatki,
// zadania, szkice wiadomości i terminy, liczy terminy procesowe. Wykonuje je
// ten ekran, bo to on pokazuje karty propozycji i zna powiązanie klient → sprawa.
//
// Granica bezpieczeństwa jest ta sama co w interfejsie: żadne narzędzie nie
// zapisuje danych, nie wysyła i nie daje zgody. Propozycja trafia na kartę
// (zapis po „Zatwierdź”, `/actions/{id}/confirm` z nagłówkiem
// `direct_ui_button`), szkic wiadomości — w pole odpowiedzi rozmowy, termin —
// do formularza. Model dostaje to wprost w wyniku narzędzia.
//
// Deklaracje (nazwy, argumenty) są po stronie backendu:
// `adwokat-app-project/src/lib/crm/voice/appTools.ts`. Identyfikatory przychodzą
// tak, jak zwracają je narzędzia CRM — liczby (`12`) albo z prefiksem
// (`client-12`, `lead-7`) — i są tu normalizowane.

extension AssistantStore: VoiceAppToolHandling {

    func handleAppTool(name: String, argumentsJSON: String) async -> String {
        guard let dependencies else {
            return Self.toolError("Ekran Emmy nie jest gotowy.")
        }
        let args = Self.arguments(from: argumentsJSON)

        switch name {
        case "app_open_screen":
            return openScreen(
                args["screen"] as? String,
                day: (args["date"] as? String).flatMap { LocalDate(iso: $0) },
                dependencies: dependencies
            )

        case "app_open_client":
            guard let clientID = Self.contactID(from: args) else {
                return Self.toolError("Podaj client_id albo lead_id z wyniku wyszukiwania.")
            }
            guard let client = await resolveClient(clientID, dependencies: dependencies) else {
                return Self.toolError("Nie znaleziono tej osoby w kancelarii.")
            }
            dependencies.emmaContext = client.id
            dependencies.openPerson(client.id)
            return Self.toolResult(["status": "opened", "screen": "client", "name": client.displayName])

        case "app_open_case":
            guard let caseID = Self.entityID(args["case_id"], prefix: "case") else {
                return Self.toolError("Podaj case_id z wyniku wyszukiwania spraw.")
            }
            dependencies.openCase(CaseID(caseID))
            return Self.toolResult(["status": "opened", "screen": "case", "case_id": caseID])

        case "app_prepare_action":
            return await prepareFromTool(args, dependencies: dependencies)

        case "app_revise_action":
            guard let text = (args["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                return Self.toolError("Podaj nową treść.")
            }
            guard let actionID = targetActionID(args) else {
                return Self.toolError("Nie ma przygotowanej propozycji do poprawienia.")
            }
            await edit(actionID: actionID, text: text)
            // Korekta udana = karta na ekranie niesie nową treść.
            guard let pending = pendingAction, pending.proposal.text == text else {
                return Self.toolError(dependencies.voice.state.lastError ?? "Nie udało się poprawić propozycji.")
            }
            return Self.toolResult([
                "status": "awaiting_user_confirmation",
                "action_id": pending.proposal.id.rawValue,
                "text": pending.proposal.text,
                "message": "Poprawiona karta czeka na zatwierdzenie przyciskiem. Wcześniejsza zgoda przestała obowiązywać.",
            ])

        case "app_cancel_action":
            guard let actionID = targetActionID(args) else {
                return Self.toolError("Nie ma przygotowanej propozycji do anulowania.")
            }
            await cancel(actionID: actionID)
            return Self.toolResult(["status": "cancelled", "action_id": actionID.rawValue])

        case "app_open_thread":
            guard let clientID = Self.contactID(from: args) else {
                return Self.toolError("Podaj client_id albo lead_id z wyniku wyszukiwania.")
            }
            guard let threadID = await conversationID(for: ClientID(clientID), dependencies: dependencies) else {
                return Self.toolError("Ta osoba nie pisała do kancelarii na WhatsAppie — nie ma rozmowy do otwarcia.")
            }
            dependencies.emmaContext = ClientID(clientID)
            dependencies.openThread(threadID)
            return Self.toolResult(["status": "opened", "screen": "thread"])

        case "app_draft_reply":
            return await draftReplyFromTool(args, dependencies: dependencies)

        case "app_prepare_event":
            return await prepareEventFromTool(args, dependencies: dependencies)

        case "app_compute_deadline":
            return await computeDeadlineFromTool(args, dependencies: dependencies)

        default:
            return Self.toolError("Aplikacja nie zna narzędzia \(name).")
        }
    }

    // MARK: Rozmowy WhatsApp

    /// Rozmowa osoby z listy wątków — bez zgadywania identyfikatora.
    func conversationID(for clientID: ClientID, dependencies: AppDependencies) async -> ThreadID? {
        let threads = (try? await dependencies.repository.threads()) ?? []
        return threads.first { $0.clientID == clientID }?.id
    }

    /// Szkic w polu odpowiedzi rozmowy. Wysyła adwokat — model tego nie umie
    /// i dostaje to wprost w wyniku.
    private func draftReplyFromTool(_ args: [String: Any], dependencies: AppDependencies) async -> String {
        guard let text = (args["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return Self.toolError("Podaj treść wiadomości.")
        }
        guard let rawID = Self.contactID(from: args) ?? dependencies.emmaContext?.rawValue else {
            return Self.toolError("Nie wiem, do kogo napisać. Wyszukaj osobę i podaj client_id albo lead_id.")
        }
        let clientID = ClientID(rawID)
        guard let threadID = await conversationID(for: clientID, dependencies: dependencies) else {
            return Self.toolError("Ta osoba nie pisała do kancelarii na WhatsAppie, więc nie ma rozmowy, w której można odpisać.")
        }
        dependencies.emmaContext = clientID
        dependencies.pendingThreadDraft = ThreadDraftSeed(threadID: threadID, text: text)
        dependencies.openThread(threadID)
        return Self.toolResult([
            "status": "draft_in_composer",
            "text": text,
            "message": "Szkic jest w polu odpowiedzi rozmowy. Wysyła użytkownik przyciskiem — nie mów, że wysłano.",
        ])
    }

    // MARK: Kalendarz i terminy

    /// Formularz nowego terminu wypełniony z rozmowy. Zapis — w formularzu.
    private func prepareEventFromTool(_ args: [String: Any], dependencies: AppDependencies) async -> String {
        let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let day = (args["date"] as? String).flatMap { LocalDate(iso: $0) }
        let time = (args["time"] as? String).flatMap { TimeOfDay(hhmm: $0) }
        let (clientID, caseID) = await eventContext(args, dependencies: dependencies)
        dependencies.pendingEventDraft = EventDraftSeed(
            title: (title?.isEmpty == false) ? title : nil,
            day: day,
            time: time
        )
        dependencies.present(.eventForm(editing: nil, clientID: clientID, caseID: caseID, initialDay: day))
        var result: [String: Any] = [
            "status": "form_open",
            "message": "Formularz terminu jest otwarty. Zapisze go użytkownik przyciskiem — nie mów, że dodano.",
        ]
        if let day { result["date"] = day.isoString }
        if let time { result["time"] = time.hhmm }
        return Self.toolResult(result)
    }

    /// Ta sama arytmetyka co „Policz termin” w formularzu (sobota i święta
    /// przesuwają koniec). Na życzenie od razu otwiera formularz z wyliczeniem.
    private func computeDeadlineFromTool(_ args: [String: Any], dependencies: AppDependencies) async -> String {
        guard let from = (args["from_date"] as? String).flatMap({ LocalDate(iso: $0) }) else {
            return Self.toolError("Podaj from_date (dzień doręczenia albo ogłoszenia) jako RRRR-MM-DD.")
        }
        let days = (args["days"] as? NSNumber)?.intValue
        switch ProceduralDeadlines.compute(ruleID: args["rule_id"] as? String, days: days, from: from) {
        case .failure(.unknownRule(let id)):
            let known = ProceduralDeadlines.common.map(\.id).joined(separator: ", ")
            return Self.toolError("Nie znam reguły \(id). Znane: \(known). Albo podaj days.")
        case .failure(.hourly(let rule)):
            return Self.toolError(
                "\(rule.title) liczy się w godzinach od chwili zatrzymania (\(rule.spanText)). "
                    + "Zapytaj o dzień i godzinę zatrzymania i otwórz formularz terminu."
            )
        case .failure(.missingSpan):
            return Self.toolError("Podaj rule_id z listy albo liczbę dni (days).")
        case .success(let computation):
            var result: [String: Any] = [
                "from_date": computation.from.isoString,
                "span": computation.spanText,
                "due_date": computation.result.due.isoString,
                "due_text": dependencies.dateText.dayTitle(computation.result.due),
            ]
            if let reason = computation.result.shiftReason {
                result["shifted_from"] = computation.result.nominal.isoString
                result["shift_reason"] = reason
            }
            if let rule = computation.rule {
                result["rule"] = rule.title
                result["legal_basis"] = rule.legalBasis
                result["starts_from"] = rule.startsFrom
            }
            if args["open_form"] as? Bool == true {
                let (clientID, caseID) = await eventContext(args, dependencies: dependencies)
                dependencies.pendingEventDraft = EventDraftSeed(
                    title: computation.rule?.title,
                    deadlineFrom: computation.from,
                    deadlineRuleID: computation.rule?.id
                )
                dependencies.present(.eventForm(editing: nil, clientID: clientID, caseID: caseID, initialDay: nil))
                result["form"] = "open — zapis przyciskiem w formularzu"
            }
            return Self.toolResult(result)
        }
    }

    /// Klient i sprawa terminu: z argumentów, a sprawa podpowiada klienta.
    private func eventContext(_ args: [String: Any], dependencies: AppDependencies) async -> (ClientID?, CaseID?) {
        let caseID = Self.entityID(args["case_id"], prefix: "case").map { CaseID($0) }
        var clientID = Self.contactID(from: args).map { ClientID($0) }
        if clientID == nil, let caseID {
            clientID = (try? await dependencies.repository.legalCase(id: caseID))?.clientID
        }
        return (clientID ?? dependencies.emmaContext, caseID)
    }

    // MARK: Nawigacja

    /// Ekran aplikacji; kalendarz od razu na wskazanym dniu („pokaż piątek”).
    private func openScreen(_ screen: String?, day: LocalDate?, dependencies: AppDependencies) -> String {
        switch screen {
        case "today": dependencies.go(to: .today, resetStack: true)
        case "tasks": dependencies.openTasks()
        case "calendar":
            if let day {
                dependencies.openCalendar(on: day)
            } else {
                dependencies.go(to: .calendar, resetStack: true)
            }
        case "clients": dependencies.go(to: .clients, resetStack: true)
        case "leads": dependencies.openLeads(filter: .needsAction)
        case "messages": dependencies.go(to: .messages, resetStack: true)
        case "emma": dependencies.go(to: .emma)
        default:
            return Self.toolError("Nieznany ekran. Dostępne: today, tasks, calendar, clients, leads, messages, emma.")
        }
        var result: [String: Any] = ["status": "opened", "screen": screen ?? ""]
        if screen == "calendar", let day { result["date"] = day.isoString }
        return Self.toolResult(result)
    }

    // MARK: Propozycje

    private func prepareFromTool(_ args: [String: Any], dependencies: AppDependencies) async -> String {
        guard let rawKind = args["kind"] as? String, let kind = ActionKind(rawValue: rawKind), kind != .reply else {
            return Self.toolError("Pole kind musi być note albo task.")
        }
        guard let text = (args["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return Self.toolError("Podaj treść notatki albo zadania.")
        }
        if let pending = pendingAction {
            return Self.toolError(
                "Na ekranie czeka już propozycja (action_id \(pending.proposal.id.rawValue)). "
                    + "Najpierw niech użytkownik ją zatwierdzi albo ją anuluj."
            )
        }

        // Osoba: z argumentu, a gdy go brak — z bieżącego kontekstu rozmowy.
        var clientID = Self.contactID(from: args).map { ClientID($0) } ?? dependencies.emmaContext
        if clientID == nil, let caseID = Self.entityID(args["case_id"], prefix: "case") {
            clientID = (try? await dependencies.repository.legalCase(id: CaseID(caseID)))?.clientID
        }
        guard let clientID else {
            return Self.toolError("Nie wiem, której osoby dotyczy. Wyszukaj klienta i podaj client_id.")
        }
        let dueDate = (args["due_date"] as? String).flatMap { LocalDate(iso: $0) }

        // Karta musi być widoczna: przechodzimy na ekran Emmy.
        dependencies.emmaContext = clientID
        dependencies.go(to: .emma)
        guard let turn = await newAction(kind: kind, clientID: clientID, text: text, dueDate: dueDate) else {
            return Self.toolError(dependencies.voice.state.lastError ?? "Nie udało się przygotować propozycji.")
        }
        var result: [String: Any] = [
            "status": "awaiting_user_confirmation",
            "action_id": turn.proposal.id.rawValue,
            "kind": kind.rawValue,
            "text": turn.proposal.text,
            "message": "Karta czeka na ekranie. Zapis nastąpi dopiero po dotknięciu „Zatwierdź”. Nie mów, że zapisano.",
        ]
        if let due = turn.proposal.taskDueDate { result["due_date"] = due.isoString }
        return Self.toolResult(result)
    }

    private func targetActionID(_ args: [String: Any]) -> ActionID? {
        if let raw = args["action_id"] as? String, !raw.isEmpty { return ActionID(raw) }
        return pendingAction?.proposal.id
    }

    private func resolveClient(_ rawID: String, dependencies: AppDependencies) async -> Client? {
        let id = ClientID(rawID)
        if let known = client(id: id) { return known }
        return try? await dependencies.repository.client(id: id)
    }

    // MARK: Argumenty i wynik

    static func arguments(from json: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
    }

    /// Klient z kartoteki (`client_id`) albo zgłoszenie (`lead_id`) — w aplikacji
    /// to ta sama karta, różni je prefiks identyfikatora.
    static func contactID(from args: [String: Any]) -> String? {
        entityID(args["client_id"], prefix: "client") ?? entityID(args["lead_id"], prefix: "lead")
    }

    /// `12`, `"12"` i `"client-12"` → `"client-12"`. Identyfikator z innym
    /// prefiksem (np. `"lead-7"` podany jako `client_id`) zostaje bez zmian.
    static func entityID(_ value: Any?, prefix: String) -> String? {
        if let number = value as? NSNumber {
            let integer = number.intValue
            guard integer > 0, Double(integer) == number.doubleValue else { return nil }
            return "\(prefix)-\(integer)"
        }
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if let integer = Int(text), integer > 0 { return "\(prefix)-\(integer)" }
        return text
    }

    static func toolResult(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return #"{"status":"ok"}"#
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func toolError(_ message: String) -> String {
        toolResult(["error": message])
    }
}
