$gameDir = (.\libs\getConfigvalue.bat X4_PATH).Replace('%PROGRAMFILES(X86)%', ${env:ProgramFiles(x86)})

$catFiles = Get-ChildItem -Path "$gameDir\*" -include "*.cat"  -exclude "*sig*"
$currentVersion = $(Get-Content "$gameDir\version.dat")
$unpackDir = "$gameDir\unpacked-$currentVersion"

New-Item -Path $unpackDir -ItemType Directory

.\libs\vendor\Egosoft\XRCatTool.exe -in $catFiles -out $unpackDir 
