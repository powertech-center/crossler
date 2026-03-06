@echo off
:: Creates a symlink CLAUDE.md in the project root pointing to .claude/CLAUDE.md
:: Run as Administrator or with Developer Mode enabled in Windows

set "SCRIPT_DIR=%~dp0"
set "ROOT_DIR=%SCRIPT_DIR%..\"
set "TARGET=%SCRIPT_DIR%CLAUDE.md"
set "LINK=%ROOT_DIR%CLAUDE.md"

if exist "%LINK%" (
    echo CLAUDE.md already exists in the project root.
) else (
    mklink "%LINK%" "%TARGET%"
)
