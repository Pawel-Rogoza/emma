# Integracja z Emmą — etap prototypu

Odczyt repo przez GitHub: `Pawel-Rogoza/emma`, commit `c57caf0884f4410283544c45859347c683e9472b`, 2026-09-12. Żaden plik zdalnego repo ani kod aplikacji nie został zmieniony.

## Ustalenia ze źródeł

- `ios/Emma/DesignSystem/EmmaOrb.swift`: SwiftUI, rozmiary 18 / 25 / 32 / 37 / 100 pt, `isActive` i nowe osobne `breathing`. Awatar oddziela spokojny ruch od ruchu pyska sterowanego audio.
- `ios/Emma/Features/Today/TodayScreen.swift`: ekran powitalny Emmy; przycisk orba hero używa `voice.state.isPlaybackActive` i `breathing: true`. Dotknięcie wywołuje `openEmma(clientID: nil, startVoice: true)`. Przy przyszłej podmianie zachować ten przycisk i jego dostępność, wymienić tylko grafikę wewnątrz.
- `ios/Emma/Core/Voice/VoiceEvents.swift`: `TurnState` ma `waiting`, `listening`, `thinking`, `speaking`, `interrupted`. Nie znaleziono strumienia poziomu audio w tym kontrakcie — `playbackStarted` nie zawiera amplitudy.
- `ios/Emma/DesignSystem/EmmaTheme.swift`: jasne tło `#F5F6F8`, tekst `#152337`, muted `#687688`. Podgląd pokazuje jasny ekran mobilny, bez panelu studia.

## Pakiet natywny

W Xcode dodaj lokalny Swift Package z katalogu `native`, potem produkt `EmmaPortrait` do targetu. Pakiet zawiera własną teksturę i generator siatki; nie potrzebuje WebView ani bibliotek JavaScript. Nie kopiuje ani nie zastępuje koordynatora głosu.

```swift
import EmmaPortrait

// Przykład; podstaw aktualny TurnState z koordynatora aplikacji.
EmmaPortrait(size: 100, state: .listening)

// Po przyszłym dodaniu sygnału RMS z odtwarzania:
EmmaPortrait(size: 100, state: .speaking, audioLevel: 0.4)
```

Mapowanie `TurnState` jest jeden-do-jednego według nazw. Dla rozmiarów orba mniejszych niż 80 pt renderer nie jest tworzony. Reduce Motion, nieaktywna scena i zniknięcie widoku przełączają na statyczny portret. Maksymalnie 30 fps. Wymagany pomiar na docelowym iPhonie; kompilacja nie stanowi dowodu zużycia baterii.

Mrugnięcie i mówienie korzystają teraz z dwóch lokalnych, fotorealistycznych nakładek (`emma-blink-overlay.png`, `emma-speak-overlay.png`) zamiast deformowania odpowiednich fragmentów siatki. SceneKit animuje ich opacity nad reliefem; kanał alfa ogranicza zmianę odpowiednio do powiek i pyska. Morphy siatki pozostają aktywne tylko dla uszu. `audioLevel` steruje intensywnością klatki mówiącego pyska; nadal nie jest to synchronizacja fonemów.

Obecny wariant `emma-avatar.png` ma kanał alfa i wtapia się w jasny ekran. Maski w web i SwiftUI łagodnie wygaszają dolną sierść. Podgląd odtwarza dostarczony ekran startowy; nie zawiera już panelu stanów. Nie podmieniaj wszystkich orbów automatycznie: przy 18–37 pt trzeba ocenić czytelność i kadrowanie. W podglądzie główny awatar ma 210 px (170 px przy niskim ekranie); natywny parametr `size` pozostaje konfigurowalny.

## Co dokładnie zostało zrobione

Zaakceptowany portret jest teksturą na płytkiej siatce przestrzennej (25921 wierzchołków, 51200 trójkątów). Głębia jest ręcznie przybliżona funkcjami Gaussa. Dodano pięć deformacji: blinkLeft, blinkRight, earLeft, earRight, jawOpen. Przymykanie oczu jest lokalnym ściskaniem portretu; ruch pyska nie odsłania jamy ustnej. Nie są to anatomiczne powieki, szczęka ani synchronizacja fonemów. Uszy poruszają się niezależnie, głowa przechyla się zależnie od stanu. Implementacje JavaScript i SceneKit używają tych samych funkcji ruchu. GLB ma klipy idle/listening/thinking/speaking/interrupted i morph targets; speaking zawiera demonstracyjny poziom 0.5, nie nagranie głosu. Światło jest zapisane w obrazie, bez dynamicznego oświetlenia sierści. To nadal relief 2.5D, nie kompletna głowa.

## Warunek pełnej wersji 3D

Pełny model potrzebuje poprawnej bryły głowy i profilu, tekstur także boków/tyłu, osobnych oczu i powiek, szczęki, uszu oraz fryzury (groom do renderów, zoptymalizowane hair cards do telefonu). Następnie rig/morph targets, klipy oraz eksport USDZ dla natywnego renderera i GLB do podglądu. W tym pakiecie tych elementów jeszcze nie ma. Nie przedstawiać reliefu jako ukończonego modelu Blender.

## Sprawdzenie

- `npm run build` — zaliczone.
- `node scripts/verify-animation.mjs` — 9000 próbek ruchu, geometria pięciu deformacji i walidator glTF: zero błędów i ostrzeżeń. Informacje walidatora obejmują rozmiar tekstury niebędący potęgą dwójki.
- `swift build --package-path native` — zaliczone na macOS, Swift 6.
- `swiftc -typecheck -swift-version 6 -target arm64-apple-ios17.0-simulator` z SDK iOS Simulator — zaliczone.
- Nie uruchomiono aplikacji na iPhonie ani symulatorze; nie zmierzono wydajności natywnej i wyglądu renderu SceneKit.
