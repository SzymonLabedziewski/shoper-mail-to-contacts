# `src/` — PowerShell

Wejście użytkownika: [`../Uruchom.ps1`](../Uruchom.ps1) albo [`MailToContacts.ps1`](MailToContacts.ps1).

```
src/
  MailToContacts.ps1      # CLI: setup | run | demo | discover | …
  modules/
    Ui.ps1                # kolory terminala, prompty, lista SCAN/skip
    Setup.ps1             # kreator (SelfTest → config → stopy → foldery → run)
    PlIds.ps1             # NIP / REGON / IBAN
    TextUtil.ps1          # e-mail, telefon, cytaty, imiona (title-case = pewne)
    Providers.ps1         # preset IMAP Shoper (s.mail.dcsaas.net:143 STARTTLS)
    FolderPolicy.ps1      # SPECIAL-USE / Sent / Trash + wybór numerów
    Orders.ps1            # warstwa 1 — adapter Shoper
    Signatures.ps1        # warstwa 2 — stopy + grounding + roster
    Merge.ps1             # e-mail / NIP / telefon → książka (notes bez hashy)
    Export.ps1            # VCF / CSV
    Config.ps1            # config.json (bez hasła)
    Ollama.ps1            # warstwa 3 — Ensure-OllamaReady / pull / chat
    ImapClient.ps1        # MailKit CONNECT / FETCH / SEARCH (limit = N najnowszych)
    Pipeline.ps1          # demo + Invoke-ImapLiveRun
  scripts/
    Install-MailKit.ps1   # NuGet → lib/mailkit (net48 na PS 5.1)
```

Komendy: `powershell -File .\src\MailToContacts.ps1 help`

`MailToContacts.ps1` ustawia wyjście konsoli na UTF-8. Żywy `run` drukuje pasek per folder, potem `pobrano` / `zamykam IMAP` / `analizuję`, a przy Ollamie `Ollama k/n` tylko dla niepewnych stopek.
