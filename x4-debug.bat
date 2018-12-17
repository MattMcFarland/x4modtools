@echo off

for /f "tokens=*" %%i in ('.\libs\getConfigvalue.bat X4_EXE_PATH') do set X4_EXE_PATH=%%i
call set X4_EXE_PATH="%X4_EXE_PATH%"

rem !!--- set the date and time for logfile year-month-day__hh-mm-ss
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /format:list') do set datetime=%%I
set datetime=%datetime:~0,4%-%datetime:~4,2%-%datetime:~6,2%__%datetime:~8,2%-%datetime:~10,2%-%datetime:~12,2%
echo "Date & Time test = %datetime%  year-month-day__hh-mm-ss"

rem stores a value like `x4-game-2018-12-10__11-04-11.log` - to be passed in -logfile
set LOG_FILE_NAME=x4-game-%datetime%.log
rem stores a value like `x4-script-2018-12-10__11-04-11.log` - to be passed in -scriptlogfile
set SCRIPT_LOG_FILE_NAME=x4-script-%datetime%.log
set exec="%X4_EXE_PATH% -debug all -logfile %LOG_FILE_NAME% -scriptlogfile %SCRIPT_LOG_FILE_NAME%"

rem execution phase, first we log out the command, if any of the variables are blank, make sure you dont have whitespace around any of the variables
echo "Executing %X4_EXE_PATH% -debug all -logfile %LOG_FILE_NAME% -scriptlogfile %SCRIPT_LOG_FILE_NAME%"
start "" %X4_EXE_PATH% -debug all -logfile %LOG_FILE_NAME% -scriptlogfile %SCRIPT_LOG_FILE_NAME%
