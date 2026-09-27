@echo off
REM ==================================================================
REM  Maxhub ERP - STEP 2: start the dashboard
REM  First run installs everything (takes 2-5 minutes), later runs are fast.
REM ==================================================================
setlocal
cd /d "%~dp0.."

if not exist ".venv\Scripts\python.exe" (
    echo First run - creating a Python virtual environment ...
    python -m venv .venv
    if errorlevel 1 (
        echo [ERROR] Python was not found. Install Python and tick "Add python.exe to PATH".
        pause
        exit /b 1
    )
    echo Installing libraries - please wait ...
    ".venv\Scripts\python.exe" -m pip install --upgrade pip
    ".venv\Scripts\python.exe" -m pip install -r requirements.txt
)

if not exist ".env" (
    copy ".env.example" ".env" >nul
    echo.
    echo A settings file called .env was created and will open in Notepad.
    echo Replace your_postgres_password_here with your real password, SAVE, then close Notepad.
    notepad ".env"
)

echo.
echo Starting Maxhub ERP - your browser will open at http://localhost:8501
echo Keep this window open while you use the dashboard. Press Ctrl+C to stop.
".venv\Scripts\python.exe" -m streamlit run app\app.py
pause
