@ECHO OFF

C:\msys64\usr\bin\bash.exe -lec "cd \"$1\" && bash -xe <<< $BUILDKITE_COMMAND" -- "%cd%"
EXIT %ERRORLEVEL%
