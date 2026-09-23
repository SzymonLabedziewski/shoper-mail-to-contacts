# Instrukcja — książka adresowa z poczty Shoper

Jeśli właśnie pobrałeś ten folder: otwórz PowerShell tutaj i wpisz `powershell -File .\Uruchom.ps1`. Krótki opis jest w [README](../README.md). Dwuklik `URUCHOM.bat` robi to samo.

Narzędzie robi **jedną rzecz**: z poczty sklepu **Shoper / Shoparena** buduje lokalną książkę adresową (VCF / CSV / JSON).

Ścieżka użytkownika to **jeden kreator** (`Uruchom.ps1`). Osobne komendy CLI (`setup`, `run`, `discover`, `demo`, `selftest`) są w `src/MailToContacts.ps1` — do powtórki albo testu bez poczty, nie zamiast kreatora.

Katalog roboczy: folder z `README.md` i `Uruchom.ps1`.

---

## Uruchomienie

```powershell
cd ścieżka\do\na_repo
powershell -File .\Uruchom.ps1
```

To wszystko. Skrypt sam:

- zapisze ustawienia skrzynki Shoper (`config.json` — **bez hasła**),
- doinstaluje MailKit, jeśli trzeba,
- zapyta o hasło IMAP,
- pokaże foldery i pozwoli wybrać, skąd brać maile,
- pobierze wiadomości i zbuduje książkę.

`config.json` jest lokalny (gitignore) — **nie commituj** go.

---

## Co pyta kreator

(Kolorowy terminal; przed każdym pytaniem pusta linia.)

1. **SelfTest** (Y/n) — szybki test bez sieci (zalecane przy pierwszym uruchomieniu).
2. **E-mail skrzynki Shoper** — host zawsze `s.mail.dcsaas.net`, port 143, STARTTLS. Zapis `config.json` bez hasła.
3. **Stopy** (Y/n) — czy oprócz potwierdzeń zamówień brać też zwykłą korespondencję.
4. **Ollama** (y/N) — tylko gdy stopy = tak. Domyślnie nie. Kreator sam mówi, czy Ollama jest zainstalowana, czy trzeba ją **uruchomić**, i może ją doinstalować (winget) oraz pobrać model. Przy „nie” słabe stopy lądują w `ai_queue.jsonl`.
5. **MailKit** — doinstalowanie DLL, jeśli ich brakuje (na Windows PowerShell 5.1: net48, nigdy net8.0).
6. **Hasło IMAP** — często osobne hasło w panelu poczty Shoper, nie hasło do panelu sklepu. Albo zmienna `IMAP_PASSWORD`.
7. **LIST** — `SCAN` (zielony) i `skip` (szary) z powodem. Potem numery folderów SCAN.
8. **Foldery** — bez domyślnego wyboru. Numery (`1,3` / `1-5` / `11-15`), dokładna nazwa albo `*` = wszystkie SCAN. Sam Enter nic nie wybiera — skrypt pyta ponownie. Potem liczniki: przy włączonych stopkach linia `w tym N potwierdzeń`.
9. **Limit** — najnowsze N na folder (**dokładnie N**, bez dociągania starszych zamówień). Enter = bez limitu, albo wartość z `config.json` (`maxMessagesPerFolder`).
10. **Start** (Y/n) — pobranie i budowa książki. W terminalu: postęp `folder i/n`, potem `pobrano N (zamykam IMAP…)` i `analizuję…`. Przy Ollamie: `Ollama k/n` tylko dla niepewnych stopek. Na końcu `contacts=…` i ścieżka `data\run_*\`.

Konsola: CLI ustawia wyjście na UTF-8, żeby polskie znaki (`potwierdzeń`, `łącznie`, nazwy folderów) nie rozjeżdżały się w Windows PowerShell 5.1. Pliki `.ps1` są UTF-8 z BOM.

---

## Skąd biorą się kontakty

| Warstwa | Źródło | Rola |
|---|---|---|
| 1 | Maile „Potwierdzenie zamówienia…” | Szablon „Dane zamawiającego” — pewne dane klienta |
| 2 | Reszta korespondencji | Stopy / reguły; imię i nazwisko tylko gdy wyglądają na pewne |
| 3 | Ollama (opcjonalnie) | Tylko niepewne stopki; wynik też przechodzi test pewności |

W notatkach kontaktu są **NIP** i **Zamowienia: …**. Hashe podpisów nie trafiają do książki.

### Jak łączone są karty

- ten sam e-mail → jedna karta,
- ten sam NIP i ta sama osoba → scalenie,
- wspólny telefon → scalenie, o ile nie wygląda to na dwie różne osoby,
- sama podobna nazwa firmy lub samo imię bez wspólnego klucza → **nie** łączy (lepiej dwie karty).

Powtórzony ten sam mail (Message-ID) i ta sama stopka (hash) są liczone raz.

---

## Wynik

```text
data\run_YYYYMMDD_HHMMSS\
  contacts.vcf              ← import (Roundcube / Thunderbird / telefon)
  contacts.csv              UTF-8 z BOM (Excel)
  contacts_unified.json
  orders_raw.json
  companies_by_nip.json
  messages_raw.jsonl        maile do stopek (nie zamówienia już wyjęte)
  extracted_rules.jsonl     stopy złapane regułami
  ai_queue.jsonl            słabe stopy; puste wywołanie modelu, gdy Ollama wyłączona
  RAPORT.txt
```

`RAPORT.txt` ma pięć liczników: `orders`, `contacts`, `messages`, `signatures_rules`, `signatures_ai_queue`.

Importuj `contacts.vcf` — to główny plik książki. JSON, VCF i JSONL są UTF-8 (bez BOM); polskie znaki w treści są poprawne.

---

## Tylko Shoper

Kreator jest **wyłącznie** pod pocztę sklepu Shoper / Shoparena (`s.mail.dcsaas.net`).  
Gmail, Outlook itd. nie są obsługiwane.

Hasło: prompt albo zmienna `IMAP_PASSWORD` (nigdy w pliku).

---

## Opcjonalnie: Ollama

Domyślnie wyłączona. Książka powstaje bez niej.

Jeśli w kreatorze wybierzesz **tak**, skrypt sam sprawdza sytuację:

| Co jest na komputerze | Co robi kreator |
|---|---|
| Nic nie zainstalowane | Mówi o tym i pyta, czy zainstalować Ollamę przez `winget` oraz pobrać model (~2 GB) |
| Ollama pobrana, ale nie włączona | Mówi, że trzeba **uruchomić program** (ikona przy zegarze / menu Start) i może wystartować go sam |
| Ollama działa, brak modelu | Pyta, czy wykonać `ollama pull` dla modelu z configu |
| Ollama działa i model jest | Idzie dalej |

Maile zostają na Twoim PC (`http://127.0.0.1:11434`). Ręcznie: [ollama.com/download](https://ollama.com/download) i `ollama pull qwen2.5:3b-instruct-q4_K_M`.

---

## Typowe problemy

| Objaw | Co zrobić |
|---|---|
| Logowanie IMAP nieudane | Hasło IMAP skrzynki (panel poczty), pełny e-mail, IMAP włączony |
| MailKit / LoaderExceptions | Zamknij PowerShell, uruchom znowu `.\Uruchom.ps1` (pobierze właściwe DLL-e) |
| Zero zamówień | W pobranej paczce nie było tematu „Potwierdzenie zamówienia”. Limit N to N najnowszych maili, bez dociągania starszych |
| Zero stopek | Stopy wyłączone w kreatorze albo w wybranych folderach nie ma stopek |
| Dużo linii w `ai_queue.jsonl` | Ollama wyłączona albo daemon nie działa — to kolejka, nie błąd; książka i tak powstaje |
| `Nie można połączyć się z serwerem` / Ollama | Program Ollama nie jest włączony albo nie jest zainstalowany. Kreator pyta i może go uruchomić, zainstalować (winget) i pobrać model. Książka powstaje też bez tego |
| Długa nazwa folderu zawija pasek postępu | Kosmetyka konsoli; licznik i pliki wyniku są poprawne |

---

## Więcej (dla rozwijających kod)

| Plik | Po co |
|---|---|
| [README.md](../README.md) | skrót projektu |
| [pipeline.md](pipeline.md) | trzy warstwy |
| [folders.md](folders.md) | SCAN / skip |
| [../AGENTS.md](../AGENTS.md) | niezmienniki |
| [../SECURITY.md](../SECURITY.md) | hasła, TLS |
| [../PRIVACY.md](../PRIVACY.md) | dane lokalne |
