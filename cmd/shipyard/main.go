package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"strings"

	"github.com/shipyard-io/bash-cli/internal/cli"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	if len(os.Args) < 2 {
		printUsage()
		return nil
	}

	switch strings.ToLower(os.Args[1]) {
	case "setup":
		fs := flag.NewFlagSet("setup", flag.ContinueOnError)
		repo := fs.String("repo", "", "Target repository in owner/name format")
		nonInteractive := fs.Bool("non-interactive", false, "Run setup without prompts using env vars")
		envFile := fs.String("env-file", "", "Path to .env file used for ENV_FILE_CONTENT in non-interactive mode")
		if err := fs.Parse(os.Args[2:]); err != nil {
			return err
		}
		return cli.RunSetup(cli.SetupOptions{
			CommonOptions: cli.CommonOptions{
				Repo:           *repo,
				NonInteractive: *nonInteractive,
			},
			EnvFile: *envFile,
		})
	case "secrets":
		fs := flag.NewFlagSet("secrets", flag.ContinueOnError)
		repo := fs.String("repo", "", "Target repository in owner/name format")
		nonInteractive := fs.Bool("non-interactive", false, "Run secrets update without prompts")
		secret := fs.String("secret", "", "Secret name for non-interactive mode")
		value := fs.String("value", "", "Secret value for non-interactive mode")
		valueFile := fs.String("value-file", "", "Read secret value from file in non-interactive mode")
		if err := fs.Parse(os.Args[2:]); err != nil {
			return err
		}
		return cli.RunSecrets(cli.SecretsOptions{
			CommonOptions: cli.CommonOptions{
				Repo:           *repo,
				NonInteractive: *nonInteractive,
			},
			SecretName: *secret,
			Value:      *value,
			ValueFile:  *valueFile,
		})
	case "help", "-h", "--help":
		printUsage()
		return nil
	default:
		return errors.New("unknown command: " + os.Args[1])
	}
}

func printUsage() {
	fmt.Println("Shipyard CLI")
	fmt.Println()
	fmt.Println("Usage:")
	fmt.Println("  shipyard setup [--repo owner/name] [--non-interactive --env-file .env]")
	fmt.Println("  shipyard secrets [--repo owner/name] [--non-interactive --secret NAME --value ...]")
}
