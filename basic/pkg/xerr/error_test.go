package xerr

import (
	"testing"
)

func TestError_Error(t *testing.T) {
	type tcase struct {
		err  Error
		want string
	}

	tests := map[string]tcase{
		"ErrNotFound":     {err: ErrNotFound, want: "not found"},
		"ErrAlreadyExist": {err: ErrAlreadyExists, want: "already exists"},
		"Custom":          {err: Error("test error"), want: "test error"},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			if got := tc.err.Error(); got != tc.want {
				t.Errorf("Error() = %v, want %v", got, tc.want)
			}
		})
	}
}
