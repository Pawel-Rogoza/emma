import Foundation
import Security

// MARK: - Sesja mobilna w kluczyku systemowym
//
// Token dostępu i token odświeżania nie mogą leżeć w `UserDefaults`: ten plik
// czyta każdy proces w piaskownicy i trafia do kopii zapasowej. Kluczyk daje
// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — dostęp dopiero po
// pierwszym odblokowaniu telefonu i **nigdy** przez kopię na inne urządzenie.
//
// Gdy kluczyk jest niedostępny (symulator bez entitlementu, uszkodzony wpis),
// `load()` zwraca `nil`, a zapis rzuca błąd — aplikacja wraca na ekran
// logowania zamiast udawać zalogowaną.

struct KeychainError: Error, Equatable {
    let status: OSStatus
    let operation: String
}

final class KeychainMobileSessionStore: MobileSessionStoring, @unchecked Sendable {

    private let service: String
    private let account: String

    init(
        service: String = "pl.kancelaria.emma.session",
        account: String = "mobile-auth-session"
    ) {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() throws -> MobileAuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return try? Self.decoder.decode(MobileAuthSession.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status, operation: "odczyt sesji")
        }
    }

    func save(_ session: MobileAuthSession) throws {
        let data = try Self.encoder.encode(session)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError(status: updateStatus, operation: "aktualizacja sesji")
        }

        var insert = baseQuery
        insert.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError(status: addStatus, operation: "zapis sesji")
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status, operation: "usunięcie sesji")
        }
    }

    /// Ten sam format daty co w kliencie HTTP: `expires_at` musi przetrwać
    /// zapis i odczyt bez zgadywania strefy.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = MobileAuthClient.parseISO8601(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Nieznany format daty w kluczyku: \(raw)"
                )
            }
            return date
        }
        return decoder
    }
}

// MARK: - Tożsamość instalacji
//
// Backend wiąże sesję z instalacją (kontrakt: `installation_id`). Wartość musi
// być stała dla danego urządzenia i aplikacji — inaczej każde logowanie
// tworzyłoby nowe „urządzenie” i lista zaufanych urządzeń byłaby bezużyteczna.
// Nie jest sekretem: to identyfikator, nie uwierzytelnienie.

enum InstallationIdentity {

    static let defaultsKey = "emma.installation.id"

    static func current(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: defaultsKey), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString
        defaults.set(created, forKey: defaultsKey)
        return created
    }
}
