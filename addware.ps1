param (
    [string]$use = ".\addwares.xml",
    [switch]$force = $false
 )

$ErrorActionPreference = "Stop"
# load it into an XML object:
[xml]$addwaresXml = Get-Content $use

. .\libs\Merge-XML.ps1
. .\libs\Expand-GZ.ps1
. .\libs\Invoke-Assignment.ps1

function Get-ConfigItem {
	<#
		.SYNOPSIS
			Retrieves a value from configuration
		.PARAMETER ConfigNodeName
			Name of the node which contains the value
	#>  
    param(
      [Parameter(Mandatory=$true,Position=0)]
      [string]$ConfigNodeName
    )
    $config = $addwaresXml.addwares.configuration
    return $config.$ConfigNodeName.Value.Replace('%PROGRAMFILES(X86)%', ${env:ProgramFiles(x86)})
}

function Merge-WareDefaults {
    param(
        [xml]$Node
    )
    $wareDefaults = (Select-XML -Xml $addwaresXml -XPath '//configuration/defaults')
    return Merge-XML $wareDefaults $Node
}

$MOD_PREFIX = Get-ConfigItem "prefix"

$GAME_PATH = Get-ConfigItem("gamepath")
$MOD_PATH = Join-Path -Path $GAME_PATH -ChildPath $(Get-ConfigItem("modpath"))
$MOD_REL_PATH = Get-ConfigItem("modpath")
$UNPACKED_PATH = Join-Path -Path $GAME_PATH -ChildPath $(Get-ConfigItem("unpackedPath"))

Write-Host "MOD_PREFIX: $MOD_PREFIX"
Write-Host "GAME_PATH: $GAME_PATH"
Write-Host "MOD_PATH: $MOD_PATH"
Write-Host "UNPACKED_PATH: $UNPACKED_PATH"



function Publish-WareMacro {
  param(
    [string]$WareId
  )

  # Create Wares Macro
  $wareMacroName = "$($MOD_PREFIX)_ware_$($WareId)_macro"
  $sourceWareMacroPath = Join-Path -Path $UNPACKED_PATH -ChildPath "assets\wares\macros\ware_default_macro.xml"
  $destinationWareMacroPath = Join-Path -Path $MOD_PATH -ChildPath "assets\wares\macros\$wareMacroName.xml"
  
  Write-Host "Publish $destinationWareMacroPath"
  New-Item -Path $destinationWareMacroPath -Force
  Copy-Item $sourceWareMacroPath -Destination $destinationWareMacroPath 

  # update the copied macro to contain the new id
  [xml]$newWareMacroXml = Get-Content $destinationWareMacroPath
  $newWareMacroXml.macros.macro.name = $wareMacroName

  # save the updated xml
  $newWareMacroXml.save($destinationWareMacroPath)

}

function Publish-ProductionMacro {
  param(
    [string]$WareId,
    [System.Xml.XmlDocument]$Ware,
    [string]$CloneProductionModuleFrom
  )
  $prodMacroName = "$($MOD_PREFIX)_prod_gen_$($WareId)_macro"
  $sourcePath = Join-Path -Path $UNPACKED_PATH -ChildPath "assets\structures\production\macros\$($CloneProductionModuleFrom)_macro.xml"
  $destinationPath = Join-Path -Path $MOD_PATH -ChildPath "assets\structures\production\macros\$prodMacroName.xml"

  Write-Host "Publish $destinationPath"
  New-Item -Path $destinationPath -Force
  Copy-Item $sourcePath -Destination $destinationPath 

  [xml]$newMacroXml = Get-Content $destinationPath
  # Update Macro Name
  $newMacroXml.macros.macro.name = $prodMacroName
  # Update Identification 
  $wareName = $Ware.DocumentElement.name
  $newMacroXml.macros.macro.properties.identification.name = "$wareName Production"
  $newMacroXml.macros.macro.properties.identification.shortname = $wareName
  # Update production
  $newMacroXml.macros.macro.properties.production.wares = "$($MOD_PREFIX)_$wareId"
  $newMacroXml.macros.macro.properties.production.queue.ware = "$($MOD_PREFIX)_$wareId"
  # Save
  $newMacroXml.save($destinationPath)
}

function Publish-ProductionIcon {
  param(
    [string]$WareId,
    [string]$CloneProductionModuleFrom
  )
  $prodMacroName = "$($MOD_PREFIX)_prod_gen_$($WareId)_macro"
  $sourcePath = Join-Path -Path $UNPACKED_PATH -ChildPath "assets\fx\gui\textures\stationmodules\$($CloneProductionModuleFrom)_macro.gz"
  $destinationPath = Join-Path -Path $MOD_PATH -ChildPath "assets\fx\gui\textures\stationmodules\$prodMacroName.dds"

  Write-Host "Publish $destinationPath"
  New-Item -Path $destinationPath -Force
  Expand-GZ -infile $sourcePath -outfile $destinationPath
}

function New-XmlCollection {
  param (
    [string]$Path, 
    [string]$CollectionName
  )  
  Write-Host "Publish $Path"
  New-Item -Path $Path -Force
  [xml]$Doc = New-Object System.Xml.XmlDocument
  $Doc.CreateXmlDeclaration("1.0","UTF-8",$null)
  $root = $doc.CreateNode("element", $CollectionName, $null)
  $Doc.AppendChild($root)
  $Doc.Save($Path)
  return [xml]$Doc
}
function Update-Index {
  param(
		[System.Xml.XmlDocument]$xml,
    [string]$Name,
    [string]$Value
  )
  $entryExist = (Select-XML -Xml $xml -XPath "//entry[@name=`"$($Name)`"]")
  if ($entryExist) { return $xml }
  
  $entry = $xml.CreateNode("element", "entry", $null)
  $entry.SetAttribute("name", $Name)
  $entry.SetAttribute("value", $Value)
  $xml.DocumentElement.AppendChild($entry)
}

function Update-Icons {
  param(
		[System.Xml.XmlDocument]$xml,
    [string]$Name,
    [string]$Texture
  )
  $entryExist = (Select-XML -Xml $xml -XPath "//entry[@name=`"$($Name)`"]")
  if ($entryExist) { return $xml }
  
  $entry = $xml.CreateNode("element", "icon", $null)
  $entry.SetAttribute("name", $Name)
  $entry.SetAttribute("texture", $Texture)
  $xml.DocumentElement.AppendChild($entry)
}


function Get-OrCreateXML {
    param (
    [string]$Path, 
    [string]$CollectionName
  )
  $pathExists = $(Test-Path $Path -PathType Leaf)
  Write-Host "Get $Path { $CollectionName }"
  [xml]$result = $(If ($pathExists) { 
      $(Get-Content $Path) 
    } Else { 
      $(New-XmlCollection -Path $Path -CollectionName $CollectionName) 
    } 
  )
  return $result
}

function Update-Manifest {
  param(
    [string]$WareId,
    [System.Xml.XmlDocument]$Ware
  )
  $prodMacroName = "$($MOD_PREFIX)_prod_gen_$($WareId)_macro"
  $wareMacroName = "$($MOD_PREFIX)_ware_$($WareId)_macro"

  $relIndexMacrosXmlPath = "index\macros.xml"
  $relIconsXmlPath = "libraries\icons.xml"
  $relProdMacroPath = "assets\structures\production\macros\$prodMacroName.xml"
  $relWareMacroPath = "assets\wares\macros\$wareMacroName.xml"
  $relIconAssetPath = "assets\fx\gui\textures\stationmodules\$prodMacroName.dds"

  $indexMacrosXmlPath = Join-Path -Path $MOD_PATH -ChildPath $relIndexMacrosXmlPath
  $iconsXmlPath =  Join-Path -Path $MOD_PATH -ChildPath $relIconsXmlPath

  $relModWarePath = Join-Path -Path $MOD_REL_PATH -ChildPath $relWareMacroPath
  $relModProdPath = Join-Path -Path $MOD_REL_PATH -ChildPath $relProdMacroPath  
  $relModIconPath = Join-Path -Path $MOD_REL_PATH -ChildPath $relIconAssetPath


  [xml]$indexMacrosXml = Get-OrCreateXML -Path $indexMacrosXmlPath -CollectionName "index"
  [xml]$iconsXml = Get-OrCreateXML -Path $iconsXmlPath -CollectionName "icons"

  # Write to index/macros.xml
  Update-Index $indexMacrosXml -Name $wareMacroName -Value $relModWarePath
  Update-Index $indexMacrosXml -Name $prodMacroName -Value $relModProdPath
  $indexMacrosXml.Save($indexMacrosXmlPath)

  # Write to libraries/icons.xml
  Update-Icons $iconsXml -Name "module_$prodMacroName" -Texture $relModIconPath
  $iconsXml.Save($iconsXmlPath)
}




$addWares = (Select-XML -Xml $addwaresXml -XPath '//generation/*')


foreach ($addWare in $addWares) {    
  
  $final = (Merge-WareDefaults -Node $addWare)
  $id = $addWare.Node.Attributes['id'].Value
  $prefixedId = "$($MOD_PREFIX)_$($id)"

  $cloneProductionModuleFrom = $addWare.Node.Attributes['cloneProductionModuleFrom'].Value

  # add prefixed id to the ware
  $addedAttribute = $final.DocumentElement.OwnerDocument.CreateAttribute('id')
  $addedAttribute.Value = $prefixedId
  $final.DocumentElement.Attributes.Append($addedAttribute)

  
  # $attrib = $final.Node.ware.Node.Attributes.CreateAttribute('id')
  # $attrib.Value = $id

  # Write-Host "final: $($final.InnerXml)"
  Publish-WareMacro -id $id -Ware $final
  Publish-ProductionMacro -WareId $id -CloneProductionModuleFrom $cloneProductionModuleFrom -Ware $final
  Publish-ProductionIcon -WareId $id -CloneProductionModuleFrom $cloneProductionModuleFrom
  Update-Manifest -WareId $id 
  
}

# $final = (Merge-Ware-Defaults -Node $ware[1])

# Write-Host "ware: $ware"

# $MainWindow.TopMost              = $false
# $ProgressBar1                    = New-Object system.Windows.Forms.ProgressBar
# $ProgressBar1.width              = 302
# $ProgressBar1.height             = 26
# $ProgressBar1.location           = New-Object System.Drawing.Point(58,61)
# $statusLabel                     = New-Object system.Windows.Forms.Label
# $statusLabel.text                = "statusLabel"
# $statusLabel.AutoSize            = $true
# $statusLabel.width               = 25
# $statusLabel.height              = 10
# $statusLabel.location            = New-Object System.Drawing.Point(58,34)
# $statusLabel.Font                = 'Microsoft Sans Serif,10'
# $messageLabel                    = New-Object system.Windows.Forms.Label
# $messageLabel.text               = "messageLabel"
# $messageLabel.AutoSize           = $true
# $messageLabel.width              = 25
# $messageLabel.height             = 10
# $messageLabel.location           = New-Object System.Drawing.Point(58,103)
# $messageLabel.Font               = 'Microsoft Sans Serif,10'
# $MainWindow.controls.AddRange(@($ProgressBar1,$statusLabel,$messageLabel))

# #Write your logic code here
# [void]$MainWindow.ShowDialog()
