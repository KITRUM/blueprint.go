# Basic

## Project Structure

- `app` - Holds an application code.
    - `middlewares` - Holds a set of HTTP middlewares.
    - `service` - Holds set of packages. Each package is fully responsible for its own domain, transport, persistence logic.
    - `server.go` - Represents ah HTTP listener which holds all the dependencies and provide an API routing to each `service` package.
- `cmd` - Defines a command line interface to which serves as an entry point for different application running options. Examples: `app serve` will run an HTTP
  service, `app cron` will run a cronjob, etc.
- `pkg` - Holds set of packages with shared code which is not related to the domain logic.

## Service Package Structure

The idea of having self-contained packages is simple. Each package defines `Service` interface along with domain entities which represents domain logic.
Package defines a transport layer, an HTTP API in our case, which conforms to a `http.Handler` interface. Package defines package level endpoints.

Example:
```go
// Service holds logic of work with Cat entity.
type Service interface {
	// GetCatByID returns a Cat searched by the given id,
	// returns ErrNotFound in case given id can not be found.
	GetCatByID(ctx context.Context, id string) (*Cat, error)

	// CreateCat creates a Cat.
	CreateCat(ctx context.Context, name, breed string, age uint32) error
}
```

Our Cat service defines 2 methods which our transport layer wraps in:
```go
// Initialize routes.
	t.router.Get("/{id}", t.catByID)
	t.router.Post("/", t.createCat)
```

