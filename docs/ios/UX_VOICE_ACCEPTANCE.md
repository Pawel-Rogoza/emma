# Macierz akceptacji §8 — stan po etapie 6

Dokument spina tabelę testów regresji z §8 audytu (`UX_VOICE_AUDIT_2026-09-13.md`)
z **konkretnymi testami** w repozytorium. Powstał, żeby dało się sprawdzić, co jest
udowodnione, a co nie — bez czytania całego kodu.

Legenda: **POKRYTE** — istnieje test asertujący oczekiwany rezultat; **CZĘŚCIOWO** —
testy pokrywają tylko wykonalny fragment; **NIEWERYFIKOWALNE** — wymaga urządzenia
lub usług, których w tym środowisku nie ma (patrz koniec dokumentu).

| # | Scenariusz (§8) | Status | Dowód |
| --- | --- | --- | --- |
| 1 | Wybór dnia, następnego tygodnia, odświeżenie | POKRYTE | `EmmaTests/App/Stage6AcceptanceTests.swift::testFormInheritsTheSelectedDayFromTheWeekStrip` (arkusz nowego terminu dziedziczy wybrany dzień, nie „dzisiaj”), `Stage1ReliabilityTests.swift::testCalendarKeepsSelectedDayAcrossReload` i `::testCalendarKeepsWeekOffsetAcrossReload` (wybór i tydzień przeżywają odświeżenie), `EmmaUITests/Stage6BoundaryUITests.swift::testCaptureStage6EventFormInheritsSelectedDay` + zrzut `docs/ios/screenshots/stage6-2026-09-13/36-termin-dziedziczy-dzien.png` (OCR: `Data · 2026-09-18` po przesunięciu tygodnia) |
| 2 | Wpisanie i usunięcie zapytania w Rozmowach | POKRYTE | `Stage1ReliabilityTests.swift::testClearingConversationSearchRestoresAllRows`, `::testConversationSearchFiltersByNameWithoutLosingRows` |
| 3 | Utrata sieci przy pytaniu o dzień | CZĘŚCIOWO | `EmmaTests/Logic/BriefingIntegrityTests.swift::testCalendarReadFailureIsNamedExplicitly`, `::testBothReadFailuresAreReportedWithoutClaimingFreeDay` (brak fałszywego „Wolny termin”). Realne odcięcie sieci nieweryfikowalne |
| 4 | Edycja wiadomości i natychmiastowe „Wyślij” | POKRYTE | `Stage6AcceptanceTests.swift::testEditedReplySendsTheLatestVersionOnly` (wiadomość: wykonanie wskazuje nowszą wersję, drugie „wyślij” bez drugiego outboxa), `Stage1ReliabilityTests.swift::testImmediateConfirmAfterEditExecutesVisibleText` (zadanie) |
| 5 | Dwie osoby o tym samym imieniu | POKRYTE | `Stage5DialogTests.swift::testAmbiguousRecipientIsResolvedByVoice` (dwa nazwiska w pytaniu, treść zachowana, wybór nazwiskiem wskazuje właściwą osobę) |
| 6 | Przerwanie odczytu propozycji, potem „tak” | POKRYTE | `Stage6AcceptanceTests.swift::testInterruptDisarmsVoiceConsentAndKeepsProposal` (przerwanie rozbraja zgodę, „tak” nie wykonuje, przycisk nadal działa), `VoiceAndActionTests.swift::testVoiceConsentRequiresArmedPresentation`, `::testStalePresentationIsRejected`, `Stage6PlaybackTests.swift::testStopInterruptsPlayback` |
| 7 | „A jakie mam jutro terminy?” w trakcie szkicu | POKRYTE | `Stage6AcceptanceTests.swift::testReturnToDraftAfterReadOnlyQuestionSendsOnce` (szkic ten sam, potem jedno wykonanie), `Stage5DialogTests.swift::testRunBScheduleQuestionKeepsPreparedDraft`, `EmmaUITests/Stage5DialogUITests.swift::testCaptureStage5ReadOnlyQuestionKeepsDraft` |
| 8 | Zmiana zakładki, wejście do arkusza, klawiatura | POKRYTE | `EmmaUITests/Stage4VoicePanelUITests.swift::testMiniPanelAppearsInAnotherTab`, `::testMiniPanelMutesAndEndsSessionFromAnotherTab`, `::testPanelStaysAboveKeyboardInSheet` (panel nad klawiaturą, `isHittable`) |
| 9 | Telefon, odłączenie słuchawek, tło, Face ID | CZĘŚCIOWO | `Stage6AcceptanceTests.swift::testBackgroundingRevokesVoiceWritesAndKeepsDraft` (tło kończy zapisy głosem, szkic zostaje), `VoiceAndActionTests.swift::testRouteChangeFromHeadphonesToSpeakerPausesSensitivePlayback`, `EmmaTests/App/AuthStoreTests.swift::testUnlockSucceedsWithBiometrics`, `::testUnlockFailureKeepsAppLockedAndExplains`. Połączenie telefoniczne, realne wypięcie słuchawek i prawdziwe Face ID — nieweryfikowalne |
| 10 | Powtórzone zdarzenie końcowe / „wyślij” dwa razy | POKRYTE | `Stage5DialogTests.swift::testRunAConfirmationExecutesOnce`, `::testRepeatedTranscriptDoesNotDuplicateTurns`, `VoiceAndActionTests.swift::testDoubleConfirmWithSameVersionIsIdempotent`, `::testUIConfirmAndVoiceConfirmProduceSingleExecution` |
| 11 | Timeout po wysłaniu | POKRYTE | `Stage6AcceptanceTests.swift::testUnknownOutcomeIsReconciledInsteadOfResent` (niepewny wynik → `needsReview`, to samo wykonanie i outbox, brak automatycznego ponowienia), `VoiceAndActionTests.swift::testUnknownOutcomeIsNotRetried`, `::testFailedExecutionMayBeRetriedExplicitly` |
| 12 | Duży tekst, długie nazwisko i cyrylica | CZĘŚCIOWO | Duży tekst: `EmmaUITests/Stage2ScreenshotUITests.swift::testCaptureStage2LargeTextScreens`, `Stage3ScreenshotUITests.swift::testCaptureStage3LargeTextScreens`, `Stage4ScreenshotUITests.swift::testCaptureStage4LargeTextScreens` (+ zrzuty `18-duzy-tekst-rozmowy.png`, `30-duzy-tekst-mini-panel.png`). Cyrylica: `DomainLogicTests.swift::testMatchesCyrillic`. **Brak testu układu z długim nazwiskiem i cyrylicą** — patrz „Luki” |

## Zmiana w kodzie wynikająca z tej macierzy

Wiersz 1 ujawnił prawdziwy błąd: przycisk „Dodaj termin” w nagłówku kalendarza
otwierał formularz z `initialDay: nil`, więc formularz pokazywał **„dzisiaj”**, mimo że
na ekranie zaznaczony był inny dzień. Teraz oba wejścia (nagłówek i „Dodaj termin na ten
dzień”) korzystają z jednego `CalendarStore.newEventRoute`, który zawsze przekazuje
`selectedDay`. Test `testFormInheritsTheSelectedDayFromTheWeekStrip` pilnuje tej reguły, a zrzut
`36-termin-dziedziczy-dzien.png` pokazuje formularz z `Data · 2026-09-18` po przesunięciu
tygodnia (dzień wybrany, nie 11 września). Zrzut i test są dowodem naprawy, nie obietnicą.

## Nieweryfikowalne w tym środowisku

- **Wiersz 9**: połączenie telefoniczne, fizyczne wypięcie słuchawek, prawdziwe Face ID —
  symulator nie generuje tych zdarzeń. Testy używają wstrzykiwanych zdarzeń i mocka
  biometrii, co jest dowodem logiki, nie zachowania systemu.
- **Wiersz 3**: nie ma realnego transportu sieciowego, więc „utrata sieci” jest modelowana
  niepowodzeniem odczytu, a nie odcięciem interfejsu.
- **Wiersze 5–7, 10, 11**: brak dostawcy mowy i STT. „Wypowiedź” to tekst albo zdarzenie
  `MockVoiceTransport`, więc zrozumiałość mowy i akustyczne wejście w słowo nie są
  sprawdzane. Wysyłka kończy się na `MockRepository` — **mock nie jest dowodem
  wysłania WhatsApp** ani doręczenia.
- **Wiersz 12**: VoiceOver i Reduce Motion wymagają urządzenia; testy pokrywają duży tekst
  na symulatorze.

## Luki

1. **Wiersz 12 — układ z długim nazwiskiem i cyrylicą.** Brak fixture z długim nazwiskiem
   w cyrylicy i brak testu, że ramki kluczowych kontrolek się nie przecinają
   (`CGRect.intersects`) oraz że wszystkie decyzje są osiągalne przy `AccessibilityXXXL`.
   Wykonalne w symulatorze; wymaga nowej fixture demo i testu UI.
1b. **Wiersz 9 — realne zdarzenia systemowe pozostają poza zasięgiem** (połączenie,
słuchawki, Face ID): symulator ich nie generuje, więc dowodem jest logika na wstrzykiwanych
zdarzeniach.

2. **Realne usługi (etap 6).** Prawdziwy głos dostawcy, faktycznie odebrana wiadomość
   testowa i prawdziwe stany wysłania/dostarczenia — wymagają kont, backendu i urządzenia;
   opis w `UX_VOICE_STAGES.md` (§ „Czego etap 6 nie zamyka”).
