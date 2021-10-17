package main

import (
	"errors"
	"fmt"
	"os"
	"time"
)

const (
	cantWriteLog = iota + 1
	wrongArgs
	cantOpenLogFile
)

func writeLogs(args []string) (int, error) {
	if len(args) < 2 {
		return wrongArgs, errors.New("You need to provide a file to write the logs to")
	}

	filename := args[1]

	f, err := os.OpenFile(filename, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil {
		return cantOpenLogFile, fmt.Errorf("Unable to open log file: %w", err)
	}
	defer f.Close()

	for {
		_, err := fmt.Fprintf(f, "%s: This is an error message\n", time.Now())
		if err != nil {
			return cantWriteLog, fmt.Errorf("Unable to write log: %w", err)
		}
		time.Sleep(2 * time.Second)
	}
}

func main() {
	errCode, err := writeLogs(os.Args)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		os.Exit(errCode)
	}
}
