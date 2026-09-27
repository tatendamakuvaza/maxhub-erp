@echo off
REM ==================================================================
REM  Maxhub ERP - STEP 1: create the database and load the schema
REM  Double-click this file after installing PostgreSQL.
REM ==================================================================
setlocal
cd /d "%~dp0.."

set "PSQL="
for /d %%D in ("C:\Program Files\PostgreSQL\*") do (
    if exist "%%D\bin\psql.exe" set "PSQL=%%D\bin\psql.exe"
)
if not defined PSQL (
    echo [ERROR] Could not find psql.exe under C:\Program Files\PostgreSQL
    echo Install PostgreSQL first - see docs\STEP_BY_STEP_GUIDE.md
    pause
    exit /b 1
)
echo Found PostgreSQL at "%PSQL%"
echo.
set /p PGPASSWORD=Type the password you chose for the 'postgres' user and press Enter: 
set PGCLIENTENCODING=UTF8
echo.
echo [1/2] Creating database maxhub_erp ...
echo       (a message saying it "already exists" is fine)
"%PSQL%" -U postgres -h localhost -c "CREATE DATABASE maxhub_erp;"
echo.
echo [2/2] Loading tables, functions, views and demo data ...
"%PSQL%" -U postgres -h localhost -d maxhub_erp -v ON_ERROR_STOP=1 -q -f "database\maxhub_erp.sql"
if errorlevel 1 (
    echo.
    echo [ERROR] The SQL script failed. Read the message above.
    pause
    exit /b 1
)
echo.
echo ==============================================
echo  SUCCESS - the Maxhub ERP database is ready.
echo  Next: double-click scripts\run_dashboard.bat
echo ==============================================
pause
