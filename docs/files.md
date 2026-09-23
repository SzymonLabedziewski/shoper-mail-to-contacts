# Katalog plików

Legenda: **POTRZEBNE** · **POBIERANE** · **GENEROWANE** · **PRZYKŁAD** · **GITIGNORE**

| Plik | Rola |
|---|---|
| `Uruchom.ps1` | POTRZEBNE — to uruchamia użytkownik |
| `Uruchom.bat` / `URUCHOM.bat` | POTRZEBNE — dwuklik; woła `Uruchom.ps1` |
| `README.md` | POTRZEBNE — instrukcja na start |
| `LICENSE` | POTRZEBNE — MIT |
| `config.example.json` | POTRZEBNE (szablon) |
| `config.json` | POTRZEBNE lokalnie, GITIGNORE, **bez hasła** |
| `src/MailToContacts.ps1` | POTRZEBNE — CLI |
| `src/modules/Ui.ps1` | kolory / prompty terminala |
| `src/modules/Setup.ps1` | kreator setup |
| `src/modules/ImapClient.ps1` | MailKit FETCH / SEARCH |
| `src/modules/Orders.ps1` | warstwa 1 — szablon Shoper |
| `src/modules/Signatures.ps1` | warstwa 2 — stopy + pewność imienia |
| `src/modules/Ollama.ps1` | warstwa 3 — opcjonalnie; Ensure-OllamaReady / pull |
| `src/modules/Merge.ps1` | scalanie e-mail / NIP / telefon (notes bez hashy) |
| `src/modules/TextUtil.ps1` | e-mail, telefon, cytaty, `Split-PersonName` |
| `lib/mailkit/*.dll` | POBIERANE (`install-mailkit`), GITIGNORE |
| `samples/fetched/*.txt` | PRZYKŁAD wejścia |
| `samples/mailboxes/*.txt` | PRZYKŁAD LIST |
| `samples/generated/*` | GENEROWANE przez `demo` (te same nazwy plików co żywy run) |
| `data/run_YYYYMMDD_HHMMSS/` | GENEROWANE przez żywy `run`, GITIGNORE |

W każdym katalogu wyniku (`data/run_*` oraz `samples/generated`):

| Plik | Rola |
|---|---|
| `contacts.vcf` | GENEROWANE — książka do importu (UTF-8) |
| `contacts.csv` | GENEROWANE — UTF-8 z BOM |
| `contacts_unified.json` | GENEROWANE |
| `orders_raw.json` | GENEROWANE — sparsowane potwierdzenia |
| `companies_by_nip.json` | GENEROWANE |
| `messages_raw.jsonl` | GENEROWANE — maile oddane do warstwy stopek |
| `extracted_rules.jsonl` | GENEROWANE — trafienia reguł |
| `ai_queue.jsonl` | GENEROWANE — niepewne stopki (Ollama albo sama kolejka) |
| `RAPORT.txt` | GENEROWANE — `orders`, `contacts`, `messages`, `signatures_rules`, `signatures_ai_queue` |

Poza katalogiem wyniku:

| Plik | Rola |
|---|---|
| `schemas/*.json` | kontrakt dla ludzi i AI |
| `docs/INSTRUKCJA.md` | obsługa użytkownika |

Pełny przebieg: `docs/pipeline.md`. Niezmienniki: `AGENTS.md`.
