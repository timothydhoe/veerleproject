@echo off
setlocal
set BUNDLE_DIR=%~dp0
set R_HOME=%BUNDLE_DIR%R-portable

for /f %%L in ('powershell -NoProfile -Command "$env:BUNDLE_DIR.Length"') do set BUNDLE_PATH_LEN=%%L
if %BUNDLE_PATH_LEN% GTR 90 (
    echo ============================================================
    echo  WAARSCHUWING: het pad naar deze map is lang ^(%BUNDLE_PATH_LEN% tekens^).
    echo ============================================================
    echo.
    echo  Windows heeft een limiet van 260 tekens voor een volledig
    echo  bestandspad. Bestanden diep in de R-bibliotheek kunnen die
    echo  limiet overschrijden en dan zonder duidelijke foutmelding
    echo  ontbreken of corrupt zijn na het uitpakken.
    echo.
    echo  Advies: verplaats deze map naar een korte locatie, bv. C:\SM\,
    echo  en pak opnieuw uit met 7-Zip ^(niet de ingebouwde Windows-
    echo  uitpakker, die bestanden met te lange paden soms stil
    echo  overslaat zonder foutmelding^).
    echo.
    echo  Doorgaan kan werken als je databestandsnamen kort genoeg zijn,
    echo  maar is niet gegarandeerd.
    echo.
    pause
)

if exist "%R_HOME%\bin\x64\Rscript.exe" (
    set RSCRIPT=%R_HOME%\bin\x64\Rscript.exe
) else (
    set RSCRIPT=%R_HOME%\bin\Rscript.exe
)

if not exist "%RSCRIPT%" (
    echo ============================================================
    echo  FOUT: kon R niet vinden op %RSCRIPT%
    echo ============================================================
    echo.
    echo  Dit betekent meestal dat de map niet volledig is uitgepakt,
    echo  of dat antivirussoftware bestanden heeft geblokkeerd of
    echo  verwijderd tijdens het uitpakken. Dit gebeurt soms met de
    echo  .exe/.dll bestanden in de R-portable map.
    echo.
    echo  Probeer opnieuw uit te pakken. Voeg zo nodig eerst een
    echo  uitzondering toe in je antivirussoftware voor de map waarin
    echo  je uitpakt, en pak dan opnieuw uit.
    echo.
    pause
    exit /b 1
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

if errorlevel 1 (
    echo.
    echo ============================================================
    echo  FOUT: de pipeline is niet volledig afgerond.
    echo ============================================================
    echo.
    echo  Bekijk de foutmelding hierboven in dit venster. Vaak gaat
    echo  het om een probleem met config.yaml of met de data in
    echo  data\raw\meting_1 of data\raw\meting_2.
    echo.
    echo  Los het probleem op en start dit bestand opnieuw.
    echo.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo  Klaar. Start nu "2 - Dashboard starten.bat" om de
echo  resultaten te bekijken.
echo ============================================================
pause
