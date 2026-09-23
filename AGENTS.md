# AGENTS.md

Ten plik jest dla osób zmieniających kod i dla agentów AI. Żeby tylko zbudować książkę adresową, otwórz [README.md](README.md) i uruchom `.\Uruchom.ps1`.

Instructions for coding agents (and humans) implementing or extending this repo.

## Goal

Turn a **Shoper/Shoparena** mailbox into a contact book **on the user's machine**. Launch scripts and parsers are **PowerShell**. Three layers:

1. **Structured mail** (order confirmation) — deterministic parser (`ConvertFrom-ShoperOrder`).
2. **Unstructured incoming mail** — signature rules (`Get-SignatureHits`).
3. **Optional local Ollama** — only uncertain signature hits (`aiConfidenceBelow`, `uncertain_*`). Roster / all-caps product lines are not treated as a person. `Ensure-OllamaReady` may install/start/pull; a dead daemon must not abort the run (`ai_queue.jsonl`).

Output: contact book → JSON + CSV + vCard 3.0. Contact `notes` contain **NIP** and **Zamowienia** only — **never** write signature SHA hashes into the address book. Never upload mailbox content to a cloud LLM from this repo.

## Do not copy the original prototype 1:1

The sibling workspace (`eksport-klienci-zamowienia.ps1`, hand-rolled IMAP, hardcoded `FIRMY` folders) is a **proven product prototype**, not the public design.

Keep the **heuristics and safety rules**. Replace the **transport**:

- IMAP = **MailKit 4.17** (`src/modules/ImapClient.ps1`), not raw TCP.
- Folder policy = SPECIAL-USE + name heuristics, never require `INBOX.FIRMY`.
- Wizard must **not** default-select any Shop order folder — every shop layout differs; user must pick numbers / `*` / name.
- Identifiers = official NIP/REGON/IBAN checksums (`src/modules/PlIds.ps1`).
- Signature hash = SHA-256 for internal dedupe only — not exported to VCF/CSV notes.
- LLM = Ollama `/api/chat` with JSON schema `format` + `Remove-HallucinatedFields`.

Pliki `.ps1` są **UTF-8 z BOM**. Wejście CLI (`MailToContacts.ps1`) ustawia `[Console]::OutputEncoding` na UTF-8 bez BOM, żeby polski tekst w konsoli Windows PowerShell 5.1 nie był czytany jako Windows-1250.

MailKit na **Windows PowerShell 5.1**: TFM `net48` / `net462` (nigdy `lib\net8.0`). Główna ścieżka: `Uruchom.ps1` / `setup` — Shoper-only config, **bez** hasła w pliku. Defaults: `signatures.enabled=true`, `signatures.useOllama=false`.

## Invariants (`tests/SelfTest.ps1` must not regress)

1. Skip messages where `From` equals the mailbox user or `config.self.emails`, **except** Shoper order confirmations (sent by the shop). Those go to `ConvertFrom-ShoperOrder`, not to signature extraction.
2. Skip Sent/Trash/Junk/Drafts. Custom folders and `[Shop]` stay **in**. Flat INBOX-only mailboxes must work.
3. Deduplicate by `Message-ID`.
4. Strip quoted history before signature extraction.
5. Order confirmations: subject **fragment** `Potwierdzenie zamówienia`. Skip `Re:`/`Odp:` order mails that lack an email field.
6. Polish **NIP checksum**. Same idea for REGON/IBAN-PL.
7. Same email → one contact. Same NIP + same person → merge. Shared phone may merge unless names look like two people. Different full names → do not merge. No fuzzy merge on company name alone.
8. LLM fields must appear in the signature `block`. After Ollama, re-check person name with `Split-PersonName` (title-case tokens).
9. Password never written to `config.json`. Clear auth-failure message (IMAP password vs panel password).
10. Samples use `@example.com` only. Example NIP `5252345675` is valid; `5252345678` is not.
11. Empty folder pick = empty selection (wizard re-asks). `*` = all SCAN.
12. Contact notes must not contain `Podpisy:` / signature hashes.
13. `maxMessagesPerFolder` / wizard limit N = exactly the N newest UIDs in that folder (no extra SEARCH for older order mails).
14. Certain person names need at least two title-case tokens (`Test-NameToken`). All-caps lines and multi-line ALL-CAPS rosters are not certain names.

## Contracts

JSON Schema in `schemas/` (camelCase):

- `order-raw.schema.json`
- `message-raw.schema.json`
- `extracted-fields.schema.json`
- `contact.schema.json`

Golden input: `samples/fetched/*`.  
Golden behaviour: `tests/SelfTest.ps1` then `MailToContacts.ps1 demo`.

## Parallelism

| Stage | Bound | Do this |
|---|---|---|
| LIST folders | 1 RTT | one MailKit connection |
| FETCH bodies | I/O | **Kolejno**, osobny `ImapClient` na folder (v1 nie puszcza puli równoległej). `imap.parallelFolders` to tylko zapowiedź. Nigdy nie dziel jednego klienta między wątki. |
| Order / signature regex | CPU | in-process |
| Ollama | saturated | **sequential** HTTP |

## When adding an order adapter

1. Add `ConvertFrom-<Shop>Order` next to `ConvertFrom-ShoperOrder`.
2. Do not change `Contact` shape.
3. Add `samples/fetched/order-*-<shop>.txt` and an assert in `tests/SelfTest.ps1`.

## When touching merge

Prefer false negatives (two cards) over merging two people. Do not put signature hashes into `notes`.
