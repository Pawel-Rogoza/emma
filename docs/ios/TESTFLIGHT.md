# Emma Gemini Live na iPhonie przez TestFlight

Build powstaje na macOS w GitHub Actions z gałęzi `feat/gemini-live-voice`.
Schemat `Emma-Staging` używa `pl.kancelaria.emma.staging`, zespołu
`QZ25N94YZ8`, backendu `https://advokat-varshava.pl` i Gemini 3.8 Live.
Numer builda to identyfikator przebiegu GitHub Actions, więc kolejne wysyłki
nie powtarzają numeru.

## Jednorazowe ustawienie konta Apple

1. W [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list)
   sprawdź, czy istnieje jawny App ID `pl.kancelaria.emma.staging` w zespole
   `QZ25N94YZ8`. Jeśli nie, zarejestruj go.
2. W [App Store Connect](https://appstoreconnect.apple.com/apps) utwórz aplikację
   i wybierz ten sam bundle ID. Nazwa może brzmieć `Emma Beta`.
3. Potrzebny jest certyfikat **Apple Distribution** z kluczem prywatnym,
   wyeksportowany jako `.p12`, oraz profil **App Store Connect** dla dokładnie
   tego App ID i certyfikatu. Profil `.mobileprovision` można pobrać z witryny
   Apple Developer. Sam plik `.cer` nie wystarczy do podpisania buildu:
   potrzebny jest także odpowiadający mu klucz prywatny.
4. W App Store Connect → **Users and Access → Integrations → App Store Connect API**
   włącz dostęp do API (jeżeli nie jest aktywny) i utwórz klucz zespołu z rolą
   pozwalającą przesyłać buildy (co najmniej App Manager). Zapisz `Key ID`,
   `Issuer ID` i pobrany raz plik `.p8`.

## Sekrety repozytorium GitHub

W `Pawel-Rogoza/emma` → **Settings → Secrets and variables → Actions** ustaw:

| Nazwa | Wartość |
| --- | --- |
| `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64` | zawartość `.p12` zakodowana Base64, w jednej linii |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | hasło do `.p12` |
| `IOS_DISTRIBUTION_PROFILE_BASE64` | zawartość `.mobileprovision` zakodowana Base64, w jednej linii |
| `ASC_KEY_ID` | Key ID klucza App Store Connect API |
| `ASC_ISSUER_ID` | Issuer ID klucza API |
| `ASC_PRIVATE_KEY_P8` | pełna zawartość pliku `.p8`, z liniami BEGIN/END |

Na Linuksie pojedynczą linię Base64 otrzymasz poleceniem
`base64 -w 0 nazwa-pliku`; na macOS: `base64 -i nazwa-pliku | tr -d '\n'`.
Nie umieszczaj certyfikatu, kluczy ani profilu w repozytorium lub zgłoszeniu.

## Pierwszy i następne buildy

W zakładce **Actions** repozytorium wybierz `Emma · TestFlight`, potem
**Run workflow** z gałęzi `master`. Workflow pobiera kod aplikacji z
`feat/gemini-live-voice`, generuje projekt Xcode, podpisuje schemat Staging
i wysyła `.ipa` do App Store Connect. Przed pierwszą wysyłką warto otworzyć
`ios/Config/Staging.xcconfig` w tej gałęzi i potwierdzić dostawcę `gemini_live`.

Po przetworzeniu buildu przez Apple: App Store Connect → aplikacja Emma Beta →
**TestFlight → Internal Testing**. Utwórz grupę wewnętrzną, dodaj swoje konto
App Store Connect i przypisz build do grupy. Na iPhonie zainstaluj TestFlight,
przyjmij zaproszenie i zainstaluj Emmę. Dalsze wersje wymagają ponownego
uruchomienia workflow; można je przypisywać do tej samej grupy.

TestFlight jest testem na fizycznym telefonie: pozwala ocenić mikrofon,
odtwarzanie i rozmowę Gemini, których symulator nie weryfikuje wiarygodnie.
Apple może zażądać odpowiedzi na pytania o szyfrowanie przed udostępnieniem
nowego buildu. Build pozostaje dostępny do testowania przez 90 dni.
