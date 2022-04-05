SET toolchain_selected=0

set BUILDKITE_CLEAN_CHECKOUT=true
set BUILDKITE_NO_LOCAL_HOOKS=true

rem Add MSYS to PATH so buildkite-agent can find its Git.
set PATH=%PATH%;C:\msys64\usr\bin

set X_PARALLEL_JOBS=4

FOR /F %%i IN ('buildkite-agent step get --format json agents') DO (
rem  	IF [%%i] == ["queue=windows-i686"] (
rem  		ECHO Using 32-bit GCC toolchain
rem  		
rem  		IF "%toolchain_selected%" == "1" (
rem  			ECHO Multiple toolchains requested, aborting!
rem  			EXIT 1
rem  		)
rem  		
rem  		SET PATH=%PATH%;C:\i686-w64-mingw32\mingw32\bin;C:\msys64\usr\bin
rem  		SET CC=i686-w64-mingw32-gcc
rem  		SET CXX=i686-w64-mingw32-g++
rem  		SET LLVM_CONFIG=/c/i686-w64-mingw32/llvm-9.0.1-release-static/bin/llvm-config
rem  		SET WX_CONFIG=/c/i686-w64-mingw32/wxWidgets-3.0.5-release-static/bin/wx-config
rem  		
rem  		SET toolchain_selected=1
rem  	)
rem  	
rem  	IF [%%i] == ["queue=windows-x86_64"] (
rem  		ECHO Using 64-bit GCC toolchain
rem  		
rem  		IF "%toolchain_selected%" == "1" (
rem  			ECHO Multiple toolchains requested, aborting!
rem  			EXIT 1
rem  		)
rem  		
rem  		SET PATH=%PATH%;C:\x86_64-w64-mingw32\mingw64\bin;C:\msys64\usr\bin
rem  		SET CC=x86_64-w64-mingw32-gcc
rem  		SET CXX=x86_64-w64-mingw32-g++
rem  		SET LLVM_CONFIG=/c/x86_64-w64-mingw32/llvm-9.0.1-release-static/bin/llvm-config
rem  		SET WX_CONFIG=/c/x86_64-w64-mingw32/wxWidgets-3.0.5-release-static/bin/wx-config
rem  		
rem  		SET toolchain_selected=1
rem  	)
	
	IF [%%i] == ["queue=mingw-i686"] (
		ECHO Using 32-bit MinGW toolchain
		
		IF "%toolchain_selected%" == "1" (
			ECHO Multiple toolchains requested, aborting!
			EXIT 1
		)
		
		SET MSYSTEM=MINGW32
		
		SET toolchain_selected=1
	)
	
	IF [%%i] == ["queue=mingw-x86_64"] (
		ECHO Using 64-bit MinGW toolchain
		
		IF "%toolchain_selected%" == "1" (
			ECHO Multiple toolchains requested, aborting!
			EXIT 1
		)
		
		SET MSYSTEM=MINGW64
		
		SET toolchain_selected=1
	)
)

IF "%toolchain_selected%" == "0" (
	ECHO Couldn't determine toolchain to use!
	EXIT 1
)
