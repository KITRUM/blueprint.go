package cat

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/KitRUM/golang-blueprint/basicrest/pkg/log"
	"github.com/KitRUM/golang-blueprint/basicrest/pkg/xerr"
	"github.com/maxatome/go-testdeep/td"
)

func TestTransport_createCat(t *testing.T) {
	type tcase struct {
		service Service
		payload []byte

		wantStatus int
		wantBody   []byte
	}

	tests := map[string]tcase{
		"201 Created": {
			service: &mockService{
				createCatFunc: func(ctx context.Context, name, breed string, age uint32) error {
					return nil
				},
			},
			payload: func() []byte {
				b, _ := json.Marshal(&struct {
					Name  string `json:"name"`
					Breed string `json:"breed"`
					Age   uint32 `json:"age"`
				}{
					Name:  "test",
					Breed: "test-breed",
					Age:   10,
				})

				return b
			}(),

			wantStatus: http.StatusCreated,
			wantBody:   []byte(``),
		},
		"409 Conflict": {
			service: &mockService{
				createCatFunc: func(ctx context.Context, name, breed string, age uint32) error {
					return xerr.ErrAlreadyExists
				},
			},
			payload: func() []byte {
				b, _ := json.Marshal(&struct {
					Name  string `json:"name"`
					Breed string `json:"breed"`
					Age   uint32 `json:"age"`
				}{
					Name:  "test",
					Breed: "test-breed",
					Age:   10,
				})

				return b
			}(),
			wantStatus: http.StatusConflict,
			wantBody:   []byte("Conflict\n"),
		},
		"400 Bad Request": {
			service: &mockService{
				createCatFunc: func(ctx context.Context, name, breed string, age uint32) error {
					return nil
				},
			},
			payload:    func() []byte { return []byte(`{`) }(),
			wantStatus: http.StatusBadRequest,
			wantBody:   []byte("Bad Request\n"),
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			handler, err := NewTransport(tc.service, log.DisabledLogger())
			td.CmpNoError(t, err)

			server := httptest.NewServer(handler)

			t.Cleanup(func() { server.Close() })

			req, err := http.NewRequest(http.MethodPost, server.URL, bytes.NewBuffer(tc.payload))
			td.CmpNoError(t, err)

			res, err := http.DefaultClient.Do(req)
			td.CmpNoError(t, err)
			td.Cmp(t, res.StatusCode, tc.wantStatus)

			body, err := io.ReadAll(res.Body)
			td.CmpNoError(t, err)

			td.Cmp(t, string(body), string(tc.wantBody))
		})
	}
}

type mockService struct {
	getCatByIDFunc func(ctx context.Context, id string) (*Cat, error)
	createCatFunc  func(ctx context.Context, name, breed string, age uint32) error
}

func (m *mockService) GetCatByID(ctx context.Context, id string) (*Cat, error) {
	return m.getCatByIDFunc(ctx, id)
}

func (m *mockService) CreateCat(ctx context.Context, name, breed string, age uint32) error {
	return m.createCatFunc(ctx, name, breed, age)
}
