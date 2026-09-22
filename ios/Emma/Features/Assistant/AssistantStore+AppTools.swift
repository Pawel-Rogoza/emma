import Foundation

// MARK: - Narzędzia aplikacji dla Gemini Live (`app_*`)
//
// Model rozmawia głosem i **steruje aplikacją** przez te narzędzia: otwiera
// ekrany, karty klientów i spraw, przygotowuje notatki i zadania. Wykonuje je
// ten ekran, bo to on pokazuje karty propozycji i zna powiązanie klient → sprawa.
//
// Granica bezpieczeństwa jest ta sama co w interfejsie: żadne narzędzie nie
// zapisuje danych ani nie daje zgody. Propozycja trafia na kartę, a zapis
// następuje dopiero po dotknięciu „Zatwierdź” (`/actions/{id}/confirm`
// z nagłówkiem `direct_ui_button`). Model dostaje to wprost w wyniku narzędzia.
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
            return openScreen(args["screen"] as? String, dependencies: dependencies)

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

        default:
            return Self.toolError("Aplikacja nie zna narzędzia \(name).")
        }
    }

    // MARK: Nawigacja

    private func openScreen(_ screen: String?, dependencies: AppDependencies) -> String {
        switch screen {
        case "today": dependencies.go(to: .today, resetStack: true)
        case "tasks": dependencies.openTasks()
        case "calendar": dependencies.go(to: .calendar, resetStack: true)
        case "clients": dependencies.go(to: .clients, resetStack: true)
        case "messages": dependencies.go(to: .messages, resetStack: true)
        case "emma": dependencies.go(to: .emma)
        default:
            return Self.toolError("Nieznany ekran. Dostępne: today, tasks, calendar, clients, messages, emma.")
        }
        return Self.toolResult(["status": "opened", "screen": screen ?? ""])
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
