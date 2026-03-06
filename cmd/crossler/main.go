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
		case "version":
			fmt.Println(Version)
		case "help":
			printHelp()
		default:
			fmt.Fprintf(os.Stderr, "Unknown command: %s\n", os.Args[1])
			printHelp()
			os.Exit(1)
		}
		return
	}

	fmt.Printf("Crossler %s\n", Version)
	fmt.Println("Cross-platform packaging tool")
	fmt.Println("Run 'crossler help' for usage information.")
}

func printHelp() {
	fmt.Println("Usage:")
	fmt.Println("  crossler              Show version and status")
	fmt.Println("  crossler version      Show version number")
	fmt.Println("  crossler help         Show this help message")
}
