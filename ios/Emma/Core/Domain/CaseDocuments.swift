import Foundation

// MARK: - Akta sprawy
//
// Skan wezwania, zdjęcie postanowienia, PDF od klienta — te same akta, które
// panel kancelarii pokazuje w zakładce sprawy (tabela `files`, foldery,
// statusy pism). Aplikacja dokłada do nich telefon: aparat skanuje kartki
// do jednego PDF, a plik trafia do akt jednym dotknięciem.

/// Folder akt — te same nazwy co w panelu.
public enum CaseDocumentFolder: String, CaseIterable, Identifiable, Sendable {
    case documents = "Dokumenty"
    case evidence = "Dowody"
    case filings = "Pisma"
    case billing = "Rozliczenia"
    case other = "Inne"

    public var id: String { rawValue }
}

public struct CaseDocument: Identifiable, Hashable, Sendable {
    public let id: String
    public let caseID: CaseID
    public let name: String
    public let mime: String
    public let size: Int
    public let folder: String
    /// Status pisma z panelu (`zlozony`, `otrzymany`…) albo `nil`.
    public let status: String?
    public let uploadedAt: Date
    public let uploadedBy: String?

    public init(
        id: String,
        caseID: CaseID,
        name: String,
        mime: String,
        size: Int,
        folder: String,
        status: String?,
        uploadedAt: Date,
        uploadedBy: String?
    ) {
        self.id = id
        self.caseID = caseID
        self.name = name
        self.mime = mime
        self.size = size
        self.folder = folder
        self.status = status
        self.uploadedAt = uploadedAt
        self.uploadedBy = uploadedBy
    }

    public var systemImage: String {
        if mime == "application/pdf" { return "doc.richtext" }
        if mime.hasPrefix("image/") { return "photo" }
        return "doc.text"
    }

    /// „Złożony”, „Otrzymany” — etykieta statusu pisma z panelu.
    public var statusLabel: String? {
        switch status {
        case "roboczy": return "Roboczy"
        case "do_akceptacji": return "Do akceptacji"
        case "podpisany": return "Podpisany"
        case "wyslany": return "Wysłany"
        case "zlozony": return "Złożony"
        case "otrzymany": return "Otrzymany"
        case "archiwalny": return "Archiwalny"
        default: return nil
        }
    }

    /// „1,2 MB”, „340 KB”.
    public var sizeText: String {
        if size >= 1_000_000 {
            let tenths = (size + 50_000) / 100_000
            return "\(tenths / 10),\(tenths % 10) MB"
        }
        return "\(max(1, (size + 500) / 1000)) KB"
    }

    /// Rozszerzenie pliku do podglądu (QuickLook rozpoznaje typ po nazwie).
    public var fileExtension: String {
        let fromName = (name as NSString).pathExtension.lowercased()
        if !fromName.isEmpty { return fromName }
        switch mime {
        case "application/pdf": return "pdf"
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/heic": return "heic"
        default: return "bin"
        }
    }
}

/// Akta sprawy po stronie danych. Osobny port, bo nie każde źródło je ma
/// (dane demo trzymają akta w pamięci, a starszy serwer — wcale).
public protocol CaseDocumentsRepository: Sendable {
    func caseDocuments(caseID: CaseID) async throws -> [CaseDocument]
    func uploadCaseDocument(
        caseID: CaseID,
        fileName: String,
        mime: String,
        data: Data,
        folder: CaseDocumentFolder
    ) async throws -> CaseDocument
    func documentData(id: String) async throws -> Data
}

public enum CaseDocumentNaming {

    /// „Skan 2026-10-01 22.45.pdf”, a z tytułem: „Wezwanie 2026-10-01.pdf”.
    /// Bez znaków, których nie lubią systemy plików i panel.
    public static func scanFileName(title: String?, at date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let cleaned = (title ?? "")
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return "Skan \(day) \(String(format: "%02d.%02d", parts.hour ?? 0, parts.minute ?? 0)).pdf"
        }
        return "\(String(cleaned.prefix(80))) \(day).pdf"
    }
}

/// Ciało `multipart/form-data` dla wysyłki pliku. Czysta funkcja, żeby
/// format dało się sprawdzić testem, a nie dopiero na serwerze.
public struct MultipartForm: Sendable {
    public let boundary: String
    private var body = Data()

    public init(boundary: String = "emma-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public mutating func addField(_ name: String, _ value: String) {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        body.append(Data("\(value)\r\n".utf8))
    }

    public mutating func addFile(_ name: String, fileName: String, mime: String, data: Data) {
        // Cudzysłów i znaki nowej linii w nazwie złamałyby nagłówek.
        let safeName = fileName.replacingOccurrences(of: "\"", with: "'")
            .components(separatedBy: .newlines).joined(separator: " ")
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(safeName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mime)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    public func finished() -> Data {
        var result = body
        result.append(Data("--\(boundary)--\r\n".utf8))
        return result
    }
}
