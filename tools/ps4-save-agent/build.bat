@echo off
setlocal EnableDelayedExpansion

set "ROOT=%~dp0..\.."
set "SRCDIR=%~dp0src"
set "INTDIR=%~dp0build"
set "OUTDIR=%ROOT%\payloads"
set "PS4TOOLS_OUTDIR=C:\PS4Tools\payloads"
set "PS4TOOLS_DEV_OUTDIR=D:\Devs\PS4Tools\payloads"
set "TARGET=ps4-save-agent"

if "%PS4_PAYLOAD_SDK%"=="" set "PS4_PAYLOAD_SDK=D:\Devs\ps4-payload-sdk-v0.9\ps4-payload-sdk"
if "%LLVM_BINDIR%"=="" set "LLVM_BINDIR=D:\Devs\LLVM-18\bin"

if not exist "%PS4_PAYLOAD_SDK%\target\include" (
  echo PS4_PAYLOAD_SDK invalido: %PS4_PAYLOAD_SDK%
  exit /b 1
)

if not exist "%LLVM_BINDIR%\clang.exe" (
  echo LLVM_BINDIR invalido: %LLVM_BINDIR%
  exit /b 1
)

if not exist "%OUTDIR%" mkdir "%OUTDIR%"
if not exist "%INTDIR%" mkdir "%INTDIR%"

set "CC=%LLVM_BINDIR%\clang.exe"
set "LD=%LLVM_BINDIR%\ld.lld.exe"
set "SDK=%PS4_PAYLOAD_SDK%"
set "CFLAGS=-target x86_64-scie-ps4 -fvisibility-nodllstorageclass=default -isysroot %SDK% -isystem %SDK%\target\include -I%SRCDIR% -fno-stack-protector -fno-plt -femulated-tls -O2 -D_BSD_SOURCE -std=gnu11"
set "SQLFLAGS=-DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_WAL -w"
set "LIBS=-lc -lkernel_web -lSceLibcInternal -lSceNet -lSceFsInternalForVsh -lSceRegMgr"

echo Compilando %TARGET%...
"%CC%" %CFLAGS% -Wall -g -c "%SRCDIR%\main.c" -o "%INTDIR%\payloadsdk-main.o"
if errorlevel 1 exit /b 1

echo Compilando SQLite...
"%CC%" %CFLAGS% %SQLFLAGS% -c "%SRCDIR%\sqlite3.c" -o "%INTDIR%\sqlite3.o"
if errorlevel 1 exit /b 1

echo Linkando %TARGET%.elf...
"%LD%" -m elf_x86_64 -pie -T"%SDK%\ldscripts\elf_x86_64.x" --eh-frame-hdr -z max-page-size=0x4000 -o "%OUTDIR%\%TARGET%.elf" -L"%SDK%\target\lib" "%SDK%\target\lib\crt1.o" "%INTDIR%\payloadsdk-main.o" "%INTDIR%\sqlite3.o" %LIBS%
if errorlevel 1 exit /b 1

echo Gerado: "%OUTDIR%\%TARGET%.elf"
if not exist "%PS4TOOLS_OUTDIR%" mkdir "%PS4TOOLS_OUTDIR%"
if not exist "%PS4TOOLS_DEV_OUTDIR%" mkdir "%PS4TOOLS_DEV_OUTDIR%"
copy /y "%OUTDIR%\%TARGET%.elf" "%PS4TOOLS_OUTDIR%\%TARGET%.elf" >nul
copy /y "%OUTDIR%\%TARGET%.elf" "%PS4TOOLS_DEV_OUTDIR%\%TARGET%.elf" >nul
echo Copiado para: "%PS4TOOLS_OUTDIR%\%TARGET%.elf"
echo Copiado para: "%PS4TOOLS_DEV_OUTDIR%\%TARGET%.elf"

endlocal
