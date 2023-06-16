package cat

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/KitRUM/golang-blueprint/basicrest/pkg/log"
)

func TestTransport_createCat(t *testing.T) {
	type tcase struct {
		service Service
	}

	tests := map[string]tcase{
		"": {},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			handler, err := NewTransport(tc.service, log.DisabledLogger())
			if err != nil {
				t.Fatalf("Unexpected error: %v", err)
			}

			server := httptest.NewServer(handler)

			t.Cleanup(func() { server.Close() })

			http.Get(server.URL)
		})
	}
}
