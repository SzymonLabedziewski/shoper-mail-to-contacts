# Bezpieczeństwo

## Hasła

- Wpisuj hasło w prompcie (`SecureString`) albo przez `IMAP_PASSWORD`.
- **Nigdy** nie zapisuj hasła w `config.json` (kreator też tego nie robi).
- Nie commituj `config.json`, `.env`, dumpów skrzynki.
- Nie przekazuj hasła w historii poleceń.
- Shoper: często **osobne hasło IMAP** skrzynki w panelu poczty — nie mylić z hasłem do panelu sklepu. Przy błędzie logowania skrypt wypisuje krótką ściągę (user / host / IMAP włączony).

## TLS

MailKit weryfikuje certyfikat serwera. `imap.insecureSkipCert` jest świadomą, odradzaną flagą.

Domyślnie: STARTTLS na porcie **143** (`s.mail.dcsaas.net`). Alternatywa z panelu: IMAPS **993** / `ssl`.

## Gmail / Microsoft 365

Nie są w kreatorze v1. Gdyby ktoś ręcznie wpisał host w JSON: IMAP wymaga **hasła aplikacji**, nie zwykłego hasła konta.

## Zgłaszanie błędów

Nie wklejaj do issue prawdziwych maili, haseł, NIP-ów klientów ani `messages_raw.jsonl`.
