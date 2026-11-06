@echo off
rem Builds Claude Limits with the C# compiler that ships with Windows (nothing to install),
rem copies it to %LOCALAPPDATA%\Programs\ClaudeLimits and starts it.
chcp 65001 >nul
cd /d "%~dp0"
set NET=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319
if not exist build mkdir build
"%NET%\csc.exe" /nologo /codepage:65001 /optimize+ /target:winexe /out:build\ClaudeLimits.exe ^
  /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll ^
  /r:"%NET%\WPF\UIAutomationClient.dll" /r:"%NET%\WPF\UIAutomationTypes.dll" /r:"%NET%\WPF\WindowsBase.dll" ClaudeLimits.cs
if errorlevel 1 (echo Не зібралось & pause & exit /b 1)

set DEST=%LOCALAPPDATA%\Programs\ClaudeLimits
taskkill /im ClaudeLimits.exe /f >nul 2>&1
if not exist "%DEST%" mkdir "%DEST%"
copy /y build\ClaudeLimits.exe "%DEST%\" >nul
rem Через Провідник: тоді краб — звичайна програма й не закриється разом із терміналом, з якого його зібрали
explorer.exe "%DEST%\ClaudeLimits.exe"
echo Готово: %DEST%\ClaudeLimits.exe
