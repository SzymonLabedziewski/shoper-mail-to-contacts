# Dostawcy IMAP

To narzędzie w **kreatorze v1** jest **tylko pod Shoper / Shoparena** (poczta sklepu).

| Platforma | Host | Port | TLS | Uwaga |
|---|---|---|---|---|
| Shoper / Shoparena / dcsaas | `s.mail.dcsaas.net` | 143 | STARTTLS | sprawdzone; kreator ustawia to zawsze |
| (opcjonalnie w JSON) | to samo | 993 | ssl | jeśli panel skrzynki wymaga IMAPS |

Hasło: prompt `SecureString` albo `IMAP_PASSWORD` — **nigdy** do `config.json`.  
Często jest to **osobne hasło IMAP** skrzynki w panelu Shoper (nie hasło logowania do panelu sklepu).

Własna domena (np. `sklep@firma.pl`) to normalny przypadek — host i tak jest `s.mail.dcsaas.net`.

Gmail / Outlook / WP **nie są** w kreatorze v1.
