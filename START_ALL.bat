@echo off
REM Start all services for Solar Panel Monitoring System
REM This script starts the FastAPI backend (ML/RAG) and frontend

setlocal enabledelayedexpansion

echo.
echo =========================================
echo  Solar Panel Monitoring System
echo =========================================
echo.

REM Get the root directory
set ROOT_DIR=%~dp0

REM Start FastAPI Backend (ML/RAG/Gemini on port 8000)
echo [1/2] Starting FastAPI Backend (ML/RAG/Gemini Analysis)...
echo Port: 8000
cd /d "%ROOT_DIR%"
start "FastAPI Backend" cmd /k "python -m uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload"
timeout /t 5 >nul

REM Start React Frontend (port 3000)
echo.
echo [2/2] Starting React Frontend...
echo Port: 3000
cd /d "%ROOT_DIR%solar-dashboard\frontend"
start "React Frontend" cmd /k "npm start"
timeout /t 3 >nul

echo.
echo =========================================
echo  ✓ All services started!
echo =========================================
echo.
echo Frontend:  http://localhost:3000
echo Backend:   http://localhost:8000
echo Swagger:   http://localhost:8000/docs
echo.
echo Press Ctrl+C in each window to stop services
echo.

pause
