@echo off
setlocal
set BUNDLE_DIR=%~dp0
set R_HOME=%BUNDLE_DIR%R-portable

if exist "%R_HOME%\bin\x64\Rscript.exe" (
    set RSCRIPT=%R_HOME%\bin\x64\Rscript.exe
) else (
    set RSCRIPT=%R_HOME%\bin\Rscript.exe
)

echo ============================================================
echo  SchoolMove - Stap 1: Pipeline uitvoeren
echo ============================================================
echo.
echo Dit verwerkt de data in data\raw\meting_1 en data\raw\meting_2.
echo Zorg dat je bestanden daar staan voor je verdergaat.
echo.
echo Dit kan 30-60 minuten duren voor de volledige dataset.
echo Sluit dit venster niet terwijl de pipeline draait.
echo.
pause

cd /d "%BUNDLE_DIR%r"
"%RSCRIPT%" -e "source('pipeline/run_all.R')"

echo.
echo ============================================================
echo  Klaar. Start nu "2 - Dashboard starten.bat" om de
echo  resultaten te bekijken.
echo ============================================================
pause
