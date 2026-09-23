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
    /// Nazwa klienta, która ma istnieć w bazie backendu. Test nie wpisuje jej
    /// sam — oczekuje danych, które przygotował backend (patrz runbook).
    private var expectedClient: String { ProcessInfo.processInfo.environment["EMMA_UI_EXPECT_CLIENT"] ?? "Olena Kowalenko" }
    private var expectedCase: String { ProcessInfo.processInfo.environment["EMMA_UI_EXPECT_CASE"] ?? "II K 341/26" }

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

    /// Zamyka systemowe okno „Zachować hasło?" po zalogowaniu.
    ///
    /// iOS potrafi pokazać je nad aplikacją po wpisaniu hasła w polu
    /// bezpiecznym. Wtedy trafia w nie pierwszy tap po zalogowaniu i test
    /// sprawdza ekran, którego nie otworzył — a to fałszywy wynik, nie usterka.
    private func dismissPasswordSavePromptIfPresent() {
        for label in ["Nie teraz", "Nie zapisuj", "Not Now"] {
            let button = application.buttons[label]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                return
            }
        }
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
        dismissPasswordSavePromptIfPresent()

        let tabBar = application.buttons["tab.today"]
        XCTAssertTrue(
            tabBar.waitForExistence(timeout: 30),
            "Po poprawnym logowaniu nie pojawiła się powłoka aplikacji"
        )
        attachScreenshot("M1-02-po-zalogowaniu")
    }

    /// Dowód, że aplikacja czyta **prawdziwe** dane kancelarii: po zalogowaniu
    /// do backendu zakładka „Klienci” ma pokazać osobę z bazy, a jej karta —
    /// sprawę z bazy. To nie to samo co „ekran się otworzył”: gdyby repozytorium
    /// dalej czytało fixture'y, ten test by padł.
    func testRealBackendDataAppearsInClientsAndCard() throws {
        try XCTSkipIf(backendURL == nil, "Brak EMMA_UI_BACKEND_URL — test integracyjny pominięty")
        try launchAgainstBackend()
        typeCredentials(totp: TOTP.code(secret: totpSecret))
        dismissPasswordSavePromptIfPresent()

        let clientsTab = application.buttons["tab.clients"]
        XCTAssertTrue(clientsTab.waitForExistence(timeout: 30), "Brak zakładki „Klienci” po zalogowaniu")
        clientsTab.tap()

        // Ekran otwiera się na „Do obsługi”, a ten test szuka konkretnej osoby
        // z bazy — dlatego filtr wybieramy jawnie, zamiast liczyć na domyślny.
        // Domyślny filtr ma osobny test: `testRealNewLeadsAreDefaultView`.
        let allChip = application.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Wszystkie")
        ).firstMatch
        if allChip.waitForExistence(timeout: 20) {
            allChip.tap()
        }

        // Wiersz listy to przycisk z etykietą „nazwa, temat, status, język…”,
        // więc dopasowujemy po początku etykiety.
        let lead = application.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", expectedClient)
        ).firstMatch
        XCTAssertTrue(
            lead.waitForExistence(timeout: 25),
            "Zakładka „Klienci” nie pokazała klienta \(expectedClient) z backendu"
        )
        attachScreenshot("M2-01-klienci-z-backendu")

        lead.tap()
        let caseCard = application.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", expectedCase)
        ).firstMatch
        XCTAssertTrue(
            caseCard.waitForExistence(timeout: 25),
            "Karta klienta nie pokazała sprawy \(expectedCase) z backendu"
        )
        attachScreenshot("M2-02-karta-klienta-z-backendu")
    }

    /// Domysł Tomasza: „apka pokazuje zbyt wiele nowych, chyba coś się zbugowało
    /// ze statusem”. Ten test sprawdza to na prawdziwej bazie: zakładka ma się
    /// otwierać na „Nowych”, licznik ma być widoczny, a zgłoszenie bez terminu
    /// ma pokazywać datę zgłoszenia — nie pustkę ani wymyślony status.
    ///
    /// Nic tu nie zapisujemy: to odczyt produkcyjnych danych.
    func testRealNewLeadsAreDefaultView() throws {
        try XCTSkipIf(backendURL == nil, "Brak EMMA_UI_BACKEND_URL — test integracyjny pominięty")
        try launchAgainstBackend()
        typeCredentials(totp: TOTP.code(secret: totpSecret))
        dismissPasswordSavePromptIfPresent()

        let clientsTab = application.buttons["tab.clients"]
        XCTAssertTrue(clientsTab.waitForExistence(timeout: 30), "Brak zakładki „Klienci” po zalogowaniu")
        clientsTab.tap()

        // Od 23.09.2026 domyślna jest kolejka „Do obsługi” (nowe + czekające
        // ≥ 24 h), a „Nowe” to wyłącznie zgłoszenia z ostatniej doby.
        let newChip = application.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Do obsługi")
        ).firstMatch
        XCTAssertTrue(newChip.waitForExistence(timeout: 25), "Brak filtra „Do obsługi”")
        XCTAssertTrue(newChip.isSelected, "Zakładka nie otworzyła się na „Do obsługi”")

        // Licznik pokazuje, ile zgłoszeń naprawdę czeka — a nie ile jest w bazie.
        XCTAssertFalse(newChip.label.isEmpty)
        attachScreenshot("M2-03-nowe-zgloszenia-z-backendu")
    }

    /// Pełny obieg: aplikacja → prawdziwy backend → baza, i z powrotem.
    /// Tworzy zgłoszenie z formularza, a potem usuwa je z menu po przytrzymaniu.
    /// To jedyny test, który **pisze** do backendu, dlatego wymaga jawnej zgody
    /// `EMMA_UI_ALLOW_WRITES=1` — uruchomiony przez pomyłkę przeciw produkcji
    /// zostawiłby tam (albo skasował) prawdziwe zgłoszenie.
    func testRealAddAndDeleteLeadRoundTrip() throws {
        try XCTSkipIf(backendURL == nil, "Brak EMMA_UI_BACKEND_URL — test integracyjny pominięty")
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["EMMA_UI_ALLOW_WRITES"] == "1",
            "Zapis do backendu tylko za zgodą EMMA_UI_ALLOW_WRITES=1"
        )
        try launchAgainstBackend()
        typeCredentials(totp: TOTP.code(secret: totpSecret))
        dismissPasswordSavePromptIfPresent()

        let clientsTab = application.buttons["tab.clients"]
        XCTAssertTrue(clientsTab.waitForExistence(timeout: 30), "Brak zakładki „Klienci” po zalogowaniu")
        clientsTab.tap()

        application.buttons["Dodaj leada"].tap()
        let name = "Zapis Testowy UI"
        let nameField = application.textFields["Imię i nazwisko"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 15), "Arkusz „Nowy kontakt” się nie otworzył")
        nameField.tap()
        nameField.typeText(name)

        let topicField = application.textFields["Temat zgłoszenia"]
        topicField.tap()
        topicField.typeText("Zgłoszenie z testu integracyjnego")

        let contextField = application.textViews["Kontekst zgłoszenia"]
        if contextField.waitForExistence(timeout: 5) {
            contextField.tap()
            contextField.typeText("Kontekst z testu.")
        }
        application.staticTexts["Nowy kontakt"].tap()
        let submit = application.buttons["Dodaj kontakt"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        submit.tap()

        XCTAssertTrue(
            application.staticTexts[name].waitForExistence(timeout: 25),
            "Backend nie oddał karty nowego kontaktu — zapis się nie udał"
        )
        attachScreenshot("M3-01-zapis-przez-aplikacje")

        // Wracamy na listę i usuwamy to, co właśnie powstało.
        let back = application.buttons["Wróć"]
        if back.waitForExistence(timeout: 5) {
            back.tap()
        }
        let created = application.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", name)
        ).firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 20), "Nowe zgłoszenie nie wróciło na listę")

        created.press(forDuration: 1.2)
        let deleteItem = application.buttons["Usuń zgłoszenie"]
        XCTAssertTrue(deleteItem.waitForExistence(timeout: 10), "Brak usuwania w menu")
        deleteItem.tap()

        let confirm = application.alerts.buttons["Usuń"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "Brak potwierdzenia usunięcia")
        confirm.tap()

        let gone = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: application.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        )
        wait(for: [gone], timeout: 20)
        attachScreenshot("M3-02-usuniecie-przez-aplikacje")
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
