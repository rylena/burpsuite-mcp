@echo off
setlocal enabledelayedexpansion

:: BurpSuite MCP Full Control - Windows Build Script
:: Produces: build\libs\burp-mcp-full.jar (fat jar, Burp-loadable)

:: ===== Detect JDK (JAVA_HOME -> PATH -> common install dirs) =====
set "JAVAC="
set "JAR_CMD="

if defined JAVA_HOME (
    if exist "%JAVA_HOME%\bin\javac.exe" (
        set "JAVAC=%JAVA_HOME%\bin\javac.exe"
        set "JAR_CMD=%JAVA_HOME%\bin\jar.exe"
    )
)

if not defined JAVAC (
    where javac >nul 2>nul
    if not errorlevel 1 (
        for /f "delims=" %%i in ('where javac') do (
            set "JAVAC=%%i"
            goto :javac_found
        )
    )
)
:javac_found

if not defined JAR_CMD (
    where jar >nul 2>nul
    if not errorlevel 1 (
        for /f "delims=" %%i in ('where jar') do (
            set "JAR_CMD=%%i"
            goto :jar_found
        )
    )
)
:jar_found

if not defined JAVAC (
    for %%P in (
        "C:\Program Files\Java"
        "C:\Program Files\Eclipse Adoptium"
        "C:\Program Files\Microsoft\jdk-21.0.5.11-hotspot"
    ) do (
        if exist %%P (
            for /d %%D in (%%P\jdk-2*) do (
                if exist "%%D\bin\javac.exe" (
                    set "JAVAC=%%D\bin\javac.exe"
                    set "JAR_CMD=%%D\bin\jar.exe"
                )
            )
        )
    )
)

if not defined JAVAC (
    echo ERROR: javac not found in JAVA_HOME, PATH, or common install dirs.
    echo Set JAVA_HOME to your JDK 21+ install directory, e.g.:
    echo     set JAVA_HOME=C:\Program Files\Java\jdk-21
    exit /b 1
)

if not defined JAR_CMD (
    echo ERROR: jar not found in JAVA_HOME, PATH, or common install dirs.
    exit /b 1
)

set "SRC=src\main\java\com\burpmcp"
set "RES=src\main\resources"
set "LIB=lib"
set "OUT=build\classes"
set "DIST=build\libs"

echo [1/5] Validating MCP bridge...
where node >nul 2>nul
if not errorlevel 1 (
    node --check mcp-bridge.js
    if errorlevel 1 exit /b 1
    node --test test\mcp-bridge.test.js
    if errorlevel 1 exit /b 1
) else (
    echo WARNING: Node.js not found; skipping MCP bridge validation.
)

echo [2/5] Downloading dependencies...
if not exist %LIB% mkdir %LIB%
if not exist %LIB%\montoya-api.jar curl -fsSL -o %LIB%\montoya-api.jar "https://repo1.maven.org/maven2/net/portswigger/burp/extensions/montoya-api/2025.5/montoya-api-2025.5.jar"
if not exist %LIB%\gson.jar        curl -fsSL -o %LIB%\gson.jar        "https://repo1.maven.org/maven2/com/google/code/gson/gson/2.11.0/gson-2.11.0.jar"
if not exist %LIB%\nanohttpd.jar   curl -fsSL -o %LIB%\nanohttpd.jar   "https://repo1.maven.org/maven2/org/nanohttpd/nanohttpd/2.3.1/nanohttpd-2.3.1.jar"

echo [3/5] Compiling...
if exist "%OUT%" rmdir /s /q "%OUT%"
mkdir "%OUT%"
"%JAVAC%" --release 21 -encoding UTF-8 -cp "%LIB%\montoya-api.jar;%LIB%\gson.jar;%LIB%\nanohttpd.jar" -d %OUT% %SRC%\*.java
if errorlevel 1 (
    echo COMPILE FAILED
    exit /b 1
)

:: Copy resources (extension descriptor) so the jar is loadable by Burp
xcopy /e /i /y "%RES%\META-INF" "%OUT%\META-INF" >nul

echo [4/5] Packaging fat jar...
if not exist %DIST% mkdir %DIST%

:: Extract dependencies into classes dir
cd %OUT%
"%JAR_CMD%" xf ..\..\%LIB%\gson.jar com
"%JAR_CMD%" xf ..\..\%LIB%\nanohttpd.jar fi
cd ..\..

:: Create jar
"%JAR_CMD%" cf %DIST%\burp-mcp-full.jar -C %OUT% .

echo [5/5] Done!
echo Output: %DIST%\burp-mcp-full.jar
echo.
echo Install: Burp Suite -^> Extensions -^> Add -^> Java -^> Select %DIST%\burp-mcp-full.jar
echo.
echo MCP config (any client):
echo   { "command": "node", "args": ["%~dp0mcp-bridge.js"] }
