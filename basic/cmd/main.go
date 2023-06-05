package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"time"

	"github.com/KitRUM/golang-blueprint/basicrest/app"
	"github.com/KitRUM/golang-blueprint/basicrest/app/service/cat"
	"github.com/KitRUM/golang-blueprint/basicrest/app/service/cat/storage/pgcatstore"
	"github.com/KitRUM/golang-blueprint/basicrest/pkg/log"
	"github.com/go-playground/validator/v10"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/urfave/cli/v2"
)

// Variables which are related to Version command.
// Should be specified by '-ldflags' during the build phase.
// Example:
// GOOS=linux GOARCH=amd64 go build -ldflags="-X main.Branch=$BRANCH \
// -X main.Commit=$COMMIT -o api.
var (
	// Branch is the branch this binary built from.
	Branch = "local"

	// Commit is the commit this binary built from.
	Commit = "unknown"

	// BuildTime is the time this binary built.
	BuildTime = time.Now().Format(time.RFC822)
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()

	cmd := &cli.App{
		Name:  "app",
		Usage: "root command of the app",
		Before: func(c *cli.Context) error {
			// Prints the app version.
			fmt.Printf("Branch: %s, Commit: %s, Build time: %s\n\n", Branch, Commit, BuildTime)

			return nil
		},

		Commands: []*cli.Command{
			ServeCommand(),
		},
	}

	if err := cmd.RunContext(ctx, os.Args); err != nil {
		panic(fmt.Sprintf("Error: %s\n", err.Error()))
	}
}

func ServeCommand() *cli.Command {
	cfg := struct {
		Env       string `validate:"oneof=dev test prod"`
		LogLevel  string
		HTTPAddr  string
		DBConnStr string
	}{}

	command := cli.Command{
		Name:  "serve",
		Usage: "runs HTTP listener to serve the incoming connections",
		Action: func(c *cli.Context) error {
			logger := log.New()

			dbConfig, err := pgxpool.ParseConfig(cfg.DBConnStr)
			if err != nil {
				return fmt.Errorf("parse database connection string: %w", err)
			}

			dbConn, err := pgxpool.NewWithConfig(c.Context, dbConfig)
			if err != nil {
				return fmt.Errorf("database connection: %w", err)
			}

			catStorage := pgcatstore.New(dbConn)
			catService := cat.NewService(catStorage)
			catTransport, catTransportErr := cat.NewTransport(catService, logger)
			if catTransportErr != nil {
				return fmt.Errorf("create cat transport: %w", catTransportErr)
			}

			server := app.NewServer(cfg.HTTPAddr, logger, catTransport)

			return server.Serve(c.Context)
		},

		Before: func(ctx *cli.Context) error {
			// Config validation.
			return validator.New().Struct(cfg)
		},

		Flags: []cli.Flag{
			&cli.StringFlag{
				Name:        "env",
				Usage:       "defines app runtime environment",
				EnvVars:     []string{"ENV"},
				Required:    true,
				Destination: &cfg.Env,
			},
			&cli.StringFlag{
				Name:        "http-addr",
				Usage:       "defines HTTP listener address",
				EnvVars:     []string{"HTTP_ADDR"},
				Value:       ":8080",
				Destination: &cfg.HTTPAddr,
			},
			&cli.StringFlag{
				Name:        "db-conn-str",
				Usage:       "defines database connection string",
				Required:    true,
				Destination: &cfg.DBConnStr,
				EnvVars:     []string{"DB_CONN_STR"},
			},
		},
	}

	return &command
}
