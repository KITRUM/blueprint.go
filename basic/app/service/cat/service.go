package cat

import (
	"context"
	"fmt"

	"github.com/KitRUM/golang-blueprint/basicrest/pkg/idkit"
)

// Service holds logic of work with Cat entity.
type Service interface {
	// GetCatByID returns a Cat searched by the given id,
	// returns ErrNotFound in case given id can not be found.
	GetCatByID(ctx context.Context, id string) (*Cat, error)

	// CreateCat creates a Cat.
	CreateCat(ctx context.Context, name, breed string, age uint32) error
}

// Storage represents layer of persistence for the Cat entity.
type Storage interface {
	// GetCatByID tries to find a Cat in the storage by given id.
	// Returns ErrNotFound if Cat with given id ca not be found in the database.
	GetCatByID(ctx context.Context, id string) (*Cat, error)

	// SaveCat saves given Cat record to the storage.
	SaveCat(ctx context.Context, cat *Cat) error
}

// Cat represents a Cat entity in a context of implemented system.
type Cat struct {
	ID    string
	Name  string
	Breed string
	Age   uint32
}

// ServiceImpl implements Service interface.
type ServiceImpl struct {
	storage Storage
}

// NewService returns a pointer to a new instance of Service implementation.
func NewService(storage Storage) *ServiceImpl {
	s := ServiceImpl{
		storage: storage,
	}

	return &s
}

func (s *ServiceImpl) GetCatByID(ctx context.Context, id string) (*Cat, error) {
	user, err := s.storage.GetCatByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("get cat by id '%s' from the storage: %w", id, err)
	}

	return user, nil
}

func (s *ServiceImpl) CreateCat(ctx context.Context, name, breed string, age uint32) error {
	uid := idkit.XID() // Generate new lexicographically sortable cat id.

	cat := Cat{
		ID:    uid,
		Name:  name,
		Breed: breed,
		Age:   age,
	}

	if err := s.storage.SaveCat(ctx, &cat); err != nil {
		return fmt.Errorf("save cat '%+v' to the storage: %w", cat, err)
	}

	return nil
}
