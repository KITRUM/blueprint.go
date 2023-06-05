package log

import (
	"os"

	"github.com/rs/zerolog"
)

// Logger abstracts the application logging logic.
type Logger interface {
	// Infof formats message with given arguments and prints it with an info level.
	Infof(format string, args ...any)

	// Errorf formats message with given arguments and prints it with an error level.
	Errorf(format string, args ...any)
}

// ZeroLogger implements Logger using the github.com/rs/zerolog.
type ZeroLogger struct {
	log zerolog.Logger
}

// New returns a pointer to a new instance of ZeroLogger.
func New() *ZeroLogger {
	l := ZeroLogger{
		log: zerolog.New(os.Stdout).With().Timestamp().Logger(),
	}

	return &l
}

func (l *ZeroLogger) Infof(format string, args ...any) {
	l.log.Info().Msgf(format, args...)
}

func (l *ZeroLogger) Errorf(format string, args ...any) {
	l.log.Error().Msgf(format, args...)
}
