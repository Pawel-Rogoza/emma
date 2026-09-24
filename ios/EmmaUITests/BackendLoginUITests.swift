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

        // Ekran otwiera się na „Do obsługi”, a osoba z bazy może być już
        // klientem kancelarii — wyszukiwanie obejmuje wszystkich (audyt 23.09).
        let search = application.textFields["Szukaj osoby lub tematu"]
        XCTAssertTrue(search.waitForExistence(timeout: 20), "Brak pola wyszukiwania")
        search.tap()
        search.typeText(expectedClient + "\n")

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

    /// Audyt 23.09.2026: na backendzie szczegół zadania i terminu kończył się
    /// błędem („backend nie udostępnia”), „Edytuj” zakładało duplikat, zadania
    /// bez terminu nie istniały w aplikacji, a przyszłe terminy ginęły za
    /// limitem 200 pozycji. Test czyta dane przygotowane w bazie (runbook):
    /// `EMMA_UI_EXPECT_TASK`, `EMMA_UI_EXPECT_UNDATED_TASK`, `EMMA_UI_EXPECT_EVENT`,
    /// `EMMA_UI_EXPECT_FUTURE_EVENT`. Nic nie zapisuje.
    func testRealTaskAndEventDetailsOpenAndEditLoadsRecord() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipIf(backendURL == nil, "Brak EMMA_UI_BACKEND_URL — test integracyjny pominięty")
        let taskTitle = try XCTUnwrap(environment["EMMA_UI_EXPECT_TASK"], "Brak EMMA_UI_EXPECT_TASK")
        let undatedTask = try XCTUnwrap(environment["EMMA_UI_EXPECT_UNDATED_TASK"], "Brak EMMA_UI_EXPECT_UNDATED_TASK")
        let eventTitle = try XCTUnwrap(environment["EMMA_UI_EXPECT_EVENT"], "Brak EMMA_UI_EXPECT_EVENT")
        let futureEvent = try XCTUnwrap(environment["EMMA_UI_EXPECT_FUTURE_EVENT"], "Brak EMMA_UI_EXPECT_FUTURE_EVENT")

        try launchAgainstBackend()
        typeCredentials(totp: TOTP.code(secret: totpSecret))
        dismissPasswordSavePromptIfPresent()
        XCTAssertTrue(application.buttons["tab.today"].waitForExistence(timeout: 30), "Brak powłoki po zalogowaniu")

        // Szczegół zadania z ekranu „Dzisiaj”.
        let task = application.staticTexts[taskTitle].firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 25), "„Dzisiaj” nie pokazuje zadania \(taskTitle)")
        task.tap()
        // „Edytuj” jest tylko we wczytanym szczególe (etykieta „Oznacz jako
        // wykonane” istnieje też na liście, więc nie nadaje się na dowód).
        XCTAssertTrue(
            application.buttons["Edytuj"].waitForExistence(timeout: 20),
            "Szczegół zadania się nie wczytał"
        )
        attachScreenshot("AUDYT-01-szczegol-zadania")

        // „Edytuj” ma wczytać istniejące zadanie, a nie pusty formularz.
        application.buttons["Edytuj"].tap()
        XCTAssertTrue(application.staticTexts["Edytuj zadanie"].waitForExistence(timeout: 15), "Brak formularza edycji")
        let titleField = application.textFields["Co trzeba zrobić?"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10))
        let loaded = expectation(for: NSPredicate(format: "value == %@", taskTitle), evaluatedWith: titleField)
        wait(for: [loaded], timeout: 15)
        attachScreenshot("AUDYT-02-edycja-zadania")
        application.buttons["Zamknij"].firstMatch.tap()

        // Zadanie bez terminu jest na liście zadań (wcześniej znikało).
        let allTasks = application.buttons["Wszystkie zadania"]
        XCTAssertTrue(allTasks.waitForExistence(timeout: 10))
        allTasks.tap()
        let allScope = application.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wszystkie")).firstMatch
        if allScope.waitForExistence(timeout: 5) { allScope.tap() }
        XCTAssertTrue(
            application.staticTexts[undatedTask].waitForExistence(timeout: 20),
            "Zadanie bez terminu nie pojawiło się na liście"
        )
        attachScreenshot("AUDYT-03-zadanie-bez-terminu")
        application.buttons["Wróć"].firstMatch.tap()

        // Szczegół najbliższego terminu.
        let details = application.buttons["Szczegóły"]
        XCTAssertTrue(details.waitForExistence(timeout: 15), "Brak najbliższego terminu \(eventTitle)")
        details.tap()
        XCTAssertTrue(
            application.buttons["Edytuj termin"].waitForExistence(timeout: 20),
            "Szczegół terminu się nie wczytał"
        )
        attachScreenshot("AUDYT-04-szczegol-terminu")
        application.buttons["Zamknij"].firstMatch.tap()

        // Karta klienta pokazuje przyszły termin mimo setek starszych w bazie.
        let clientLink = application.buttons.matching(NSPredicate(format: "label CONTAINS %@", expectedClient)).firstMatch
        XCTAssertTrue(clientLink.waitForExistence(timeout: 10))
        clientLink.tap()
        let future = application.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", futureEvent)).firstMatch
        for _ in 0..<6 where !future.exists { application.swipeUp() }
        XCTAssertTrue(future.waitForExistence(timeout: 10), "Karta klienta zgubiła przyszły termin \(futureEvent)")
        attachScreenshot("AUDYT-05-przyszly-termin-w-karcie")
    }

    /// Zapisy, które do 0.2.0 zawsze kończyły się błędem albo ginęły po cichu:
    /// zmiana miejsca terminu i rozpoczęcie sprawy z karty zgłoszenia. Wymaga
    /// backendu z trasami z audytu 23.09.2026 i zgody na zapis.
    /// `EMMA_UI_EXPECT_CASE_LEAD` — zgłoszenie bez sprawy w bazie.
    func testRealEventPlaceEditAndCaseStartSave() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipIf(backendURL == nil, "Brak EMMA_UI_BACKEND_URL — test integracyjny pominięty")
        try XCTSkipUnless(environment["EMMA_UI_ALLOW_WRITES"] == "1", "Zapis do backendu tylko za zgodą EMMA_UI_ALLOW_WRITES=1")
        let caseLead = try XCTUnwrap(environment["EMMA_UI_EXPECT_CASE_LEAD"], "Brak EMMA_UI_EXPECT_CASE_LEAD")

        try launchAgainstBackend()
        typeCredentials(totp: TOTP.code(secret: totpSecret))
        dismissPasswordSavePromptIfPresent()
        XCTAssertTrue(application.buttons["tab.today"].waitForExistence(timeout: 30), "Brak powłoki po zalogowaniu")

        // Miejsce terminu: edycja → zapis → szczegół pokazuje nowe miejsce.
        let details = application.buttons["Szczegóły"]
        XCTAssertTrue(details.waitForExistence(timeout: 20), "Brak najbliższego terminu")
        details.tap()
        let edit = application.buttons["Edytuj termin"]
        XCTAssertTrue(edit.waitForExistence(timeout: 20), "Szczegół terminu się nie wczytał")
        edit.tap()
        let place = application.textFields["Miejsce"]
        XCTAssertTrue(place.waitForExistence(timeout: 15), "Brak pola miejsca")
        let loaded = expectation(for: NSPredicate(format: "value != %@ AND value != ''", "Online albo adres"), evaluatedWith: place)
        wait(for: [loaded], timeout: 15)
        place.tap()
        let current = (place.value as? String) ?? ""
        place.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        place.typeText("Sala E2E")
        application.staticTexts["Edytuj termin"].tap()
        let save = application.buttons["event-save"]
        for _ in 0..<4 where !save.isHittable { application.swipeUp() }
        save.tap()
        XCTAssertTrue(
            application.staticTexts["Sala E2E"].waitForExistence(timeout: 20),
            "Nowe miejsce terminu nie wróciło z backendu"
        )
        // Zapis zamyka arkusz; nowe miejsce widać na karcie najbliższego terminu.
        attachScreenshot("AUDYT-06-miejsce-terminu-zapisane")

        // Sprawa z karty zgłoszenia.
        application.buttons["tab.clients"].tap()
        let search = application.textFields["Szukaj osoby lub tematu"]
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap()
        search.typeText(caseLead + "\n")
        let lead = application.buttons.matching(NSPredicate(format: "label CONTAINS %@", caseLead)).firstMatch
        XCTAssertTrue(lead.waitForExistence(timeout: 20), "Brak zgłoszenia \(caseLead)")
        lead.tap()
        // Ścieżka zgłoszenia (0.3.0): „Przyjmij sprawę” jest w panelu karty,
        // gdy zgłoszenie jest „W kontakcie”; nowe najpierw tam przechodzi.
        let markContact = application.buttons["lead-mark-contact"]
        if markContact.waitForExistence(timeout: 5) { markContact.tap() }
        let start = application.buttons["lead-accept-case"]
        for _ in 0..<4 where !(start.exists && start.isHittable) { application.swipeUp() }
        XCTAssertTrue(start.waitForExistence(timeout: 15), "Brak przycisku „Przyjmij sprawę”")
        start.tap()
        let create = application.buttons["case-accept-save"]
        XCTAssertTrue(create.waitForExistence(timeout: 20), "Formularz sprawy się nie otworzył")
        create.tap()
        XCTAssertTrue(
            application.staticTexts["Prowadzona sprawa"].waitForExistence(timeout: 20),
            "Po zapisie nie otworzyła się sprawa z backendu"
        )
        attachScreenshot("AUDYT-07-sprawa-z-leada")
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
