# WhatsApp dla Emmy — partnerzy (BSP) i koszty

Stan na 2026-09-24. Uzupełnia `whatsapp-coexistence.md` (mechanika koegzystencji) i
`../WHATSAPP_ONBOARDING.md` (procedura podłączenia).

**Zastrzeżenie o źródłach:** strony Meta, 360dialog i Dualhook były w sesji researchu
zablokowane przez proxy sieciowe (tylko wyszukiwarka). Liczby poniżej pochodzą z wyników
wyszukiwania, częściowo z blogów partnerów, nie z oficjalnego cennika Meta. Przed
podpisaniem czegokolwiek trzeba je potwierdzić na stronach źródłowych (linki na dole).
Pozycje oznaczone **[do potwierdzenia]** mają tylko jedno, pośrednie źródło.

## 1. Trzy drogi

| Droga | Co to jest | Integracja z Emmą (wątki, karta klienta, sprawy) | Praca po naszej stronie |
| --- | --- | --- | --- |
| **A. Partner lekki (Tech Provider) + własny backend** | Partner robi tylko Embedded Signup i konfigurację; webhooki Meta idą prosto na backend Emmy | pełna | webhook, zapis wątków, logika AI, `/threads` |
| **B. Partner pełny (BSP z platformą)** | Partner hostuje numer, daje API i panel; webhooki przez partnera | pełna | jak w A |
| **C. Meta Business Agent** | AI Meta wbudowana w aplikację WhatsApp Business | **brak** — działa obok Emmy, nie w niej | zero |
| ~~D. Bezpośrednio jako Tech Provider~~ | własna aplikacja Meta z uprawnieniami, weryfikacją biznesu i przeglądem | pełna | jak w A + miesiące formalności; nieopłacalne dla jednego numeru |

Nieoficjalne biblioteki (Baileys, whatsapp-web.js) odpadają: łamią regulamin, ryzyko
bana numeru kancelarii.

## 2. Partnerzy obsługujący koegzystencję

| Partner | Model | Cena / numer / mies. | Narzut na wiadomości | Uwagi |
| --- | --- | --- | --- | --- |
| **Dualhook** | lekki (Tech Partner), Webhook Override | **$12** (1 połączenie); Team $25 (5) | brak | treść wiadomości nie przechodzi przez ich serwery przy Webhook Override — Meta wysyła prosto do nas. Mała firma, krótka historia **[do potwierdzenia: stabilność, umowa powierzenia]** |
| **360dialog** (Berlin) | pełny BSP | **€25** Regular / **€49** Premium; €249 high throughput | brak (Meta refakturowana 1:1) | uznany, europejski, ma dokumentację koegzystencji; webhooki idą przez nich |
| respond.io | platforma omnichannel | od ~$199 (Growth) | — | przerost formy: płacimy za inbox, którego nie potrzebujemy (mamy Emmę) |
| WATI, SendSeven itp. | platformy z panelem | ~€49+ | różnie | jak wyżej |
| **Twilio** | CPaaS | — | — | **nie obsługuje koegzystencji** — odpada |

## 3. Opłaty Meta (płacone niezależnie od partnera)

Kategorie: marketing, utility, authentication, service.

| Kategoria | Kiedy | Polska od 2026-07-01 |
| --- | --- | --- |
| **service** — dowolna odpowiedź w oknie 24 h (człowiek lub AI przez API) | klient napisał w ciągu 24 h | **od 2026-10-01 płatne**: 1000 darmowych / numer / miesiąc, potem stawka utility |
| **utility** — szablon, np. przypomnienie o terminie | poza oknem albo w oknie | **~$0,0014** **[do potwierdzenia]**; w oknie 24 h też płatne od 2026-10-01 |
| authentication | kody OTP | ~$0,0014 **[do potwierdzenia]** — nie dotyczy nas |
| **marketing** | newsletter, promocje | **$0,0384** |
| wiadomości wysłane ręcznie z aplikacji WA Business | zawsze | **darmowe** |

Ważne terminy:

- **2026-10-01** — Meta zaczyna liczyć opłaty za wiadomości service (po 1000 darmowych). Bez
  metody płatności na koncie Meta (albo u partnera, jeśli to on fakturuje) wiadomości
  service przestają być dostarczane.
- **październik 2026** — wyłączenie Embedded Signup v2 (źródła podają 8 lub 15 października).
  Dotyczy partnera, nie nas, ale warto zapytać partnera, czy jest na v4.

## 4. Meta Business Agent (droga C)

- Cena: **$2 za 1 mln tokenów**, AI i dostarczenie wiadomości w jednej stawce (od
  2026-08-01). Źródła szacują 20–25 tys. tokenów na odpowiedź → **~$0,04–0,05 za odpowiedź**
  **[do potwierdzenia]**.
- Wiedza w wersji samoobsługowej: profil, katalog, historia czatów na urządzeniu. Łączniki do
  własnego API (np. CRM) tylko w platformie enterprise o ograniczonej dostępności.
- Moment przekazania rozmowy człowiekowi wybiera Meta — nie da się tego skonfigurować.
- Dla kancelarii: AI odpowiada klientom samodzielnie, bez zatwierdzania, bez dostępu do
  spraw i terminów w Emmie. Ryzyko przy tajemnicy zawodowej i odpowiedzialności za treść.
  Nadaje się najwyżej na FAQ (godziny pracy, adres, jak umówić wizytę).

## 5. Przykładowy rachunek miesięczny

Założenie: 1 numer, 500 wiadomości od klientów, 500 odpowiedzi przez Emmę (AI + zatwierdzenie),
100 przypomnień o terminach (szablon utility), ręczne pisanie z telefonu bez zmian.

| Pozycja | Droga A (Dualhook) | Droga B (360dialog) | Droga C (Meta Agent) |
| --- | --- | --- | --- |
| Partner | $12 | €25–49 | $0 |
| Meta: 500 odpowiedzi service | $0 (mieści się w 1000 darmowych) | $0 | wliczone niżej |
| Meta: 100 przypomnień utility | ~$0,14 | ~$0,14 | nie obsługuje |
| AI | koszt modelu tekstowego w backendzie (Gemini) — do policzenia na realnym ruchu; przy tej skali rząd wielkości to pojedyncze dolary | jak A | 500 × ~$0,045 ≈ **$22** |
| **Razem / mies.** | **~$12–20** | **~€25–55** | **~$22**, bez integracji |

Koszty jednorazowe: brak opłat za onboarding u Meta. Realny koszt to praca po stronie
backendu (webhook, podpis `X-Hub-Signature-256`, deduplikacja po `wamid`, import historii w
24 h, wątki, logika AI z zatwierdzaniem) i podpięcie `/threads` w aplikacji iOS.

## 6. Rekomendacja

1. **Droga A z Dualhook** jako pierwszy wybór: najtańsza, treść rozmów klientów nie przechodzi
   przez pośrednika (istotne przy tajemnicy zawodowej), pełna integracja z Emmą.
2. **360dialog** jako zapas, jeśli Dualhook nie da umowy powierzenia (RODO) albo okaże się
   niestabilny — dojrzalszy dostawca z UE, drożej o ~€15–35 / mies.
3. **Meta Business Agent nie zamiast, ale ewentualnie obok** — tylko jeśli właściciel chce
   automatycznych odpowiedzi na FAQ poza godzinami pracy. Uwaga: dwie AI na jednym numerze
   mogą sobie wchodzić w drogę; wymaga sprawdzenia.

Przed decyzją do sprawdzenia u partnera: umowa powierzenia przetwarzania danych (RODO),
lokalizacja danych, obsługa importu historii (`history`, `smb_app_state_sync`) i echo
(`smb_message_echoes`), wersja Embedded Signup, kto fakturuje opłaty Meta.

## 7. Dualhook — umowa powierzenia (DPA) i przepływ treści

Tekst DPA (obowiązuje od 2026-07-21) dostarczony przez właściciela ze strony Dualhook.

**Kontrahent:** WADA BV (spółka z UE — BV to forma holenderska lub belgijska).

**Sprostowanie do sekcji 2:** treść nie omija Dualhook w obu kierunkach.

- przychodzące (klient → kancelaria): Webhook Override, Meta wysyła prosto na backend Emmy,
  Dualhook treści nie widzi;
- wychodzące (Emma → klient): przechodzą przez ich relay na Cloudflare (DPA §4). Deklarują
  brak zapisu i cache treści oraz brak treści i odbiorców w logach relay. Treść jest przez
  chwilę jawna w pamięci ich runtime'u — to deklaracja, nie gwarancja techniczna.

Kontekst: w Cloud API szyfrowanie E2E kończy się na serwerach Meta, a pełny BSP (360dialog)
widzi treść w obie strony. Dualhook widzi mniej niż pełny BSP, ale nie nic.

**Ocena wobec art. 28 ust. 3 RODO:** formalnie kompletna. Polecenia (§2), poufność (§5),
TOMs (§6, aneks `/security`), podwykonawcy z 30-dniowym uprzedzeniem i sprzeciwem (§7),
pomoc (§8, możliwe opłaty), SCC moduł 2 i 3 przy transferach (§10). Słabsze punkty:

- §9 — zgłoszenie naruszenia „without undue delay”, bez terminu w godzinach (kancelaria ma
  72 h wobec UODO),
- §11 — szerokie wyjątki od usunięcia danych (backup, audit, dispute) bez terminu,
- §12 — audyt głównie jako „informacje”, raz w roku.

**Do sprawdzenia przed założeniem konta:**

1. `https://dualhook.com/subprocessors` — lista i lokalizacje podwykonawców,
2. `https://dualhook.com/security` — aneks TOMs,
3. `https://dualhook.com/terms` — limit odpowiedzialności,
4. pytanie: czy wysyłka może iść bezpośrednio do Graph API własnym tokenem, z pominięciem relay,
5. pytanie: termin zgłoszenia naruszenia w godzinach,
6. po stronie kancelarii: zachować PDF DPA z datą akceptacji, wpis w rejestrze czynności
   przetwarzania, aktualizacja klauzuli informacyjnej.

## 8. Dualhook — podwykonawcy, ToS i TOMs (wersje z 2026-07-21)

Teksty dostarczone przez właściciela ze stron `/subprocessors`, `/terms`, `/security`.

**Kontrahent:** WADA BV, Sint-Paulusplaats 10, 2000 Antwerpen, Belgia, VAT BE0786.772.938.
Prawo belgijskie, sąd w Antwerpii.

**Wysyłka bez relay — niemożliwa.** TOMs §2: tokeny Meta nigdy nie są zwracane klientowi.
Token należy do aplikacji Meta Dualhook; backend Emmy wysyła przez ich Cloudflare Worker
kluczem `dh_live_` (przypisanym do jednego połączenia, przechowywanym jako SHA-256). Worker
odszyfrowuje token (AES-256-GCM) tylko na czas żądania i dodaje `appsecret_proof`.

**Podwykonawcy:** Clerk (logowanie), Stripe (płatności), Vercel (hosting, bez gwarancji
regionu UE), Cloudflare (relay wychodzących — treść w tranzycie), Turso/libSQL (baza,
w tym zaszyfrowane tokeny Meta), Umami i PostHog EU (analityka bez danych WhatsApp),
Resend (e-mail).

**Czerwone flagi / do wyjaśnienia:**

- Turso: sami piszą, że region i DPA trzeba potwierdzić — czyli nie publikują ich;
- ToS §10: zakaz przesyłania danych wrażliwych i identyfikatorów urzędowych → w kancelarii
  WhatsApp tylko do komunikacji organizacyjnej, bez meritum spraw, PESEL-i, danych o zdrowiu
  (reguła także dla promptu asystenta i akceptacji szkiców);
- brak niezależnych certyfikatów (ISO 27001, SOC 2) i brak SLA;
- zgłoszenie naruszenia nadal bez terminu w godzinach.

**ToS — ryzyka prawne:** odpowiedzialność do opłat z 3 miesięcy (§14), jednostronne
zwolnienie z odpowiedzialności na rzecz Dualhook (§15), natychmiastowe zawieszenie (§13),
zmiany regulaminu przez dalsze korzystanie (§18). Zawieszenie usługi wyłącza tylko
integrację — numer i historia zostają w aplikacji WhatsApp Business.

**ToS §5 — kto zakłada konto:** organizację Dualhook i Embedded Signup musi wykonać
kancelaria (właściciel Meta Business Portfolio). Zewnętrzny wykonawca backendu może dostać
tylko klucz `dh_live_` na podstawie pisemnej umowy; nie może trzymać danych dostępowych
Meta ani kontrolować organizacji.

**Wniosek dla backendu:** relay nie ponawia wysyłek (TOMs §5), a Cloud API nie ma klucza
idempotencji. Timeout wysyłki = stan nieznany; rozstrzyga webhook statusu z `wamid`, nie
ślepe ponowienie (ryzyko podwójnej wiadomości do klienta).

**Werdykt:** akceptowalny pod warunkiem wyjaśnienia Turso i terminu zgłoszenia naruszeń
oraz przyjęcia zasady „bez danych wrażliwych przez WhatsApp”. Alternatywa: 360dialog
(dojrzalszy, ale widzi całą treść w obie strony).

## Źródła

- Meta — cennik: https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing
- Meta — zmiany dla service/utility i Business Agent: https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing/non-template-messages
- 360dialog — płatne wiadomości service od 1.10.2026: https://360dialog.com/blog/whatsapp-service-message-charging-october-2026/
- 360dialog — cennik: https://360dialog.com/pricing, https://docs.360dialog.com/partner/get-started/pricing
- 360dialog — koegzystencja: https://docs.360dialog.com/partner/onboarding/whatsapp-coexistence
- Dualhook — cennik i porównanie: https://dualhook.com/pricing, https://dualhook.com/best-whatsapp-coexistence-providers
- Dualhook — Webhook Override: https://dualhook.com/docs/webhook-override
- Twilio bez koegzystencji: https://chakrahq.com/article/whatsapp-coexistence-chakra-twilio-migrate-change
- Stawki PL od 1.07.2026: https://woztell.com/whatsapp-pricing-changes-july-2026/, https://www.ycloud.com/blog/whatsapp-api-message-pricing-update-effective-july-1-2026
- Koegzystencja w UE: https://chakrahq.com/article/whatsapp-coexistence-live-eu-uk-europe-whatsapp-business-for-api-live/
- Meta Business Agent — cena: https://zernio.com/blog/meta-business-agent-pricing, https://www.wati.io/en/blog/meta-whatsapp-ai-token-pricing/
- Meta Business Agent — ograniczenia: https://www.wati.io/en/blog/meta-business-agent/
