# Shoper/Shoparena IMAP — kreator v1 ustawia tylko ten host (docs/providers.md).
# Hasło nigdy nie jest tu przechowywane.

function Get-ShoperImapPreset {
    [PSCustomObject]@{
        Host = 's.mail.dcsaas.net'
        Port = 143
        Tls  = 'starttls'
        Note = 'Shoper/Shoparena: STARTTLS 143 (sprawdzone). Jeśli panel daje IMAPS, użyj 993/ssl.'
    }
}
