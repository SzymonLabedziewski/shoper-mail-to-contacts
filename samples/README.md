# samples/

Fikcyjna skrzynka (`sklep@example.com`). Prawdziwych dumpów klientów **nigdy** nie commitować.

## Wejście (`fetched/`) — to, co IMAP oddaje po MIME

| Plik | Znaczenie |
|---|---|
| `order-1001-shoper.txt` | Potwierdzenie Shoper — osoba prywatna |
| `order-1002-shoper.txt` | Potwierdzenie — firma + NIP `5252345675` |
| `mail-company-signature.txt` | Zwykły mail — stopa firmowa |
| `mail-person-signature.txt` | Zwykły mail — krótka stopa (kandydat do AI) |
| `mail-quoted-thread.txt` | Odpowiedź — cytaty muszą zostać obcięte |

Opcjonalnie JSONL: `orders.jsonl`, `messages.jsonl`. `Invoke-OfflinePipeline` czyta `*.txt`, gdy brak JSONL.

## Układ folderów (`mailboxes/`)

- `inbox-only.txt` — wszystko w INBOX
- `generic-folders.txt` — INBOX + własne podfoldery + Sent/Trash
- `shoper-folders.txt` — opcjonalny układ Shoper (`FIRMY` / `OSOBY` / `[Shop]`)

Narzędzie skanuje **całe drzewo**; brak podfolderów nie blokuje `run`. Kreator **nie** wybiera automatycznie folderu zamówień — użytkownik podaje numery / `*` / nazwę. Temat zamówienia = fragment `Potwierdzenie zamówienia` gdziekolwiek w Subject.

## Wyjście (`generated/`)

Zapisuje `powershell -File src/MailToContacts.ps1 demo` (zamówienia + stopy; Ollama wyłączona). Notatki: NIP + zamówienia, **bez** `Podpisy: <hash>`. Imię i nazwisko w stopkach tylko gdy wyglądają na pewne. Źródło prawdy: `SelfTest.ps1`.
