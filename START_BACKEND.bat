@echo off
REM Start FastAPI Backend (ML/RAG/Gemini Analysis)

echo.
echo =========================================
echo  FastAPI Backend - ML/RAG/Gemini
echo =========================================
echo.
echo Starting on port 8000...
echo.

cd /d "%~dp0backend"
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload

pause
