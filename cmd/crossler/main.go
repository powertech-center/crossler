package main

import (
	"fmt"
	"os"
)

// Version is set during build via -ldflags
var Version = "0.0.0"

func main() {
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "--version":
			fmt.Println(Version)
			return
		case "--help":
			printHelp()
			return
		}
	}

	if len(os.Args) == 1 {
		fmt.Printf("Crossler %s\n", Version)
		fmt.Println("Cross-platform packaging tool")
		fmt.Println("Run 'crossler --help' for usage information.")
		return
	}

	// First arg is the config file path
	// TODO: implement config loading
	fmt.Fprintf(os.Stderr, "Not implemented yet\n")
	os.Exit(1)
}

func printHelp() {
	fmt.Println("Usage:")
	fmt.Println("  crossler                        Show version and status")
	fmt.Println("  crossler --version              Show version number")
	fmt.Println("  crossler --help                 Show this help message")
	fmt.Println("  crossler <config> [key=value]   Build packages from config")
}
