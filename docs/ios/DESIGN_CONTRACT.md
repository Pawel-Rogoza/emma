# DESIGN_CONTRACT.md

> **Zakończony 10.10.2026 (0.22.0).** Aplikacja nie odtwarza już prototypu HTML.
> Obowiązują tokeny semantyczne z `EmmaTheme.swift`, SF Pro + Manrope i komponenty
> systemowe iOS 26 — szczegóły w `REDESIGN_IOS26_2026-10-10.md`. Poniższy tekst
> zostaje jako historia decyzji.

Zamrożony kontrakt wyglądu dla natywnej aplikacji Emma na iPhone.
Źródło: `reference/prototype/` z commita `b97685b5e2c2cd3d6f78b172b9c0b5cee114270b`
(opublikowana wersja 5), sumy kontrolne zgodne z `reference/manifest.json` (patrz `BASELINE.md` §2).

Zasady nadrzędne (§1 i §2 planu):

- Obowiązuje **wynik kaskady CSS**, nie pierwszy pasujący selektor.
- Do aplikacji **nie** przenosimy: ramki telefonu, `.statusbar` z godziną 9:41, `.island`,
  `.device-indicators`, `.home-indicator`, `.preview-caption` — te elementy zapewnia urządzenie.
- Nie przenosimy martwych warstw desktopowych: `.studio`, `.intro`, `.details`, `.workspace`,
  `.sidebar`, `#desktop-nav`, `.work-panel`, `.timeline>span`.
- Kalendarz **bez** kolumny godzin po lewej; godzina i długość wyłącznie w karcie.
- Rozmowy **bez** etykiet „Pilne” / „Do odpowiedzi” / scoringu leadów / badge AI.
- Metadane 9–11 px podniesione do czytelnych ~12 pt; obszary dotykowe ≥ 44 × 44 pt (§2.2).

## 1. Kolory (wartości efektywne po kaskadzie)

| Token SwiftUI | Hex | Pochodzenie |
| --- | --- | --- |
| `EmmaTheme.bg` | `#F5F6F8` | `--bg`, tło `.content` |
| `EmmaTheme.ink` | `#152337` | `--ink` |
| `EmmaTheme.muted` | `#687688` | nadpisanie `--muted` (linia 4) |
| `EmmaTheme.mutedSoft` | `#7A8492` | bazowa `--muted` (metadane drugorzędne) |
| `EmmaTheme.border` | `#E2E7ED` | nadpisanie `--border` (linia 4) |
| `EmmaTheme.cardBorder` | `#E8ECF0` | `.card` |
| `EmmaTheme.accent` | `#3B61D9` | `--blue` |
| `EmmaTheme.unreadBadge` | `#365FD0` | `.unread-count`, `#nav .nav-unread` |
| `EmmaTheme.emmaCard` | `#14263C` | `.emma-card` |
| `EmmaTheme.emmaCardText` | `#DBE3ED` | `.emma-card p` |
| `EmmaTheme.primaryButton` | `#1B314D` | `.primary`, `.send-button` |
| `EmmaTheme.secondaryButton` | `#EDF0F5` / tekst `#365373` | `.secondary` |
| `EmmaTheme.chatBackground` | `#EEF1F5` | `.in-chat #content` |
| `EmmaTheme.bubbleIncoming` | `#FFFFFF` | `.chat-message` |
| `EmmaTheme.bubbleOutgoing` | `#DFE8F1` | `.chat-message.outgoing` |
| `EmmaTheme.receiptRead` | `#2674D8` | `.receipt.read` |
| `EmmaTheme.receiptDefault` | `#82909E` | `.receipt` |
| `EmmaTheme.composerBorder` | `#DCE3EC` | `.in-chat .chat-composer` |
| `EmmaTheme.chatDockBackground` | `#F9FAFC` | `#chat-dock` |
| `EmmaTheme.chatHeaderBorder` | `#E1E6ED` | `#chat-header` |
| `EmmaTheme.selectedDay` | `#1C314B` / cyfra `#FFFFFF`, etykieta `#BFCCDF` | `.day.selected` |
| `EmmaTheme.tabBarBackground` | `#FBFCFD` (krycie ~93%) | `#nav` |
| `EmmaTheme.tabBarBorder` | `#E1E7EE` | `#nav` |
| `EmmaTheme.tabActive` | `#254D9D` | `nav button.active` |
| `EmmaTheme.tabInactive` | `#8A93A0` | `nav button` |
| `EmmaTheme.tabEmmaChip` | `#1A2E47` na białym | `nav .nav-emma` |
| `EmmaTheme.pillNeutral` | tło `#F0F3FC`, tekst `#5770AB` | `.pill` |
| `EmmaTheme.pillGreen` | tło `#EDF4EF`, tekst `#4B7966` | `.pill.green` |
| `EmmaTheme.pillAmber` | tło `#FAF0E5`, tekst `#986B36` | `.pill.amber` |
| `EmmaTheme.danger` | `#A1533E` | `.form-error` |
| `EmmaTheme.toastBackground` | `#213953` | `#toast` |
| `EmmaTheme.controlBackground` | `#E9EDF2` | `.segmented`, `.search` |
| `EmmaTheme.fieldBorder` | `#DCE5EE` | `.form-field>input` |
| `EmmaTheme.infoRowBorder` | `#E5EAF0` | `.info-list` (linia 4) |
| `EmmaTheme.sheetHandle` | `#C9D0D9` | `.handle` |
| `EmmaTheme.contextStrip` | tło `#EAF0F6`, tekst `#6B84A0`, obramowanie `#DFE7EF` | `.emma-context` |
| `EmmaTheme.quoteRule` | `#7895B5` | `.quoted-message`, `.composer-quote` |
| `EmmaTheme.unreadDivider` | tło `#E1E9F5`, tekst `#365D98` | `.unread-divider` |
| `EmmaTheme.chatDayChip` | tło `#E5EAF0`, tekst `#788697` | `.messenger-thread .chat-day` |
| `EmmaTheme.dictationAccent` | `#9A622C` | `.thread-preview em` (etykieta „Szkic:”) |

Kolory avatarów listy rozmów (`tone-N`, wg stabilnego indeksu prezentacji, nie wg ID):

| Tone | `.thread-open` | Uwaga |
| --- | --- | --- |
| domyślny | tło `#E3EBF1`, tekst `#4E6882` | |
| `tone-1` | tło `#EAE3DA`, tekst `#88704E` | |
| `tone-2` | tło `#EEE4E8`, tekst `#926778` | |
| `tone-3` | tło `#E4E9E2`, tekst `#6A7A60` | |

W kartach klienta/osób: `.person .avatar` → tło `#EAF0F4`, tekst `#62778A`, bez obramowania.
`.avatar` bazowy: tło `#E9E3D9`, tekst `#79664A`, obramowanie `3 pt` białe.

**First release wymusza jasny motyw** (§2.3): `.preferredColorScheme(.light)`. Pełny dark mode
to osobna decyzja, nie automatyczna zmiana zaakceptowanych kolorów.

## 2. Promienie, marginesy, rytm

| Token | Wartość | Źródło |
| --- | --- | --- |
| `EmmaRadii.card` | 17 | `.card` |
| `EmmaRadii.emmaCard` | 21 | `.emma-card` (linia 4) |
| `EmmaRadii.segmented` | 10 (wewnętrzny przycisk 8) | `.segmented` |
| `EmmaRadii.search` | 11 | `.search` |
| `EmmaRadii.button` | 12 | `.primary`, `.secondary`, `.voice-cta` |
| `EmmaRadii.iconButton` | 12 | `.icon-button` |
| `EmmaRadii.bubble` | 17 / 5 po stronie nadawcy | `.chat-message` |
| `EmmaRadii.composer` | 24 (pole), 11 wewnętrzny przycisk | `.in-chat .chat-composer` |
| `EmmaRadii.pill` | 6 | `.pill` |
| `EmmaRadii.field` | 10 | `.form-field>input` |
| `EmmaRadii.choiceList` | 13 | `.choice-list` |
| `EmmaRadii.sheet` | 23 (górne narożniki) | `dialog` (linia 4) |
| `EmmaRadii.dayCell` | 15 | `.day` |
| `EmmaSpacing.screenH` | 20 | `.iphone-preview .content` |
| `EmmaSpacing.threadH` | 16 | `.in-chat #content` |
| `EmmaSpacing.contentTop` | 16 | `.content` |
| `EmmaSpacing.contentBottom` | 18 | `.content` |
| `EmmaSpacing.sectionTop` | 16, min. wysokość nagłówka 38 | `.section-head` (linie 4 i 11) |
| `EmmaSpacing.sectionBottom` | 9 | `.section-head` (linia 11) |
| `EmmaSpacing.cardGap` | 10–12 | `.meeting`, `.case-card`, `.event-row` |
| `EmmaSpacing.hitTarget` | 44 × 44 | korekta użyteczności (§2.2) |
| `EmmaSpacing.smallScreenH` | 15 | `@media(max-width:365px)` |

Szerokość referencyjna wnętrza: `412 px − 2 × 7 px obramowania = 398 pt`. Nie używamy
`UIScreen.main.bounds`; layout jest elastyczny, adaptacja dla 375 pt i 430/440 pt.

## 3. Typografia

Bazowy: DM Sans. Nagłówki i tytuły: Manrope. Bundlowane pliki i **zweryfikowane** nazwy PostScript:

| Plik | PostScript | Wagi w projekcie |
| --- | --- | --- |
| `DMSans-Regular.ttf` | `DMSans-Regular` | 400 |
| `DMSans-Medium.ttf` | `DMSans-Medium` | 500 |
| `DMSans-SemiBold.ttf` | `DMSans-SemiBold` | 600 |
| `Manrope-Bold.ttf` | `Manrope-Bold` | 700 |
| `Manrope-ExtraBold.ttf` | `Manrope-ExtraBold` | 800 |

Nazwy PostScript odczytano z tablicy `name` plików (ID 6), nie zgadywano. Licencje OFL
dołączone obok plików (`DMSans-OFL.txt`, `Manrope-OFL.txt`).

**Zmierzona kontrola pokrycia glifów** (parser cmap, patrz `BUILD_AND_DEVICE_STATUS.md`):

| Font | polskie znaki | cyrylica RU | cyrylica UK |
| --- | --- | --- | --- |
| DM Sans (wszystkie wagi) | ✅ | ❌ **brak** | ❌ **brak** |
| Manrope (700/800) | ✅ | ✅ | ✅ |

Konsekwencja projektowa (odstępstwo **D-01**, patrz `DESIGN_DEVIATIONS.md`): treść zawierająca
cyrylicę jest renderowana czcionką systemową (SF Pro), ponieważ referencja z układem
`font-family:'DM Sans',-apple-system,…` również spada na `-apple-system` dla cyrylicy.
Decyzja jest jawna w `EmmaTypography.body(for:)`, nie pozostawiona cichej kaskadzie.

| Rola | Rozmiar / waga | Źródło |
| --- | --- | --- |
| Nagłówek główny (`.welcome`) | Manrope ExtraBold 25, tracking −0.9 | linia 11 |
| Kicker / `.date` | DM Sans 11, tracking 1.5, waga 650, `mutedSoft` | linia 4 |
| Tytuł sekcji (`.section-head h2`) | DM Sans SemiBold 16 | linia 11 |
| Nazwa osoby w wierszu (`.person b`) | DM Sans SemiBold 15 | `.person b` |
| Podtytuł osoby (`.person p`) | DM Sans 12, `muted` | `.person p` |
| Karta spotkania `.meeting-top` | DM Sans 11 `muted` | linia 11 |
| Tytuł sprawy w karcie | Manrope Bold 16, tracking −0.45 | `.case-card h3` |
| Numer sprawy | DM Sans 10, tracking 1, `#8B95A3` | `.case-card-head` |
| Wiersz zadania `.task-body b` | DM Sans 13 (waga 550 → Medium/SemiBold) | linia 4 |
| Metadane zadania | DM Sans 11 `#8A95A3` | `.task-body span` |
| Termin zadania | DM Sans 10 `#8B96A5`; „Pilne” `#A47740` na `#FBF0E3` | `.task-date` |
| Nagłówek szczegółu `.back-header b` | DM Sans SemiBold 13 | linia 4 |
| Podpis szczegółu (`.back-header span`) | DM Sans 9→**12**, tracking 1 | linia 4 + §2.2 |
| Hero klienta `h1` | Manrope Bold 24, tracking −0.8 | `.client-hero h1` |
| Tytuł sprawy `h1` | Manrope Bold 25, tracking −0.9 | linia 11 |
| Nazwa w liście rozmów | DM Sans Medium 16, tracking −0.3 | `.thread-title b` |
| Czas w liście rozmów | DM Sans 12 `#7A8594` | `.thread-title time` |
| Podgląd wiadomości | DM Sans 14 `#6C798A`, max 2 linie | `.thread-preview` |
| Nagłówek otwartego wątku | DM Sans Bold 16 | linia 21 |
| Treść dymku (`.chat-message>p`) | DM Sans 16, interlinia 1.5 | linia 23 |
| Metadane dymku | DM Sans 11 `#738398`, min. wysokość 25 | `.bubble-meta` |
| Separator dnia | DM Sans 12 `#788697` | linia 22 |
| „Nowe wiadomości” | DM Sans 12 `#365D98` | linia 22 |
| Pole wiadomości | DM Sans 16 (bez auto-zoomu) | linia 24 |
| Wypowiedź Emmy | DM Sans 14, interlinia 1.8 | `.emma-turn p` |
| Tytuł akcji `.emma-action h3` | DM Sans SemiBold 15 | linia 4 |
| Formularz: etykieta | DM Sans Medium 12 `#728398` | linia 4 |
| Formularz: wartość | DM Sans 16 (iOS, unika zoomu klawiatury) | §2.2 |
| `secondary`/`primary` przycisk | DM Sans 13, min. wysokość 44 (preview 46) | linia 4 + 11 |

Skalowanie: **tylko style tekstu** — wszystkie przechodzą przez trzy konstruktory
`EmmaTypography` i skalują się względem `.body` (decyzja i dług w `DESIGN_DEVIATIONS.md`, D-13).
Odstępy pozostają stałe: siatka kart z referencji. Bez agresywnego `minimumScaleFactor`.
Długie nazwiska: `overflow-wrap:anywhere` w referencji → w SwiftUI zawijanie i `minimumScaleFactor(0.85)`
maksymalnie, z zachowaniem pełnej treści.

## 4. Orb Emmy

Jeden komponent `EmmaOrb` z rozmiarami:

| Rozmiar | Wartość | Użycie |
| --- | --- | --- |
| `.inline` | 18 pt | `.composer-emma`, `.small-suggestions` |
| `.small` | 25 pt | dawny `.chat-emma` (skrót w rozmowie) |
| `.card` | 37 pt | `.emma-card`, `.emma-top` |
| `.medium` | 32 pt | `.case-emma` |
| `.hero` | 100 pt | `.emma-intro .big-orb` |

Wypełnienie (odtworzone natywnie — `RadialGradient` + nakładki, bez nowego avatara postaci):

```
radial-gradient(circle at 28% 24%,
  #E0F7EE 0%, #95BBD3 20%, #769BBF 33%, #8A83A8 46%,
  #384D78 61%, #CCD7CE 84%, #7896BB 100%)
```

Cienie (skalowane z rozmiarem):
`inset -5 -5 12 #FFFFFF52`, `inset 3 0 9 #E5E9FB80`, `0 0 25 #9CBFDD20`;
dla `.hero`: `inset -12 -12 28`, `inset 7 0 24`, `0 16 42 #688BAC20` (linia 4).

Animacja: `breathe` **bez zmiany skali** — oddychanie niosą wyłącznie ruch głowy, uszy
i światło (stan aktywny: listening/speaking/requesting). Skala `1.08` z pierwotnego
projektu została usunięta, bo przy aktualizacji SwiftUI SceneKit interpolował transform
węzła i postać na chwilę się rozciągała (zob. `EmmaOrb`). Obwiednia postaci jest stała,
a obrazek zapasowy używa tej samej widocznej wielkości co relief (`reliefMatchScale`),
żeby przełączenie renderu nie wyglądało jak rośnięcie i zmniejszanie.
`Reduce Motion` zatrzymuje puls i pozostawia czytelną etykietę stanu. Brak stałego pulsowania aplikacji.

## 5. Shell i nawigacja

Pięć zakładek, kolejność i etykiety:

| # | Zakładka | SF Symbol | Uwaga |
| --- | --- | --- | --- |
| 1 | Dzisiaj | `house` | |
| 2 | Klienci | `person.2` | |
| 3 | Emma | `sparkles` w granatowym chipie 43 × 34, promień 13 | środkowa |
| 4 | Rozmowy | `bubble.left.and.bubble.right` | licznik nieprzeczytanych |
| 5 | Kalendarz | `calendar` | |

- Wysokość paska 74 pt, górny padding 8, dolny 3, tło `#FBFCFD` ~93 % + `blur`, obramowanie górne `#E1E7EE`.
- Etykieta 10 pt, `min-height` 52 pt, aktywny `#254D9D`.
- Licznik `.nav-unread`: `#365FD0`, biały tekst 11 pt waga 700, min. szerokość 17, wysokość 17,
  promień 10, obwódka 2 pt w kolorze paska.
- **Wygląd odtwarzamy własnym komponentem** `EmmaTabBar` (§3.1 planu) — nie przyjmujemy
  automatycznie pływającego stylu systemowego `TabView`. Dostępność: `accessibilityLabel`
  z licznikiem, `accessibilityAddTraits(.isSelected)`, hit target ≥ 44 pt.
- Otwarty czat **ukrywa** pasek zakładek i pokazuje stały nagłówek wątku (§3.2).
- Tap Emmy → centrum asystenta. Głos wyłącznie jawną akcją mikrofonu. Hold-to-talk nie istnieje
  w pierwszym przyroście.
- Sztuczny status bar / ramka / home indicator **nie są** implementowane.

## 6. Komponenty (§2.4 planu)

Zrealizowane w `ios/Emma/DesignSystem/`:

`EmmaTheme`, `EmmaTypography`, `EmmaSpacing`, `EmmaRadii`, `EmmaMetrics`
oraz: `SurfaceCard`, `PersonAvatar`, `StatusBadge`, `SegmentedFilter`, `SearchField`, `EmptyState`,
`InlineError`, `LoadingState`, `ScreenHeader`, `DetailHeader`, `EmmaTabBar`, `PrimaryButton`,
`SecondaryButton`, `FormField`, `ChoiceList`, `InfoList`, `TraceToast`, `EmmaOrb`, `NavUnreadBadge`.

Kancelaria: `EmmaBriefingCard`, `ConsultationCard`, `TaskRow`, `CaseCard`, `ClientRow`, `LeadCard`,
`EventRow`, `NoteCard`, `ActivityRow`, `QuickActions`, `WorkspaceStats`, `LinkedCaseButton`.
Rozmowy: `ConversationRow`, `UnreadBadge`, `MessageBubble`, `MessageReceipt`, `QuotedMessage`,
`MessageComposer`, `TranslationDisclosure`, `NewMessagesDivider`, `ChatDaySeparator`, `ThreadContextStrip`.
Voice: `EmmaOrb`, `VoiceControlBar`, `VoiceStatus`, `VoiceSessionStrip`, `TranscriptView`,
`ActionProposalCard`, `DictationAccessory`.

Widoki **nie** zawierają literałów kolorów ani promieni — wyłącznie tokeny.

## 7. Mapowanie ekranów na stany referencji

| Ekran natywny | Stan w `app.js` | Fixture / kryterium |
| --- | --- | --- |
| Dzisiaj | `home()` | `today-default` — Olena 10:30, Andrii pilny lead, 3 zadania, 2 sprawy |
| Klienci / Leady | `clients()` + `clientMode='Leady'` | `clients-leads` |
| Klienci / Sprawy | `clients()` + `clientMode='Sprawy'` | `clients-cases` |
| Karta klienta | `personPage()` | `client-olena` |
| Sprawa | `casePage()`, zakładki Przegląd/Zadania/Notatki/Historia | `case-11` |
| Zadania | `tasksPage()` | `tasks-open` |
| Kalendarz | `calendar()` — tydzień Pn–Nd od 2026-09-07, dzień 2026-09-11 | `calendar-week` |
| Szczegół terminu | `eventDetail()` | `event-olena` |
| Rozmowy | `messagesPage()` | `messages-default` |
| Wątek | `chatPage()` | `chat-unread` (Andrii, separator nowych, tłumaczenie) |
| Emma idle | `emmaPage()` bez tur | `emma-idle` |
| Emma konwersacja | `emmaPage()` z turami | `emma-thread` |
| Emma propozycja | `renderTurn()` typ `action`, stan `pending` | `emma-proposal` |
| Profil | `profile()` | sheet |

## 8. Wykluczenia (twarde kryteria odbioru)

1. Brak jakiejkolwiek kolumny godzin po lewej stronie kalendarza.
2. Brak etykiet pilności na liście rozmów („Pilne”, „Do odpowiedzi”, badge AI, scoring leadów).
3. Brak statycznej godziny, ramki telefonu, sztucznej wyspy i paska gestu.
4. Brak szóstej zakładki i brak desktopowego CRM z bocznym menu.
5. Brak timerów statusu dostarczenia i fikcyjnych „dostarczono/odczytano” w trybie live.
6. Brak kluczy dostawców w aplikacji i w repozytorium.
