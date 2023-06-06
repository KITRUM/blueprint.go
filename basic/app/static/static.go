package static

import (
	"embed"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
)

//go:embed migrations/*.sql
var static embed.FS

// Static returns all embedded static as embed.FS.
func Static() embed.FS { return static }

func Migrations() (fs.FS, error) {
	sub, subErr := fs.Sub(static, "migrations")
	if subErr != nil {
		return nil, fmt.Errorf("failed to find migrations folder: %w", subErr)
	}

	return sub, nil
}

func PlaceCerts() error {
	const fileMod = 0o600

	sub, subErr := fs.Sub(static, "certs")
	if subErr != nil {
		return fmt.Errorf("failed to find certs folder: %w", subErr)
	}

	dir, dirErr := os.Getwd()
	if dirErr != nil {
		return fmt.Errorf("failed to get current directory: %w", dirErr)
	}

	cert, openCertErr := fs.ReadFile(sub, "cert.pem")
	if openCertErr != nil {
		return fmt.Errorf("failed to read cert file: %w", subErr)
	}

	if err := os.WriteFile(filepath.Join(dir, "cert.pem"), cert, fileMod); err != nil {
		return fmt.Errorf("failed to place cert.pem: %w", err)
	}

	key, openKeyErr := fs.ReadFile(sub, "key.pem")
	if openKeyErr != nil {
		return fmt.Errorf("failed to open key file: %w", subErr)
	}

	if err := os.WriteFile(filepath.Join(dir, "key.pem"), key, fileMod); err != nil {
		return fmt.Errorf("failed to place key.pem: %w", err)
	}

	return nil
}
