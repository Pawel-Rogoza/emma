# Zasady pracy w repozytorium Emma

## Wersjonowanie aplikacji iOS

- Przy każdej zmianie w `ios/**`, która trafia do `master` (a więc na TestFlight),
  podbij `MARKETING_VERSION` w `ios/project.yml` (np. 0.1.1 → 0.1.2).
  Właściciel rozpoznaje nowe wydanie w TestFlight po tym numerze.
- Numer buildu (`CURRENT_PROJECT_VERSION`) ustawia automatycznie workflow
  TestFlight (`GITHUB_RUN_ID`) — nie zmieniaj go ręcznie.
