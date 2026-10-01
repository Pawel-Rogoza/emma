import XCTest
@testable import Emma

/// Akta sprawy: skan do PDF, wysyłka multipart, lista z panelu.
final class CaseDocumentsTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }

    func testScanNameCarriesDateAndDropsCharactersFilesystemsHate() {
        let date = ISO8601DateFormatter().date(from: "2026-10-01T20:45:00Z")!
        XCTAssertEqual(CaseDocumentNaming.scanFileName(title: nil, at: date, calendar: calendar), "Skan 2026-10-01 22.45.pdf")
        XCTAssertEqual(
            CaseDocumentNaming.scanFileName(title: "Wezwanie/II K 12:26", at: date, calendar: calendar),
            "Wezwanie II K 12 26 2026-10-01.pdf"
        )
    }

    func testMultipartBodyHasFieldFileAndClosingBoundary() {
        var form = MultipartForm(boundary: "B")
        form.addField("folder", "Pisma")
        form.addFile("files", fileName: "we\"zwanie.pdf", mime: "application/pdf", data: Data("%PDF".utf8))
        let body = String(decoding: form.finished(), as: UTF8.self)
        XCTAssertEqual(form.contentType, "multipart/form-data; boundary=B")
        XCTAssertEqual(
            body,
            "--B\r\nContent-Disposition: form-data; name=\"folder\"\r\n\r\nPisma\r\n"
                + "--B\r\nContent-Disposition: form-data; name=\"files\"; filename=\"we'zwanie.pdf\"\r\n"
                + "Content-Type: application/pdf\r\n\r\n%PDF\r\n--B--\r\n"
        )
    }

    func testDocumentLabels() {
        let document = CaseDocument(
            id: "file-1", caseID: CaseID("case-1"), name: "postanowienie", mime: "application/pdf",
            size: 1_250_000, folder: "Pisma", status: "zlozony", uploadedAt: Date(), uploadedBy: nil
        )
        XCTAssertEqual(document.sizeText, "1,3 MB")
        XCTAssertEqual(document.statusLabel, "Złożony")
        XCTAssertEqual(document.fileExtension, "pdf")
        XCTAssertEqual(document.systemImage, "doc.richtext")
    }

    func testBackendDocumentMapping() throws {
        let json = Data("""
        {"id":"file-7","case_id":"case-3","name":"wezwanie.pdf","mime":"application/pdf","size":1200,
         "folder":"Pisma","status":null,"uploaded_at":"2026-10-01T20:45:00.000Z","uploaded_by":"Paweł Rogoża"}
        """.utf8)
        let dto = try JSONDecoder().decode(BackendDocumentDTO.self, from: json)
        let document = try BackendRepository.document(from: dto)
        XCTAssertEqual(document.caseID, CaseID("case-3"))
        XCTAssertEqual(document.folder, "Pisma")
        XCTAssertEqual(document.uploadedBy, "Paweł Rogoża")
        XCTAssertNil(document.statusLabel)
    }

    func testDemoRepositoryKeepsScansInMemory() async throws {
        let repository = MockRepository(dataset: DemoFixtures.dataset(), clock: DemoClock(), artificialLatency: 0)
        let saved = try await repository.uploadCaseDocument(
            caseID: CaseID("case-1"), fileName: "skan.pdf", mime: "application/pdf", data: Data("%PDF".utf8), folder: .filings
        )
        let listed = try await repository.caseDocuments(caseID: CaseID("case-1"))
        XCTAssertEqual(listed.map(\.id), [saved.id])
        let data = try await repository.documentData(id: saved.id)
        XCTAssertEqual(data, Data("%PDF".utf8))
    }
}
