# Unpacks the Microsoft HTML Help Workshop installer and installs the SDK
# components silently. Mainly intended for provisioning CI systems.
#
# This script installs the files and registers the DLLs normally done by the
# installer. It does *NOT* set up registry keys, create shortcuts or install
# the redistributable since modern Windows doesn't require it.
#
# Accepts the following environment variables:
#
# HTMLHELP_EXE - Path to local copy of htmlhelp.exe
# HTMLHELP_URL - URL to download htmlhelp.exe from (if HTMLHELP_EXE isn't set)
#
# INSTALLDIR   - Path to install under, defaults to C:\Program Files [(x86)]\HTML Help Workshop

$ErrorActionPreference = "Stop"

# Create a temporary directory

$tmpfile = New-TemporaryFile
Remove-Item -path $tmpfile -force
$tmpdir = New-Item -ItemType Directory -Path $tmpfile.FullName

# Figure out where everything is

$WindowsDir = $env:windir

if(Test-Path -Path ($env:windir + "\SysWOW64"))
{
    $System32Dir = $WindowsDir + "\SysWOW64"
    $ProgramFilesDir = "C:\Program Files (x86)"
}
else{
    $System32Dir = $WindowsDir + "\System32"
    $ProgramFilesDir = "C:\Program Files"
}

if(Test-Path -Path ENV:HTMLHELP_EXE)
{
	$HTMLHELP_EXE = $ENV:HTMLHELP_EXE
	$HTMLHELP_SRC = $HTMLHELP_EXE
}
elseif(Test-Path -Path ENV:HTMLHELP_URL)
{
	$HTMLHELP_EXE = $tmpdir.FullName + "\htmlhelp.exe"
	$HTMLHELP_URL = $ENV:HTMLHELP_URL
	$HTMLHELP_SRC = $HTMLHELP_URL
}
else{
	$HTMLHELP_EXE = $tmpdir.FullName + "\htmlhelp.exe"
	$HTMLHELP_URL = "http://web.archive.org/web/20160201063255if_/https://download.microsoft.com/download/0/A/9/0A939EF6-E31C-430F-A3DF-DFAE7960D564/htmlhelp.exe"
	$HTMLHELP_SRC = $HTMLHELP_URL
}

$INSTALLDIR = if(Test-Path -Path ENV:INSTALLDIR) { $ENV:INSTALLDIR } Else { $ProgramFilesDir + "\HTML Help Workshop" }

echo "Installing HTML Help Workshop from $HTMLHELP_SRC to $INSTALLDIR"
echo ""

# Download htmlhelp.exe (if necessary)

if($HTMLHELP_URL)
{
	echo "Downloading $HTMLHELP_URL"
	Invoke-WebRequest -UseBasicParsing -uri $HTMLHELP_URL -OutFile $HTMLHELP_EXE
}

echo ""

# Unpack htmlhelp.exe

echo "Running $HTMLHELP_EXE /Q /C /T:""$($tmpdir.FullName)"""

$p = Start-Process -FilePath $HTMLHELP_EXE -ArgumentList "/Q", "/C", "/T:""$($tmpdir.Fullname)""" -Wait -PassThru
if($p.ExitCode -ne 0)
{
    throw "$HTMLHELP_EXE exited with status $($p.ExitCode)"
}

echo ""

# Install files

function Install-Files
{
    param ( $DestDir, $SrcFiles )

    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null

    foreach ( $file in $SrcFiles )
    {
        $dest_path = $DestDir + "\" + $(If($file.Dest) { $file.Dest } Else { $file.Name })
        $src_path = $tmpdir.FullName + "\" + $file.Name

        echo "Copying $($file.Name) to $dest_path"

        Copy-Item -Path $src_path -Destination $dest_path
    }
}

$HHWCopy = @(
    [PSCustomObject]@{ Name = "htmlhelp.inf"; Dest = "uninst.inf" }
    [PSCustomObject]@{ Name = "setup.exe"; }
    [PSCustomObject]@{ Name = "setup.ini" }
    [PSCustomObject]@{ Name = "advpack.dll" }
    [PSCustomObject]@{ Name = "cnvcnt.dll" }
    [PSCustomObject]@{ Name = "cnvtoc.dll" }
    [PSCustomObject]@{ Name = "gencnv.dll" }
    [PSCustomObject]@{ Name = "hhcout.dll" }
    [PSCustomObject]@{ Name = "hhkout.dll" }
    [PSCustomObject]@{ Name = "navout.dll" }
    [PSCustomObject]@{ Name = "spcom.dll" }
    [PSCustomObject]@{ Name = "sprbuild.dll" }
    [PSCustomObject]@{ Name = "spredit.dll" }
    [PSCustomObject]@{ Name = "sprfile.dll" }
    [PSCustomObject]@{ Name = "sprlog.dll" }
    [PSCustomObject]@{ Name = "hhc.exe" }
    [PSCustomObject]@{ Name = "hhw.exe" }
    [PSCustomObject]@{ Name = "hhw.gif" }
    [PSCustomObject]@{ Name = "flash.exe" }
    [PSCustomObject]@{ Name = "flash256.gif" }
    [PSCustomObject]@{ Name = "itcc.dll" }
    [PSCustomObject]@{ Name = "license.txt" }
    [PSCustomObject]@{ Name = "readme.txt" }
)

$HHWCopyInc = @(
    [PSCustomObject]@{ Name = "htmlhelp.h" }
)

$HHWCopyLib = @(
    [PSCustomObject]@{ Name = "htmlhelp.lib" }
)

$HHWCopyJava = @(
    [PSCustomObject]@{ Name = "dl.cl"; Dest = "DialogLayout.class" }
    [PSCustomObject]@{ Name = "e.cl"; Dest = "Element.class" }
    [PSCustomObject]@{ Name = "el.cl"; Dest = "ElementList.class" }
    [PSCustomObject]@{ Name = "h.cl"; Dest = "HHCtrl.class" }
    [PSCustomObject]@{ Name = "ip.cl"; Dest = "IndexPanel.class" }
    [PSCustomObject]@{ Name = "rd.cl"; Dest = "RelatedDialog.class" }
    [PSCustomObject]@{ Name = "HHCtrl.cab" }
    [PSCustomObject]@{ Name = "sp.cl"; Dest = "SitemapParser.class" }
    [PSCustomObject]@{ Name = "tc.cl"; Dest = "TreeCanvas.class" }
    [PSCustomObject]@{ Name = "tv.cl"; Dest = "TreeView.class" }
    [PSCustomObject]@{ Name = "cntimage.gif" }
)

$HHWCopyHelp = @(
    [PSCustomObject]@{ Name = "api.chm" }
    [PSCustomObject]@{ Name = "hhaxref.chm" }
    [PSCustomObject]@{ Name = "htmlref.chm" }
    [PSCustomObject]@{ Name = "htmlhelp.chm" }
)

$HHWCopyRedist = @(
    [PSCustomObject]@{ Name = "hhupd.exe" }
)

$HHWCopySystem = @(
    [PSCustomObject]@{ Name = "hha.dll" }
)

Install-Files -DestDir $INSTALLDIR -SrcFiles $HHWCopy
Install-Files -DestDir ($INSTALLDIR + "\include") -SrcFiles $HHWCopyInc
Install-Files -DestDir ($INSTALLDIR + "\lib") -SrcFiles $HHWCopyLib
Install-Files -DestDir ($INSTALLDIR + "\java") -SrcFiles $HHWCopyJava
Install-Files -DestDir ($INSTALLDIR + "\redist") -SrcFiles $HHWCopyRedist
Install-Files -DestDir ($WindowsDir + "\Help") -SrcFiles $HHWCopyHelp
Install-Files -DestDir $System32Dir -SrcFiles $HHWCopySystem

echo ""

# Register DLLs

function Register-DLL
{
    param ( $DllName )

    echo "Running $System32Dir\regsvr32.exe /s ""$DllName"""

    $p = Start-Process -FilePath ($System32Dir + "\regsvr32.exe") -ArgumentList "/s", """$DllName""" -Wait -PassThru
    if($p.ExitCode -ne 0)
    {
        throw "regsvr32.exe exited with status $($p.ExitCode)"
    }
}

$RegisterItccDLL = @(
    "itcc.dll"
    "sprbuild.dll"
    "sprlog.dll"
    "sprfile.dll"
    "spredit.dll"
    "spcom.dll"
    "cnvcnt.dll"
    "cnvtoc.dll"
    "gencnv.dll"
    "hhkout.dll"
    "hhcout.dll"
    "navout.dll"
)

foreach ( $dll in $RegisterItccDLL )
{
    Register-DLL -DllName ($INSTALLDIR + "\" + $dll)
}

echo ""

# Clean up temporary directory
Remove-Item -Path $tmpdir.FullName -Recurse -Force

# Done!
echo "HTML Help Workshop was successfully installed!"
