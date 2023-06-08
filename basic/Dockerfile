# Builder layer
FROM golang:1.20-alpine AS BUILDER

ARG BRANCH
ARG COMMIT

RUN apk add --no-cache ca-certificates build-base git && mkdir -p /app
WORKDIR /app
COPY go.mod .
COPY go.sum .
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -buildvcs=false -ldflags="-X main.Branch=$BRANCH -X main.Commit=$COMMIT" -o api ./cmd

# Final layer
FROM alpine:latest

EXPOSE 8080

COPY --from=BUILDER /app/api api

ENTRYPOINT ["./api"]