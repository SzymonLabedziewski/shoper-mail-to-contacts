# `config.example.json` — szablon

Skopiuj do `config.json` (GITIGNORE) albo użyj `Uruchom.ps1` / `init`. **Hasła tu nie ma** — prompt albo `IMAP_PASSWORD`.

Aktualny kształt (zgodny z `config.example.json` w korzeniu):

```json
{
  "imap": {
    "host": "s.mail.dcsaas.net",
    "port": 143,
    "tls": "starttls",
    "user": "",
    "insecureSkipCert": false,
    "parallelFolders": 3,
    "markSeen": false,
    "maxMessagesPerFolder": 0
  },
  "self": {
    "emails": ["sklep@example.com"],
    "phones": [],
    "nips": []
  },
  "folders": {
    "include": [],
    "excludeNameRegex": "(?i)(Sent|Wysłane|Trash|Kosz|Junk|Spam|Drafts|Szkice|Archive|Archiwum|Niechciane|Templates)"
  },
  "orders": {
    "enabled": true,
    "adapter": "shoper"
  },
  "signatures": {
    "enabled": true,
    "useOllama": false,
    "aiConfidenceBelow": 0.45
  },
  "ollama": {
    "url": "http://127.0.0.1:11434",
    "model": "qwen2.5:3b-instruct-q4_K_M",
    "recommendedModel": "qwen3:4b-instruct-2507"
  },
  "output": {
    "dir": "./data"
  }
}
```

| Pole | Znaczenie |
|---|---|
| `imap.host` / `port` / `tls` | Shoper: `s.mail.dcsaas.net`, `143`, `starttls` (albo `993` + `ssl`) |
| `imap.maxMessagesPerFolder` | `0` = bez limitu; kreator i tak pyta. Przy N > 0: dokładnie N najnowszych maili na folder |
| `self.emails` | Adresy sklepu — pomijane w stopkach; potwierdzenia zamówień i tak brane |
| `folders.include` | `[]` = całe drzewo poza exclude |
| `orders.enabled` | Warstwa 1 — szablon potwierdzeń |
| `signatures.enabled` | Warstwa 2 — stopy (domyślnie **true**) |
| `signatures.useOllama` | Warstwa 3 — tylko niepewne stopy (domyślnie **false**); kreator sprawdza daemon i model |
| `signatures.aiConfidenceBelow` | Próg reguł → kolejka AI / Ollama |

Kreator (`setup`) zapisuje Shoper + e-mail i pyta o stopy / Ollamę. Nie wybiera automatycznie folderu „Potwierdzenie zamówienia”.
