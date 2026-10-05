# Emma — przegląd rynku, potrzeby kancelarii i kierunek rozwoju (10.2026)

Perspektywa: kancelaria karna i cudzoziemska, klienci rosyjskojęzyczni,
kontakt głównie przez WhatsApp. Emma to telefon adwokata, nie panel biura —
liczy się „zrobione jednym dotknięciem”, a nie liczba modułów.

## 1. Gdzie Emma jest wobec rynku

**Rynek 2026.** Clio (Duo/Manage AI) i MyCase sprzedają ten sam rdzeń:
przyjmowanie zgłoszeń z formularzem i kontrolą konfliktu interesów,
pipeline leadów, terminy wyciągane z dokumentów do kalendarza, szkice
wiadomości do klienta, rejestr czasu i faktury, portal klienta, aplikacja
mobilna do „czasu w drodze”. W Polsce: LEX (Wolters Kluwer, w tym LegalDesk
z KSeF), Officium365, AppLex, LEX AI, a dla przyjmowania telefonów —
asystenci AI typu TuAsystent. Trend roku: AI przyjmuje zgłoszenie 24/7,
ale **nie udziela porady** — zbiera fakty i oddaje prawnikowi.

**Liczby, które mają znaczenie dla leadów:** kancelarie nie odbierają ok. 35%
połączeń w godzinach pracy i 60%+ po godzinach; większość klientów wybiera
kancelarię, która odezwie się pierwsza; odpowiedź w 5 minut daje kilkukrotnie
wyższą konwersję niż po godzinie.

| Obszar | Emma dziś | Rynek | Ocena |
|---|---|---|---|
| Skrzynka WhatsApp z kontekstem sprawy | jest (1:1, 24 h, szkic od Emmy, PL/RU) | rzadkość — zwykle SMS/e-mail | **przewaga** |
| Asystent głosowy z dostępem do CRM | jest (Gemini Live, karty akcji) | Clio Duo — tekstowo | **przewaga** |
| Terminy procesowe, areszt, legalny pobyt | kalkulator k.p.k., liczniki, powiadomienia | ogólne kalendarze | **przewaga** |
| Lead → konsultacja → sprawa | jest (rezerwacja, BLIK, gotowa odpowiedź) | standard | na poziomie |
| Powiadomienia push | **brak** (tylko lokalne przypomnienia) | standard | luka krytyczna |
| Wiadomość po 24 h (szablony WhatsApp) | **brak** — odsyła do aplikacji WhatsApp | standard (SMS) | luka |
| Rejestr czasu, rozliczenia, faktury | jest w panelu CRM, **nie ma w telefonie** | standard | luka |
| Dokumenty z szablonów, podpis | 8 szablonów w CRM, **nie ma w telefonie** | standard | luka |
| Doręczenia (Portal Informacyjny, e-Doręczenia) | brak | brak (to polska specyfika) | **okazja** |
| MOS dla cudzoziemców | brak | brak | **okazja** |
| Tryb ciemny, widżet | brak (decyzje właściciela) | standard | porządek |

## 2. Co zmieniło się w otoczeniu kancelarii (2026)

- **MOS 2.0 od 27.04.2026** — wnioski o pobyt czasowy, stały i rezydenta UE
  wyłącznie elektronicznie; papierowe są pozostawiane bez rozpoznania.
  Potrzebny Profil Zaufany cudzoziemca, aktualne zdjęcie cyfrowe, skany
  wszystkich stron paszportu, dowód opłaty; złożenie tylko z terytorium RP.
  Dla kancelarii cudzoziemskiej to codzienna lista braków do zebrania
  od klienta — dziś „na WhatsAppie i w głowie”.
- **Portal Informacyjny 3.0 od 1.03.2026** — pisma procesowe (cywilne)
  składane elektronicznie; doręczenia przez Portal mają skutek doręczenia
  procesowego: termin biegnie niezależnie od tego, czy adwokat przeczytał
  pismo. Od 1.06.2026 krąg adresatów doręczeń się poszerzył.
- **e-Doręczenia** — adwokaci mają obowiązek posiadania adresu (ADE);
  od 2026 korespondencja z urzędów (np. wojewody) trafia tam, a nie listem.
- **KSeF** — od 1.04.2026 faktury ustrukturyzowane dla pozostałych
  podatników; do 31.12.2026 można wystawiać poza KSeF, dopóki miesięczna
  sprzedaż na fakturach nie przekroczy 10 000 zł (po przekroczeniu — już
  na stałe w KSeF). Od 2027 bez tej furtki.
- **WhatsApp** — wiadomość szablonowa „utility” (przypomnienie o terminie,
  potwierdzenie, prośba o dokument) kosztuje w Polsce ok. 0,01 € i działa
  także po 24 h. Od 1.10.2026 jest płatna również w oknie 24 h.

## 3. Potrzeby kancelarii — co boli najbardziej

1. **Pierwsza minuta zgłoszenia.** Lead z WhatsAppa albo strony w nocy czeka
   do rana; telefon nie dzwoni, bo nie ma push.
2. **Klient milczy ponad dobę** — z Emmy nie da się do niego napisać.
3. **Dokumenty od cudzoziemca** (paszport, zdjęcie, umowa najmu, ZUS) przychodzą
   w WhatsAppie, gubią się, nikt nie wie, czego brakuje do MOS.
4. **Doręczenie, którego nikt nie otworzył,** a termin już biegnie.
5. **Pieniądze:** kto zapłacił BLIK za konsultację, czego nie zafakturowano,
   ile godzin poszło na sprawę — wszystko w panelu, nic w telefonie.

## 4. Kierunek rozwoju — w kolejności opłacalności

### Etap 1 — „nic nie umyka” (1–2 tygodnie)

| # | Co | Dlaczego | Zależności |
|---|---|---|---|
| 1 | **Push o nowym leadzie i wiadomości WhatsApp** (APNs) | luka nr 1; trasa `POST /devices`, wysyłka z webhooka | właściciel: Push w App ID, profil, klucz `.p8` |
| 2 | **Szablony WhatsApp**: potwierdzenie zgłoszenia (auto, w 1 min, PL/RU), przypomnienie dzień przed konsultacją, prośba o płatność/dokument; w wątku po 24 h przycisk „Wyślij szablon” zamiast „idź do WhatsAppa” | odpowiedź w 5 min i kontakt po 24 h; ~0,01 € za wiadomość | zatwierdzenie szablonów w Meta (Dualhook) |
| 3 | `/threads`: `waiting_since` i ostatnia wiadomość z ptaszkami | lista rozmów bez pobierania wiadomości wątków (dokończenie audytu 05.10) | backend |
| 4 | **Podgląd zdjęć i PDF z WhatsAppa** w wątku + „Dołącz do akt” jako prawdziwy plik | dokumenty klienta lądują w aktach, a nie tylko w notatce | decyzja: relay mediów przez Dualhook (`research/whatsapp-partnerzy-i-koszty.md` §9) |
| 5 | „Jak poszło?” → **wpis czasu** (30/60/90 min jednym dotknięciem) | rejestr czasu już jest w CRM; dziś nikt go nie uzupełnia z telefonu | trasa mobilna do `time_entries` |

### Etap 2 — „sprawy cudzoziemskie i doręczenia” (miesiąc)

| # | Co | Dlaczego |
|---|---|---|
| 6 | **Lista MOS na sprawie pobytowej**: Profil Zaufany, zdjęcie, paszport (wszystkie strony), opłata, załączniki pracodawcy — odhaczane, z „Poproś klienta” (szablon WhatsApp w jego języku) i plikiem z wątku podpiętym pod pozycję | najczęstsza czynność kancelarii od 27.04.2026; Emma zna rodzaj i etap sprawy (0.10.0) |
| 7 | **Skrzynka „Doręczenia”**: wpis doręczenia (Portal / e-Doręczenia / list) z datą → kalkulator terminu → termin w sprawie; poranny skrót przypomina o zajrzeniu do Portalu | przegapione doręczenie to przegapiony termin; kalkulator już jest |
| 8 | **Pieniądze w telefonie**: nieopłacone konsultacje, „oznacz jako zapłacone BLIK”, suma miesiąca | moduł finansów i ustawienia BLIK są w CRM |
| 9 | Tryb ciemny | adwokat czyta akta wieczorem; decyzja o bramce tokenów |

### Etap 3 — „kancelaria, która pracuje w nocy” (kwartał)

| # | Co | Uwagi |
|---|---|---|
| 10 | **Przyjmowanie zgłoszeń po godzinach na WhatsAppie**: Emma zadaje 3–4 pytania (co się stało, gdzie, kiedy, czy ktoś zatrzymany), tworzy leada z podsumowaniem i pilnością, proponuje termin konsultacji | twarda zasada: **żadnej porady prawnej**; jawna informacja, że pisze asystent; PL/RU |
| 11 | **Faktura KSeF z telefonu** po opłaconej konsultacji | przed 1.01.2027 (koniec furtki 10 000 zł); integracja z programem księgowym albo LegalDesk zamiast własnego klienta KSeF |
| 12 | **Pełnomocnictwo i umowa z szablonu** → PDF → WhatsApp | 8 szablonów w CRM; podpis — na początek odręczny skan zwrotny |
| 13 | **Notatka z konsultacji głosem**: Emma słucha (za zgodą klienta), robi notatkę, zadania i terminy do zatwierdzenia | karty akcji już są; koszt Gemini w limicie miesięcznym |
| 14 | Widżet / Live Activity „Następny termin” | osobny profil dystrybucyjny |

## 5. Czego nie robić

- **Portalu klienta.** Klienci tej kancelarii są na WhatsAppie; portal to
  kolejne hasło, którego nie założą.
- **Własnego „AI do badań prawnych”.** LEX AI, Libra, Legalis robią to
  z bazą orzeczeń; Emma ma być operacyjna (kto, co, kiedy), a nie
  konkurować z bazami.
- **Własnego podpisu elektronicznego i klienta KSeF.** Integrować, nie budować.
- **Automatycznej wysyłki bez adwokata** poza szablonami potwierdzeń —
  granica „Emma przygotowuje, adwokat wysyła” jest zaletą, nie ograniczeniem.

## 6. Decyzje właściciela

1. Push: włączyć capability w Apple Developer i wygenerować klucz APNs.
2. Szablony WhatsApp: zgoda na koszt (~0,01 €/wiadomość) i treści PL/RU.
3. Pliki z WhatsAppa: czy przechodzą przez relay Dualhooka (RODO/DPA).
4. Przyjmowanie po godzinach przez AI: tak/nie i w jakich godzinach.
5. KSeF: w czym kancelaria fakturuje dziś (program księgowy, biuro).
6. Tryb ciemny: ciemna paleta w referencji albo wyjątek w bramce.

## Źródła

- Clio / MyCase 2026: https://www.layer3labs.io/comparisons/clio-vs-mycase,
  https://legience.com/blog/best-legal-practice-management-software-2026
- AI w przyjmowaniu zgłoszeń, nieodebrane połączenia:
  https://futureagi.com/blog/voice-ai-legal-discovery-intake-2026/,
  https://www.getnextphone.com/blog/best-answering-service-for-law-firms
- Polskie programy: https://www.wolterskluwer.com/pl-pl/solutions/lex/oprogramowanie-dla-kancelarii,
  https://www.officium365.pl/, https://applex.eu/, https://www.tuasystent.pl/
- MOS: https://raczkowski.eu/od-27-kwietnia-2026-r-wnioski-pobytowe-cudzoziemcow-skladane-sa-wylacznie-elektronicznie-za-posrednictwem-modulu-obslugi-spraw-mos-2-0-sa-tez-inne-nowosci/,
  https://www.prawo.pl/samorzad/wnioski-o-pobyt-cudzoziemca-online-modul-mos,525536.html
- Portal Informacyjny: https://www.gov.pl/web/sprawiedliwosc/portal-informacyjny-sadow-powszechnych-z-nowymi-funkcjonalnosciami-od-1-marca-2026-r-rusza-elektroniczne-biuro-podawcze,
  https://www.wolterskluwer.com/pl-pl/expert-insights/komunikacja-procesowa-portal-informacyjny-sadow-2026
- e-Doręczenia: https://www.prawo.pl/prawnicy-sady/skrzynka-do-e-doreczen-nowy-obowiazek-adwokatow-i-radcow,530770.html
- KSeF: https://poradnikprzedsiebiorcy.pl/-obowiazkowy-ksef-dla-malych-firm-od-kiedy-i-na-jakich-zasadach,
  https://www.wolterskluwer.com/pl-pl/solutions/legaldesk/wiedza/ksef-w-kancelarii-przewodnik
- WhatsApp — ceny szablonów: https://sleekflow.io/blog/whatsapp-business-price
