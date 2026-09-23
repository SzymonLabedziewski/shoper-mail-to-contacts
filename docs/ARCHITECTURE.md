# Architektura

Ten plik jest dla osób, które zmieniają kod. Uruchomienie dla użytkownika: [README](../README.md) i `.\Uruchom.ps1`.

## Trzy warstwy

1. **Potwierdzenia zamówień** — stały szablon Shoper, pewne kontakty.
2. **Reszta poczty** — reguły stopek; do książki tylko pewne pola (imię/nazwisko w zapisie title-case).
3. **Ollama** — tylko niepewne stopki (`aiConfidenceBelow`, flagi `uncertain_*`).

Transport to MailKit. Ekran to kreator tylko pod Shoper (`Uruchom.ps1`). Domyślnie stopki są włączone, Ollama wyłączona. W notatkach kontaktu są NIP i numery zamówień, bez hashy podpisów.

## Dlaczego MailKit, a nie własny IMAP

Prototyp mówił IMAP ręcznie (TCP, STARTTLS na **143**, własne parsowanie MIME). To wystarczyło do sprawdzenia produktu. Do publicznego repozytorium się nie nadaje: własne parsery psują się na nietypowych serwerach i kodowaniach.

**MailKit 4.17** i **MimeKit** to utrzymywany stos .NET. Windows PowerShell 5.1 potrzebuje bibliotek **net48 / net462** (nigdy `net8.0`). PowerShell 7 może wziąć `net8.0`. Przy `ReflectionTypeLoadException` uruchom `install-mailkit` w nowym oknie PowerShell.

## Równoległość

```text
discover  : jedno połączenie, LIST
run       : każdy wybrany folder → własne Connect + FETCH (kolejno)
zamówienia / stopki : w tym samym procesie
Ollama    : jedno po drugim
```

Nie współdziel jednego `ImapClient` między wątkami. `imap.parallelFolders` to tylko zapowiedź. W tej wersji pobieranie jest kolejne. Limit N = N najnowszych UID (twardy). CLI ustawia wyjście konsoli na UTF-8. Parser zamówienia odpada przed zamianą HTML na tekst, dopóki temat nie wygląda na „Potwierdzenie zamówienia” albo treść nie ma „Dane zamawiaj”.

## Model językowy

Kreator: `Ensure-OllamaReady` (instalacja winget / start programu / `ollama pull`). Przy run: ping `/api/tags`; brak daemona nie wywala skryptu — kolejka w `ai_queue.jsonl`.

Zostaw sprawdzanie, czy pole modelu występuje w stopce (`Remove-HallucinatedFields`), oraz ponowny test imienia (`Split-PersonName` / title-case) po odpowiedzi modelu.

- Słabszy komputer: `qwen2.5:3b-instruct-q4_K_M`
- Więcej RAM: `qwen3:4b-instruct-2507`
- Domyślnie `signatures.useOllama` = **false**

W domyślnej ścieżce nie ma chmurowego modelu (dane osobowe).

## Foldery i merge

Najpierw flagi SPECIAL-USE (`\Sent`, `\Trash`, `\Junk`, `\Drafts`), potem nazwa. Użytkownik sam wybiera foldery.

Scalanie: ten sam e-mail; NIP + ta sama osoba; wspólny telefon gdy nie wygląda na dwie osoby. Lepiej dwie karty niż złączenie dwóch ludzi. Brak scalania po samym podobnym imieniu lub nazwie firmy bez wspólnego klucza.

## Co jest publiczne

- Program PowerShell → VCF / CSV / JSON.
- `extras/roundcube/` to tylko opis opcjonalnego importu, nie część uruchomienia.

## Nazwy pól

`ConvertTo-Json` zapisuje **camelCase**. Takie same nazwy są w `schemas/`. Nie przechodź na snake_case.
