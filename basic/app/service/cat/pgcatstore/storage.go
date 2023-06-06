package pgcatstore

import (
	"context"
	"errors"
	"fmt"

	"github.com/KitRUM/golang-blueprint/basicrest/app/service/cat"
	"github.com/KitRUM/golang-blueprint/basicrest/pkg/xerr"
	"github.com/jackc/pgerrcode"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Storage implements service.Storage interface using Postgres.
type Storage struct{ conn *pgxpool.Pool }

// New returns a pointer to a new instance of Storage struct.
func New(conn *pgxpool.Pool) *Storage { return &Storage{conn: conn} }

func (s *Storage) SaveCat(ctx context.Context, c *cat.Cat) (tErr error) {
	tx, txErr := s.conn.BeginTx(ctx, pgx.TxOptions{
		IsoLevel:   pgx.Serializable, // Consider another level of isolation for your use case.
		AccessMode: pgx.ReadWrite,
	})
	if txErr != nil {
		return fmt.Errorf("begin transaction: %w", txErr)
	}
	defer func() {
		if err := tx.Rollback(ctx); err != nil && !errors.Is(err, pgx.ErrTxClosed) {
			tErr = errors.Join(tErr, err)
		}
	}()

	q := `INSERT INTO cat (id, name, breed, age) VALUES ($1, $2, $3, $4);`

	if _, err := tx.Exec(ctx, q, c.ID, c.Name, c.Breed, c.Age); err != nil {
		return toServiceError(err)
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("postgres: commit transaction: %w", err)
	}

	return nil
}

func (s *Storage) GetCatByID(ctx context.Context, id string) (m *cat.Cat, tErr error) {
	tx, txErr := s.conn.BeginTx(ctx, pgx.TxOptions{
		IsoLevel:   pgx.ReadCommitted, // Consider another level of isolation for your use case.
		AccessMode: pgx.ReadOnly,
	})
	if txErr != nil {
		return nil, fmt.Errorf("begin transaction: %w", txErr)
	}
	defer func() {
		if err := tx.Rollback(ctx); err != nil && !errors.Is(err, pgx.ErrTxClosed) {
			tErr = errors.Join(tErr, err)
		}
	}()

	q := `SELECT * FROM cat WHERE id = $1 LIMIT 1;`

	var model cat.Cat
	if err := tx.QueryRow(ctx, q, id).Scan(&model.ID, &model.Name, &model.Breed, &model.Age); err != nil {
		return nil, toServiceError(err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("postgres: commit transaction: %w", err)
	}

	return &model, nil
}

func toServiceError(err error) error {
	var pgErr *pgconn.PgError

	if errors.Is(err, pgx.ErrNoRows) {
		return xerr.ErrNotFound
	}

	if errors.As(err, &pgErr) {
		switch pgErr.Code {
		case pgerrcode.NoData, pgerrcode.NoDataFound:
			return fmt.Errorf("postgres: %w: %s", xerr.ErrNotFound, pgErr.Detail)
		case pgerrcode.UniqueViolation:
			return fmt.Errorf("postgres: %w: %s", xerr.ErrAlreadyExists, pgErr.Detail)
		default:
			return fmt.Errorf("postgres: %w", pgErr)
		}
	}

	return fmt.Errorf("postgres: %w", err)
}
