# `.gitignore`

Źródło prawdy to plik [`.gitignore`](../.gitignore) w korzeniu `na_repo` (nie ta notatka).

Pomijane w gicie:

- `config.json`, `.env`, `.env.*`, `*.secure` — konfiguracja lokalna (hasło i tak nie trafia do `config.json`)
- `data/*` oprócz `data/README.md`, oraz `runs/`, `out/`, `out-ci/` — żywe przebiegi i wynik CI
- `lib/mailkit/*.dll`, `*.xml`, `*.pdb`, `tfm.txt` — DLL-e z `install-mailkit`
- `.venv/`, `__pycache__/`, `*.pyc`, `*.egg-info/`, `.pytest_cache/` — resztki Pythona, poza CLI
- `klienci_zamowienia_*/`, `wiadomosci_*/`, `kontakty_shoper_*/`, `tresc_*/`, `imap_export_*/`, `import_log_*/` — dumpy prawdziwej poczty
- `Thumbs.db`, `Desktop.ini`, `.DS_Store`, `*.log`

`samples/` (fikcyjne `@example.com`) jest commitowane.
