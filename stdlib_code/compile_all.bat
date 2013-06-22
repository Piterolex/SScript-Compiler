@echo off
rem SScript Standard Library build script

goto :begin

:loop
	goto :loop

:fail
	echo --] compilation failed; building stopped
	goto :loop

:compiler_not_found
	echo Compiler not found!
	echo It should be reachable at `..\compiler.exe`
	goto :loop

:compile
	set outputfile=..\stdlib\%~1.ssm

	echo --] '%~1.ss' :: '%outputfile%'

	if exist %outputfile% del /Q %outputfile% > nul
	..\compiler %~1.ss -o %outputfile% -h ..\stdlib\%~1.ss -Cm lib -O3
	if not exist %outputfile% goto :fail

	goto :eof

:begin
if not exist "..\compiler.exe" goto :compiler_not_found

echo -] init code
call :compile "init"

echo.
echo -] STRING
call :compile "string"

echo.
echo -] MATH
call :compile "math"
call :compile "numbers"
call :compile "float"

echo.
echo -] TIME
call :compile "time"

echo.
echo -] STDIO
call :compile "stdio"

echo.
echo -] VM
call :compile "vm"