package static

import (
	"embed"
	"fmt"
	"io/fs"
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
