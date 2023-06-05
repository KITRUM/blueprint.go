// Package xerr holds common errors for all the application logic.
package xerr

// Compilation time checks for interface implementation.
var (
	_ error = Error("") //nolint: errcheck
)

const (
	// ErrNotFound indicates that requested entity was not found.
	ErrNotFound Error = "not found"

	// ErrAlreadyExists indicates an attempt to create an entity
	// which is failed because such entity already exists.
	ErrAlreadyExists Error = "already exists"
)

// Error represents an package level xerr.
type Error string

func (e Error) Error() string { return string(e) }
