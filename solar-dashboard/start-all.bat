@echo off
REM Quick Start - All Services
REM This batch file starts Flask (5000), FastAPI (8000), and React (3000)

echo.
echo ================================================
echo  Solar Panel Dashboard - Quick Start
echo ================================================
echo.
echo This will start three services:
echo   1. Flask Backend        http://localhost:5000
echo   2. FastAPI Image Service http://localhost:8000  
echo   3. React Frontend       http://localhost:3000
echo.
echo ================================================
echo.

REM Start Flask Backend
echo Starting Flask Backend on port 5000...
start "Flask Backend [5000]" cmd /k "cd solar-dashboard\backend && python app.py"
timeout /t 3 /nobreak

REM Start FastAPI Service
echo Starting FastAPI Service on port 8000...
start "FastAPI Service [8000]" cmd /k "cd solar-dashboard\backend && python -m uvicorn image_analysis_service:app --host 0.0.0.0 --port 8000 --reload"
timeout /t 3 /nobreak

REM Start React Frontend
echo Starting React Frontend on port 3000...
start "React Frontend [3000]" cmd /k "cd solar-dashboard\frontend && npm start"

echo.
echo ================================================
echo All services starting...
echo.
echo Wait 30 seconds for compilation to complete
echo Then open: http://localhost:3000
echo.
echo To stop: Close each command window
echo ================================================
echo.

timeout /t 5

REM Open browser
start http://localhost:3000
