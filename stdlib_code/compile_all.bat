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
	set outputfile=..\stdlib\%~1.ss

	echo --] '%~1.ss' ^-^> '%outputfile%'

	if exist %outputfile% del /Q %outputfile% > nul
	..\compiler %~1.ss -o %outputfile% -Cm lib -O3 -silent
	if not exist %outputfile% goto :fail

	goto :eof

:begin
if not exist "..\compiler.exe" goto :compiler_not_found

echo -] String
call :compile "string"

echo.
echo -] Math
call :compile "math"
call :compile "numbers"
call :compile "float"

echo.
echo -] Time
call :compile "time"

echo.
echo -] Standard input/output
call :compile "stdio"

echo.
echo -] VM
call :compile "vm"

echo.
echo -] miscellaneous
call :compile "random"