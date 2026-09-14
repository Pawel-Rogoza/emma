import CryptoKit
import XCTest

// MARK: - Logowanie do prawdziwego backendu (M1)
//
// Ten test nie udaje integracji: uruchamia aplikację w konfiguracji
// `staging` ze wskazanym adresem backendu, wpisuje prawdziwe dane konta
// (hasło + kod TOTP wyliczony lokalnie) i sprawdza, że po odpowiedzi serwera
// aplikacja wchodzi do środka — albo że przy błędnych danych pokazuje komunikat
// z backendu i **nie** wpuszcza dalej.
//
// Wymaga uruchomionego backendu i konta. Bez tego jest pomijany, a nie
// „przechodzi”: w zwykłym przebiegu (Demo, CI bez serwera) nie ma czego
// sprawdzać, więc `XCTSkip` jest uczciwszą odpowiedzią niż zielony wynik.
//
// Zmienne środowiskowe (ustawia je ten, kto uruchamia test):
//   EMMA_UI_BACKEND_URL   np. http://127.0.0.1:4399
//   EMMA_UI_LOGIN_EMAIL
//   EMMA_UI_LOGIN_PASSWORD
//   EMMA_UI_TOTP_SECRET   sekret base32 z ekranu parowania TOTP

final class BackendLoginUITests: XCTestCase {

    private var application: XCUIApplication!

    private var backendURL: String? { ProcessInfo.processInfo.environment["EMMA_UI_BACKEND_URL"] }
    private var email: String { ProcessInfo.processInfo.environment["EMMA_UI_LOGIN_EMAIL"] ?? "" }
    private var password: String { ProcessInfo.processInfo.environment["EMMA_UI_LOGIN_PASSWORD"] ?? "" }
    private var totpSecret: String { ProcessInfo.processInfo.environment["EMMA_UI_TOTP_SECRET"] ?? "" }

    override func setUp() {
        continueAfterFailure = false
        application = XCUIApplication()
    }

    override func tearDown() {
        application = nil
        super.tearDown()
    }

    private func launchAgainstBackend() throws {
        let url = try XCTUnwrap(backendURL)
        // Adres i środowisko podajemy argumentem startowym: dzięki temu test
        // działa na tym samym buildzie Demo, bez osobnego archiwum.
        application.launchArguments = [
            "-EMMAEnvironment", "staging",
            "-EMMAApiBaseURL", url,
            "--reset-auth",
        ]
        application.launch()
        XCTAssertTrue(
            application.staticTexts["Zaloguj się"].waitForExistence(timeout: 20),
            "Ekran logowania nie pojawił się"
        )
    }

    private func typeCredentials(totp: String) {
        let emailField = application.textFields["imie@kancelaria.pl"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Brak pola e-mail")
        emailField.tap()
        emailField.typeText(email)

        let passwordField = application.secureTextFields["Hasło"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5), "Brak pola hasła")
        passwordField.tap()
        passwordField.typeText(password)

        if !totp.isEmpty {
            let totpField = application.textFields["6 cyfr"]
            XCTAssertTrue(totpField.waitForExistence(timeout: 5), "Brak pola kodu jednorazowego")
            totpField.tap()
            totpField.typeText(totp)
        }

        application.buttons["Zaloguj się"].tap()
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: Testy

    func testRealLoginReachesApp() throws {
        try XCTSkipIf(backendURL == nil, "Brak EMMA_UI_BACKEND_URL — test integracyjny pominięty")
        try launchAgainstBackend()
        // Uwaga na zrzut: ekran sam ustawia fokus na polu e-mail, więc dolna
        // część formularza jest zasłonięta klawiaturą. Pełny formularz — razem
        // z polem kodu jednorazowego — widać na zrzucie M1-03.
        attachScreenshot("M1-01-ekran-logowania")

        typeCredentials(totp: TOTP.code(secret: totpSecret))

        let tabBar = application.buttons["tab.today"]
        XCTAssertTrue(
            tabBar.waitForExistence(timeout: 30),
            "Po poprawnym logowaniu nie pojawiła się powłoka aplikacji"
        )
        attachScreenshot("M1-02-po-zalogowaniu")
    }

    func testWrongPasswordShowsServerMessageAndStaysOnLogin() throws {
        try XCTSkipIf(backendURL == nil, "Brak EMMA_UI_BACKEND_URL — test integracyjny pominięty")
        try launchAgainstBackend()

        application.textFields["imie@kancelaria.pl"].tap()
        application.textFields["imie@kancelaria.pl"].typeText(email)
        application.secureTextFields["Hasło"].tap()
        application.secureTextFields["Hasło"].typeText("zupelnie-zle-haslo")
        application.buttons["Zaloguj się"].tap()

        let message = application.staticTexts["Nieprawidłowe dane logowania."]
        XCTAssertTrue(
            message.waitForExistence(timeout: 20),
            "Brak komunikatu z backendu — błąd logowania został ukryty"
        )
        XCTAssertFalse(application.buttons["tab.today"].exists, "Błędne hasło nie może wpuszczać do aplikacji")
        attachScreenshot("M1-03-bledne-haslo")
    }
}

// MARK: - TOTP dla testu
//
// Liczymy kod w teście, a nie w aplikacji: aplikacja nie ma prawa znać sekretu
// TOTP, a test musi umieć przedstawić aktualny kod.

enum TOTP {

    static func code(secret: String, at date: Date = Date(), period: TimeInterval = 30) -> String {
        guard let key = base32Decode(secret) else { return "" }
        let counter = UInt64(date.timeIntervalSince1970 / period)
        var bigEndian = counter.bigEndian
        let message = Data(bytes: &bigEndian, count: MemoryLayout<UInt64>.size)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: key))
        let bytes = Array(mac)
        let offset = Int(bytes[19] & 0x0f)
        let value = (UInt32(bytes[offset] & 0x7f) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
        return String(format: "%06d", value % 1_000_000)
    }

    static func base32Decode(_ input: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var buffer = 0
        var bitsLeft = 0
        var output = Data()
        for character in input.uppercased() where character != "=" {
            guard let index = alphabet.firstIndex(of: character) else { return nil }
            buffer = (buffer << 5) | index
            bitsLeft += 5
            if bitsLeft >= 8 {
                output.append(UInt8((buffer >> (bitsLeft - 8)) & 0xff))
                bitsLeft -= 8
            }
        }
        return output.isEmpty ? nil : output
    }
}
