# Foldery IMAP — układ skrzynki NIE jest wymagany

## Domyślna polityka (`discover` / LIST)

1. **Rekurencyjnie** zbierz wszystkie foldery (INBOX + dzieci + personal namespace).
2. **SCAN** = wszystko poza Sent / Wysłane / Trash / Kosz / Junk / Spam / Drafts / Szkice / Archive / …
3. Brak `FIRMY`, `OSOBY PRYWATNE` albo `[Shop]` **nie zmienia** zachowania — wystarczy sam INBOX.

W kreatorze: `SCAN` na zielono, `skip` na szaro. Powód w nawiasie:

| Powód | Znaczenie |
|---|---|
| `inbox` | sam INBOX |
| `inbox_or_custom` | własny folder / `[Shop]` — zostaje |
| `name_heuristic` | nazwa jak Sent, Trash, Junk, Drafts, Archive |
| `imap_special_use` | serwer oznaczył folder flagą SPECIAL-USE |

Komenda `discover` wypisuje to samo bez kolorów (`SCAN` / `skip`).

Przykłady w `samples/mailboxes/`:

| Plik | Co pokazuje |
|---|---|
| `inbox-only.txt` | Wszystko w INBOX |
| `generic-folders.txt` | INBOX + własne podfoldery |
| `shoper-folders.txt` | Opcjonalny układ Shoper (FIRMY / OSOBY / Shop) |

`folders.include` w `config.json` zawęża listę tylko gdy użytkownik tego chce. Pusta lista = „całe drzewo poza śmieciami”.

## Wybór w kreatorze / interaktywnym `run`

**Nie ma domyślnego folderu** (żaden sklep nie ma uniwersalnej ścieżki „Potwierdzenie zamówienia”). Musisz wskazać:

| Wpis | Znaczenie |
|---|---|
| `1,3` albo `1-5` | Numery z listy SCAN |
| dokładna nazwa | np. `INBOX.[Shop] Potwierdzenie zamówienia` |
| `*` / `wszystkie` | Wszystkie SCAN |
| pusty Enter | Nic — skrypt pyta ponownie |

Limit: najnowsze N na folder — **twardy** limit (Enter = bez limitu albo `imap.maxMessagesPerFolder` z configu). Nie dociągamy osobno starszych potwierdzeń poza tą paczką. Przy włączonych stopkach licznik ma wcięcie i `w tym N potwierdzeń` (stan całego folderu, nie tylko paczki).

Pobieranie idzie **kolejno**, osobne połączenie IMAP na folder. Pasek: `folder i/n [nazwa] k/N` oraz `łącznie`. Po folderze: `pobrano N (zamykam IMAP…)` i `analizuję…`. Bardzo długa nazwa folderu może zawinąć jedną linię postępu w wąskiej konsoli — na pliki wyniku to nie wpływa.

Gdy `signatures.enabled = false`, SEARCH i FETCH biorą tylko tematy potwierdzeń zamówień.

## Potwierdzenia ≠ konkretny folder

Szukamy po **fragmencie tytułu** `Potwierdzenie zamówienia` (gdziekolwiek w Subject: `Fwd:…`, `Re:…`, prefix OK) albo po bloku `Dane zamawiającego:` w treści. Folder jest tylko metadaną źródła — u każdego sklepu Shoper nazwy folderów mogą być inne.
