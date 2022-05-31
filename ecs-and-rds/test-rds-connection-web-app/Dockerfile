FROM golang:1.18 as build

WORKDIR /app

COPY go.mod ./
COPY go.sum ./

RUN go mod download
COPY *.go ./
RUN go build -o /test-app

FROM debian:bullseye-slim

COPY --from=build /test-app /test-app

ENTRYPOINT [ "/test-app" ]