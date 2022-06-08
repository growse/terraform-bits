package main

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/rds/auth"
	"github.com/gin-gonic/gin"
	_ "github.com/lib/pq"
)

func main() {
	print("Hello")

	r := gin.Default()
	r.GET("/", func(c *gin.Context) {
		c.String(http.StatusOK, "Hello, Docker! <3")
	})
	r.GET("/healthz", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})
	r.GET("/dbtest", func(c *gin.Context) {
		port, err := strconv.Atoi(os.Getenv("DATABASE_PORT"))
		if err != nil {
			c.AbortWithError(http.StatusInternalServerError, err)
		}

		err = pingDatabase(c.Request.Context(), os.Getenv("DATABASE_HOST"), port, os.Getenv("DATABASE_USERNAME"), os.Getenv("DATABASE_PASSWORD"), os.Getenv("DATABASE_NAME"))
		if err != nil {
			c.AbortWithError(http.StatusInternalServerError, err)
		} else {
			c.String(http.StatusOK, "Database connect success")
		}
	})
	r.Run(":8888")
}

func pingDatabase(httpCtx context.Context, dbHost string, dbPort int, dbUser string, dbPassword string, dbName string) error {
	err := raw_connect(dbHost, dbPort)
	if err != nil {
		return err
	}
	log.Print("Pinging database")
	var dbEndpoint string = fmt.Sprintf("%s:%d", dbHost, dbPort)
	var region string = "eu-west-1"

	log.Printf("Db endpoint is %v", dbEndpoint)
	ctxWithTimeout, cancel := context.WithTimeout(httpCtx, 1*time.Second)
	defer cancel()
	cfg, err := config.LoadDefaultConfig(ctxWithTimeout)
	if err != nil {
		return fmt.Errorf("configuration error: %w", err)
	}

	log.Print("Building auth token")

	authenticationToken, err := auth.BuildAuthToken(ctxWithTimeout, dbEndpoint, region, dbUser, cfg.Credentials)
	if err != nil {
		return fmt.Errorf("failed to create authentication token: %w", err)
	}

	log.Printf("Auth token is %v", authenticationToken)

	dsn := fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s connect_timeout=3",
		dbHost, dbPort, dbUser, dbPassword, dbName,
	)

	log.Printf("DSN is %v", dsn)

	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return err
	}

	log.Print("Pinging database")

	err = db.PingContext(ctxWithTimeout)
	if err != nil {
		return err
	}

	log.Print("DB Ping Success")
	return nil
}

func raw_connect(host string, port int) error {
	timeout := time.Second
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(host, strconv.Itoa(port)), timeout)
	if err != nil {
		fmt.Println("Connecting error:", err)
		return err
	}
	if conn != nil {
		defer conn.Close()
		fmt.Println("Opened", net.JoinHostPort(host, strconv.Itoa(port)))
	}
	return nil
}
