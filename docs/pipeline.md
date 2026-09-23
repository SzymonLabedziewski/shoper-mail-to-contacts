# Pipeline (PowerShell)

```text
Uruchom.ps1  /  MailToContacts.ps1 setup
  → SelfTest (opcjonalnie)
  → config.json (Shoper IMAP, bez hasła)
  → stopy?  →  Ollama? (Ensure-OllamaReady: instalacja / start / model)
  → MailKit + hasło IMAP
  → LIST (SCAN / skip)
  → wybór folderów (bez domyślnego) + limit N (= N najnowszych, twardy)
  → run
        MailKit FETCH kolejno (osobne połączenie na folder, pasek postępu)
          → zamykam IMAP… / analizuję…
          → ConvertFrom-ShoperOrder     (warstwa 1; nie-zamówienia odpadają przed HTML)
          → Get-SignatureHits           (warstwa 2; pewne imię = title-case)
          → Invoke-OllamaExtract        (warstwa 3; tylko niepewne, jeśli useOllama i daemon działa)
          → Merge-SignatureHits         (e-mail / NIP+osoba / telefon; ostrożnie)
          → contacts.vcf / .csv / .json
            + orders_raw.json, companies_by_nip.json
            + messages_raw.jsonl, extracted_rules.jsonl, ai_queue.jsonl, RAPORT.txt
            notes = NIP + Zamowienia  (bez hashy podpisów)
```

**Limit N** = dokładnie N najnowszych UID z folderu. Brak dociągania starszych potwierdzeń SEARCH.

**Pewność stopki:** imię i nazwisko tylko przy zapisie jak nazwa własna (Wielka + małe). Same wielkie litery, hasła oferty, listy do graweru (`roster`) nie wchodzą do książki jako osoba. Niepewne → Ollama albo puste imię + sam e-mail.

Gdy `signatures.useOllama = false` albo Ollama nie odpowiada: warstwa 3 nie woła modelu; słabe stopy zostają w `ai_queue.jsonl`. Run i tak kończy VCF.

Gdy `signatures.enabled = false`:

```text
FETCH tylko SEARCH SubjectContains „Potwierdzenie zamówienia…”
  → ConvertFrom-ShoperOrder → VCF
```

Bez sieci:

```text
selftest → demo (samples/fetched → samples/generated)
```
