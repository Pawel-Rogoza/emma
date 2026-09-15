# Propozycja: pliki w aplikacji mobilnej (do decyzji)

Status: **propozycja, nie kontrakt.** `emma-mobile-api.yaml` pozostaje
niezmieniony do Twojej zgody. Ten dokument istnieje, bo cel wymienia „pliki",
a w całym kontrakcie nie ma dla nich ani jednej trasy — i coś trzeba postawić
na stole, żeby dało się to rozstrzygnąć.

## Co już jest w kodzie (potwierdzone)

- Tabela `files`: `parent_type` ∈ `('client','case','report','finance')`,
  `parent_id`, `path`, `original_name`, `mime`, `size`, `uploaded_by`,
  `created_at` (migracja `002_mvp.sql:56`).
- Tabela `file_meta`: `folder`, `version_group_id`, `version_number`,
  `is_current` (migracja `028_file_meta.sql`) — czyli dokument ma wersje,
  a lista pokazuje domyślnie tylko bieżącą.
- Treść leży na dysku: `CRM_DATA_DIR/files/<parent_type>/<parent_id>/`
  (`files.ts:227`, `absoluteFilePath`).
- Panel ma gotowe trasy: `/api/crm/files/[id]` (strumień, `Content-Disposition`
  z kodowaniem UTF-8 w nazwie) i wersje w workspace.
- Aplikacja iOS zna typ encji `'file'` (`dto.ts:28`), ale **nikt go nie
  produkuje** i klient HTTP nie wykonuje ani jednego wywołania plików.

Wniosek: nie budujemy magazynu. Wystawiamy to, co jest, w sposób spójny
z resztą warstwy mobilnej.

## Proponowane trasy (tylko odczyt, na pierwszy krok)

| Trasa | Zwraca |
| --- | --- |
| `GET /api/mobile/v1/cases/{case_id}/files` | lista **bieżących** wersji dokumentów sprawy |
| `GET /api/mobile/v1/clients/{client_id}/files` | to samo dla kartoteki klienta |
| `GET /api/mobile/v1/files/{file_id}` | metadane jednego pliku |
| `GET /api/mobile/v1/files/{file_id}/versions` | wszystkie wersje tej samej grupy |
| `GET /api/mobile/v1/files/{file_id}/content` | treść pliku (strumień, nazwa z `Content-Disposition`) |

Kształt elementu listy:

```json
{
  "id": "file-12",
  "name": "Zaswiadczenie o zatrudnieniu.pdf",
  "folder": "Dokumenty",
  "mime": "application/pdf",
  "size": 184320,
  "version_number": 2,
  "version_group_id": "file-9",
  "is_current": true,
  "created_at": "2026-09-14T09:12:00.000Z",
  "uploaded_by": "user-3"
}
```

Zasady, których nie zamierzam upraszczać:

1. **Dostęp liczony tak samo jak do sprawy i kartoteki.** Plik nie może być
   widoczny dla kogoś, kto nie widzi jego sprawy — korzystamy z tych samych
   reguł co `clients`/`cases`, a nie z nowej interpretacji.
2. **Treść tylko przez trasę z sesją.** Żadnych publicznych linków ani
   bezpośrednich ścieżek: aplikacja pobiera bajty tak samo jak panel, przez
   uwierzytelnione żądanie, z `Cache-Control: no-store`.
3. **Nazwa pliku w nagłówku** tak jak w panelu (kodowanie UTF-8), żeby polskie
   znaki nie rozsypały się przy zapisie na telefonie.
4. **Bezpieczeństwo ścieżki.** Ścieżka bierze się z bazy, a nie z żądania, ale
   przed strumieniowaniem trzeba potwierdzić, że po złożeniu nadal leży
   w katalogu danych — tak samo jak w panelu.

## Świadomie poza pierwszym krokiem

- **Wgrywanie plików z telefonu.** Wymaga limitów rozmiaru i typów, polityki
  nazw, miejsca w `CRM_DATA_DIR`, kontroli RODO i decyzji, kto odpowiada za
  treść. To osobny etap, nie „dodatek do listy".
- Usuwanie, zmiana nazwy, przenoszenie między folderami, udostępnianie na
  zewnątrz.

## Czego potrzebuję od Ciebie

1. **Czy pliki mają być widoczne w aplikacji** (lista + podgląd/pobranie), czy
   zostawiamy je wyłącznie w panelu? Jeśli w panelu — zamykam temat i wykreślam
   go z celu jako świadomie poza zakresem.
2. Czy pierwszy krok ma objąć **także kartotekę klienta**, czy tylko sprawy.
3. Czy pobieranie ma obsługiwać **zakresy (range)** dla dużych plików, czy
   wystarczy zwykły strumień (prościej; PDF i zdjęcia i tak są małe).
4. Czy wgrywanie ma trafić do planu jako kolejny etap, czy w ogóle rezygnujemy.
