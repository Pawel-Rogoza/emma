# Emma — awatar na ekranie startowym

Podgląd ekranu startowego z przesłanego zrzutu: Emma zastępuje orb na jasnym tle. Usunięto panel studia, przyciski stanów i suwaki. Właściwa aplikacja nie została zmieniona.

**Etap pośredni: animowany relief 2.5D, nie ukończony fotorealistyczny model 3D.** Portret zachowuje wygląd, siatka dodaje niewielką głębię i ograniczony ruch. Brak pełnego obrotu, rigu twarzy i animacji sierści.

```sh
npm install
npm run dev -- --host 127.0.0.1
```

Podgląd: http://127.0.0.1:5173/

## Następny etap: bryła 3D

### Studium sierści (nie finalny awatar)

`/model.html?groom` pokazuje oddzielny wariant z geometryczną sierścią, frędzlami uszu i materiałami oczu. Kod: `src/head-groom.js`. Eksport: `node scripts/export-head.mjs --groom`, wynik: `public/emma-head-groom.glb` (około 20.8 MB), te same pięć klipów animacji. Pasma są przypięte do części głowy, szczęki i uszu; nie mają osobnej symulacji fizycznej. Walidacja GLB: zero błędów i ostrzeżeń.

Ocena wizualna: **nie osiągnięto fotorealizmu ani podobieństwa zaakceptowanego portretu**. Widoczne pozostają uproszczenia bryły, łączenia elementów twarzy oraz proceduralny układ sierści. To eksperyment techniczny, nie gotowy asset do aplikacji. Nie zastępuje awatara na stronie głównej. Model wymaga rzeźbienia i retopologii przez narzędzia DCC, układania sierści według referencji i tekstur PBR; dodawanie kolejnych pasm do obecnych prymitywów nie rozwiązuje problemu podobieństwa. W środowisku nie znaleziono Blendera; nie wykonano renderu Cycles ani pliku `.blend`. Wydajność na iPhonie nie została sprawdzona. Przed wdrożeniem konieczna redukcja geometrii/LOD i pomiar na urządzeniu.

Osobny podgląd techniczny: http://127.0.0.1:5173/model.html — przeciągnij, aby obejrzeć model z dowolnej strony; kółko/pinch zmienia odległość. Przyciski kontrolują obrót i demonstracyjny ruch pyska. Nie zmienia to domyślnego awatara ani pakietu SwiftUI.

- `src/head-model.js` — pełnoobjętościowy blockout z osobnymi oczami, górnymi powiekami, szczęką i uszami. Transformacje w hierarchii węzłów, jeszcze bez skinningu.
- `public/emma-head-blockout.glb` — ok. 1 MB, pięć klipów: idle/listening/thinking/speaking/interrupted. Można importować do Blendera jako bazę techniczną.
- `scripts/export-head.mjs` — odtwarzalny eksport: `node scripts/export-head.mjs`; automatyczna walidacja glTF (zero błędów i ostrzeżeń).

To **robocza bryła z prostych powierzchni**, nie finalne podobieństwo Emmy. Nie ma jeszcze połączonej siatki twarzy, dopracowanych dolnych powiek i kącików oczu, uzębienia, UV dopasowanego do zdjęć ani sierści. Bok i tył są przybliżeniem, nie rekonstrukcją. Zaakceptowany portret pozostaje wizualnym wzorcem. Następny etap: rzeźbienie proporcji i profilu na podstawie zdjęć, retopologia twarzy i ust, tekstury PBR oraz mobilna sierść. Dopiero po ocenie podobieństwa i wydajności można zastąpić relief w natywnym rendererze.

Pliki:
- `public/emma-portrait.png` — zaakceptowany portret.
- `public/emma-avatar.png` — nowy portret z prawdziwym kanałem alfa, do jasnego tła.
- `public/emma-relief.glb` — relief z przezroczystą teksturą, pięcioma morph targets i klipami idle/listening/thinking/speaking/interrupted (ok. 5.34 MB).
- `src/relief.js` — generator siatki; `scripts/export-relief.mjs` — odtwarzalny eksport GLB.
- `native/` — osobny Swift Package dla SwiftUI/iOS 17 i macOS 14.
- `INTEGRATION.md` — ustalenia z repo, użycie, ograniczenia i walidacja.
- `preview.png` — historyczny zrzut ODRZUCONEGO prototypu; nie przedstawia tej wersji.

Stany JavaScript: `window.emma.setState('waiting' | 'listening' | 'thinking' | 'speaking' | 'interrupted')`. `window.emma.setAudioLevel(0...1)` przyjmuje poziom audio; niczego nie nagrywa ani nie odtwarza. Przyciski ekranu informują o demonstracyjnym charakterze funkcji; nie uruchamiają prawdziwego głosu, czatu lub danych kancelarii. Animacja respektuje Reduce Motion.

Dotknij głowy Emmy, aby obejrzeć 15-sekundową demonstrację słuchania, myślenia i mówienia (bez mikrofonu). Ruch obejmuje przechylenia głowy, lokalne przymykanie oczu, uszy i delikatną deformację pyska. To deformacje portretu, nie anatomiczne powieki ani otwierana jama ustna; nie jest to lip-sync. W produkcji stany ma ustawiać koordynator głosu, a nie dotknięcie głowy.

### Fotorealistyczna mimika 2.5D

Najbardziej widoczne deformacje siatki zostały zastąpione lokalnymi klatkami tekstur. `emma-blink-overlay.png` zawiera tylko powieki, a `emma-speak-overlay.png` tylko pysk; poza miękkimi maskami renderer zawsze pokazuje piksele zaakceptowanego `emma-avatar.png`. Dzięki temu sylwetka, uszy, umaszczenie i pojedyncze włosy nie „pływają” podczas przejść. Kanał alfa obu nakładek jest odtworzony z zatwierdzonego portretu przez `node scripts/make-expression-overlays.mjs`.

Web miesza nakładki w shaderze, dodaje bardzo małe ruchy spojrzenia, spokojny oddech, ograniczone przechylenia reliefu i osobny ruch uszu. SwiftUI/SceneKit używa tych samych lokalnych nakładek jako warstw na reliefie; mrugnięcie i pysk nie rozciągają już siatki. Reduce Motion pozostawia portret statyczny. Parametry diagnostyczne podglądu: `?state=speaking&level=1&time=0.092` oraz `?state=waiting&time=2.705`.

Klatki `emma-blink.png` i `emma-speak.png` przygotowano wbudowanym ImageGen w trybie identity-preserve, na podstawie zaakceptowanego portretu. Generator nie zachował przezroczystości, dlatego pliki nie są renderowane bezpośrednio: skrypt tworzy z nich bezpieczne, lokalne nakładki z prawdziwym kanałem alfa. To rozwiązanie zachowuje fotorealizm z przodu, ale świadomie ogranicza obrót — nie rekonstruuje niewidocznych boków ani tyłu głowy.

Build: `npm run build`. Eksport: `node scripts/export-relief.mjs`. Testy ruchu i walidacja GLB: `node scripts/verify-animation.mjs`. Pakiet: `swift build --package-path native`.

Portret wygenerowano wbudowanym ImageGen na podstawie trzech zdjęć Emmy, zatwierdzony przez użytkownika. Skrót promptu: „premium photorealistic Blender Cycles style portrait of exactly Emma, long-haired Russian Toy terrier; identity fidelity, slender muzzle, tall fringed ears, black-and-tan coat, cream brows and muzzle, realistic eyes, closed mouth, soft warm studio light, dark background, no text”. Generowanie obrazu nie tworzy siatki 3D.

Wariant `emma-avatar.png` wykonano wbudowanym ImageGen: usunięcie tła, zachowanie tożsamości i proporcji zaakceptowanego portretu, całe uszy i frędzle, delikatne wygaszenie dolnej sierści w przezroczystość. Potwierdzono obecność kanału alfa. Dodatkowa maska w rendererach web i SwiftUI wygasza dolną krawędź.
