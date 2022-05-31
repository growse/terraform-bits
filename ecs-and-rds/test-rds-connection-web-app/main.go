package main

import (
	"context"
	"database/sql"
	"fmt"
	"net/http"
	"os"
	"strconv"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/rds/auth"
	"github.com/gin-gonic/gin"
	_ "github.com/lib/pq"
)

func main() {
	print("Hello")

	if os.Getenv("CONNECT_TO_THE_DATABASE") != "" {
		port, err := strconv.Atoi(os.Getenv("DATABASE_PORT"))
		if err != nil {
			panic(err)
		}
		pingDatabase(os.Getenv("DATABASE_HOST"), port, os.Getenv("DATABASE_USERNAME"), os.Getenv("DATABASE_PASSWORD"), os.Getenv("DATABASE_NAME"))
	}

	r := gin.Default()
	r.GET("/", func(c *gin.Context) {
		c.String(http.StatusOK, "Hello, Docker! <3")
	})
	r.GET("/ping", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"message": "pong",
		})
	})
	r.Run(":8888")
}

func pingDatabase(dbHost string, dbPort int, dbUser string, dbPassword string, dbName string) {
	var dbEndpoint string = fmt.Sprintf("%s:%d", dbHost, dbPort)
	var region string = "eu-west-1"

	cfg, err := config.LoadDefaultConfig(context.TODO())
	if err != nil {
		panic("configuration error: " + err.Error())
	}

	authenticationToken, err := auth.BuildAuthToken(
		context.TODO(), dbEndpoint, region, dbUser, cfg.Credentials)
	if err != nil {
		panic("failed to create authentication token: " + err.Error())
	}

	dsn := fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s",
		dbHost, dbPort, dbUser, authenticationToken, dbName,
	)

	db, err := sql.Open("postgres", dsn)
	if err != nil {
		panic(err)
	}

	err = db.Ping()
	if err != nil {
		panic(err)
	}
}
