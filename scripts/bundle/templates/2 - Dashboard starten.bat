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
echo  SchoolMove - Stap 2: Dashboard starten
echo ============================================================
echo.
echo Het dashboard opent zo in je browser.
echo Sluit dit venster niet terwijl je het dashboard gebruikt -
echo daarmee stop je ook het dashboard.
echo.

cd /d "%BUNDLE_DIR%r"
"%RSCRIPT%" -e "shiny::runApp('shiny', launch.browser=TRUE)"

pause
