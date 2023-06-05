package cat

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"

	"github.com/KitRUM/golang-blueprint/basicrest/pkg/log"
	"github.com/KitRUM/golang-blueprint/basicrest/pkg/xerr"
	"github.com/go-chi/chi/v5"
	"github.com/graphql-go/graphql"
	"github.com/graphql-go/handler"
)

var (
	gqlCatType = graphql.NewObject(graphql.ObjectConfig{
		Name: "Cat",
		Fields: graphql.Fields{
			"id":          &graphql.Field{Type: graphql.String},
			"name":        &graphql.Field{Type: graphql.String},
			"description": &graphql.Field{Type: graphql.String},
			"age":         &graphql.Field{Type: graphql.Int},
		},
	})
)

// Transport represents an HTTP transport for interaction with the Service logic.
type Transport struct {
	router chi.Router
	log    log.Logger

	service Service
}

// NewTransport returns a pointer to a new instance of Transport.
func NewTransport(service Service, logger log.Logger) (*Transport, error) {
	t := Transport{
		router:  chi.NewRouter(),
		log:     logger,
		service: service,
	}

	// Initialize routes.
	t.router.Get("/{id}", t.catByID)
	t.router.Post("/", t.createCat)

	// Initialize GraphQL schema.

	gqlSchema, gqlSchemaErr := graphql.NewSchema(graphql.SchemaConfig{
		Query: graphql.NewObject(graphql.ObjectConfig{
			Name: "Query",
			Fields: graphql.Fields{
				"getCat": &graphql.Field{
					Type:        gqlCatType,
					Description: "Get a Cat by ID",
					Args: graphql.FieldConfigArgument{
						"id": &graphql.ArgumentConfig{
							Type: graphql.NewNonNull(graphql.String),
						},
					},
					Resolve: t.gqlGetCat,
				},
			},
		}),
		Mutation: graphql.NewObject(graphql.ObjectConfig{
			Name: "Mutation",
			Fields: graphql.Fields{
				"createCat": &graphql.Field{
					Type:        graphql.Boolean,
					Description: "Create a new Cat",
					Args: graphql.FieldConfigArgument{
						"name": &graphql.ArgumentConfig{
							Type: graphql.NewNonNull(graphql.String),
						},
						"breed": &graphql.ArgumentConfig{
							Type: graphql.NewNonNull(graphql.String),
						},
						"age": &graphql.ArgumentConfig{
							Type: graphql.NewNonNull(graphql.Int),
						},
					},
					Resolve: t.gqlCreateCat,
				},
			},
		}),
	})
	if gqlSchemaErr != nil {
		return nil, fmt.Errorf("graphQL schema creation: %w", gqlSchemaErr)
	}

	// Mount the GraphQL handler.
	t.router.Mount("/graphql", handler.New(&handler.Config{
		Schema:   &gqlSchema,
		Pretty:   true,
		GraphiQL: true,
	}))

	return &t, nil
}

func (t *Transport) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	t.router.ServeHTTP(w, r)
}

func (t *Transport) catByID(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	if id == "" {
		t.log.Errorf("Query parameter id not found")

		http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		return
	}

	type response struct {
		ID    string `json:"id"`
		Name  string `json:"name"`
		Breed string `json:"breed"`
		Age   int    `json:"age"`
	}

	cat, err := t.service.GetCatByID(r.Context(), id)
	if err != nil {
		t.log.Errorf("Failed to get cat with '%s' id: %s", id, err.Error())

		if errors.Is(err, xerr.ErrNotFound) {
			http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)
			return
		}

		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
		return
	}

	resp := response{
		ID:    cat.ID,
		Name:  cat.Name,
		Breed: cat.Breed,
		Age:   int(cat.Age),
	}

	if err := json.NewEncoder(w).Encode(&resp); err != nil {
		t.log.Errorf("failed encode %+v to json: %s", resp, err.Error())

		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
		return
	}
}

func (t *Transport) createCat(w http.ResponseWriter, r *http.Request) {
	type request struct {
		Name  string `json:"name"`
		Breed string `json:"breed"`
		Age   uint32 `json:"age"`
	}

	var req request

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		body, _ := io.ReadAll(r.Body) //nolint: errcheck

		t.log.Errorf("failed to decode request body %s: %s", string(body), err.Error())

		http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		return
	}
	defer r.Body.Close()

	if err := t.service.CreateCat(r.Context(), req.Name, req.Breed, req.Age); err != nil {
		t.log.Errorf("failed to create cat: %s", err.Error())

		if errors.Is(err, xerr.ErrAlreadyExists) {
			http.Error(w, http.StatusText(http.StatusConflict), http.StatusConflict)
			return
		}

		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusCreated)
}

func (t *Transport) gqlGetCat(params graphql.ResolveParams) (any, error) {
	id, ok := params.Args["id"].(string)
	if !ok {
		return nil, fmt.Errorf("id must be a string")
	}

	cat, err := t.service.GetCatByID(params.Context, id)
	if err != nil {
		return nil, fmt.Errorf("get cat with '%s' id: %s", id, err.Error())
	}

	return cat, nil
}

func (t *Transport) gqlCreateCat(params graphql.ResolveParams) (any, error) {
	name, nameOK := params.Args["name"].(string)
	if !nameOK {
		return nil, fmt.Errorf("name must be a string")
	}

	breed, breedOK := params.Args["breed"].(string)
	if !breedOK {
		return nil, fmt.Errorf("breed must be a string")
	}

	age, ageOK := params.Args["age"].(int)
	if !ageOK {
		return nil, fmt.Errorf("age must be a string")
	}

	if err := t.service.CreateCat(params.Context, name, breed, uint32(age)); err != nil {
		return nil, fmt.Errorf("create cat: %w", err)
	}

	return true, nil
}
