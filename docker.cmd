@echo off
setlocal

set IMAGE=ghcr.io/powertech-center/alpine/cross-go:latest

if "%~1"=="" (
    rem No arguments - interactive mode
    docker.exe run -it --rm -v "%cd%:/workspace" -w /workspace %IMAGE%
) else (
    rem With arguments - run command and exit
    docker.exe run --rm -v "%cd%:/workspace" -w /workspace %IMAGE% %*
)
