# Książka adresowa z poczty Shoper

Program czyta pocztę sklepu **Shoper / Shoparena** i zapisuje kontakty do pliku, który wgrywasz do programu pocztowego (Roundcube, Thunderbird, telefon).

Hasło i treść maili zostają na Twoim komputerze.

## Jak uruchomić

Potrzebujesz Windowsa z PowerShellem (jest w systemie).

1. Pobierz ten folder i go rozpakuj.
2. Wejdź do folderu (tam, gdzie leży ten plik i `Uruchom.ps1`).
3. W pasku adresu Eksploratora wpisz `powershell` i naciśnij Enter.
4. W oknie, które się otworzy, wpisz:

```powershell
powershell -File .\Uruchom.ps1
```

Możesz też dwukrotnie kliknąć `URUCHOM.bat` — on tylko uruchamia `Uruchom.ps1`.

5. Odpowiadaj na pytania na ekranie. Na hasło poczty program pyta w oknie i **nie zapisuje go w pliku**.
6. Na końcu pojawi się ścieżka do pliku `contacts.vcf`, w folderze `data\run_…\`. Ten plik importujesz jako książkę adresową.

Szczegóły pytań kreatora: [docs/INSTRUKCJA.md](docs/INSTRUKCJA.md).

## Co program robi

1. Z potwierdzeń zamówień bierze dane klienta (szablon Shoper).
2. Ze zwykłych maili próbuje odczytać stopkę — do książki trafia tylko to, co wygląda na pewne (np. imię i nazwisko zapisane jak nazwa własna).
3. Opcjonalnie lokalna [Ollama](https://ollama.com) na niepewne stopki. Domyślnie wyłączona. Jeśli jej nie masz, kreator to powie i może ją zainstalować (winget) oraz pobrać model. Jeśli już ją masz, musi być **uruchomiona** (nie wystarczy sam instalator).

Przy limicie N pobiera dokładnie N najnowszych maili z folderu — bez dociągania starszych zamówień. Scalanie kart: ten sam e-mail, ten sam NIP + ta sama osoba, wspólny telefon (ostrożnie). Lepiej dwie karty niż złączenie dwóch osób.

W notatce kontaktu są NIP i numery zamówień. Hasło IMAP to zwykle hasło skrzynki z panelu poczty, nie hasło do panelu sklepu.

## Sprawdzenie bez poczty

```powershell
powershell -File .\tests\SelfTest.ps1
powershell -File .\src\MailToContacts.ps1 demo
```

`demo` czyta fikcyjne maile z `samples\fetched\` i zapisuje wynik w `samples\generated\`.

## Dla osób, które rozwijają kod

| Plik | Po co |
|---|---|
| [docs/INSTRUKCJA.md](docs/INSTRUKCJA.md) | obsługa krok po kroku |
| [docs/pipeline.md](docs/pipeline.md) | trzy warstwy i przebieg |
| [AGENTS.md](AGENTS.md) | zasady dla zmian w kodzie |
| [src/MailToContacts.ps1](src/MailToContacts.ps1) | komendy poza kreatorem |

Licencja MIT: [LICENSE](LICENSE). Prywatność: [PRIVACY.md](PRIVACY.md).
