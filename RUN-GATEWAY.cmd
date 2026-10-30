@echo off
setlocal
where node.exe >nul 2>nul
if not errorlevel 1 (
  node.exe "%~dp0GATEWAY.cjs" %*
  exit /b
)
if exist "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe" (
  "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe" "%~dp0GATEWAY.cjs" %*
  exit /b
)
echo Node.js nao encontrado. Instale Node.js 18 ou superior no PC de laboratorio.
exit /b 1
