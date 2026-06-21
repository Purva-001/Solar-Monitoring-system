@echo off
REM Start the FastAPI Image Analysis Service on port 8000
REM This runs separately from the Flask backend on port 5000

cd /d "%~dp0"
echo.
echo ========================================
echo Starting Image Analysis Service
echo Port: 8000
echo ========================================
echo.

REM Check if uvicorn is installed
python -m pip show uvicorn > nul 2>&1
if %errorlevel% neq 0 (
    echo Installing uvicorn...
    python -m pip install uvicorn fastapi -q
)

REM Start FastAPI service
python -m uvicorn image_analysis_service:app --host 0.0.0.0 --port 8000 --reload

pause
