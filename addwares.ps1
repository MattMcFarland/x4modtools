using namespace System.Xml

param (
    [string]$use = "./addwares.xml",
    [switch]$force = $false
 )

$ErrorActionPreference = "Stop"
 
# load it into an XML object:
[xml]$addwaresXml = Get-Content $use

Import-Module ./libs/vendor/modules/PSWriteColor

if ($force) {
  Write-Host "Force option enabled.  I sure hope you know what you are doing!"
}

. ./libs/Merge-XML.ps1
. ./libs/Expand-GZ.ps1

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

$MOD_PREFIX = Get-ConfigItem "prefix"
$GAME_PATH = Get-ConfigItem("gamepath")
$MOD_PATH = Join-Path -Path $GAME_PATH -ChildPath $(Get-ConfigItem("modpath"))
$MOD_REL_PATH = Get-ConfigItem("modpath")
$UNPACKED_PATH = Join-Path -Path $GAME_PATH -ChildPath $(Get-ConfigItem("unpackedPath"))

$MSG_FORCE = " Use option -force to overwrite"

Write-Verbose "MOD_PREFIX: $MOD_PREFIX"
Write-Verbose "GAME_PATH: $GAME_PATH"
Write-Verbose "MOD_PATH: $MOD_PATH"
Write-Verbose "UNPACKED_PATH: $UNPACKED_PATH"

function Start-Main {
  [OutputType([void])]  
  $addWares = (Select-XML -Xml $addwaresXml -XPath '//generation/*')
  foreach ($addWare in $addWares) {
    $id = $addWare.Node.Attributes['id'].Value
    $cloneProductionModuleFrom = $addWare.Node.Attributes['cloneProductionModuleFrom'].Value

    Write-Color -Text "Process ", "ware ", $id, " from ", $cloneProductionModuleFrom -Color DarkCyan, DarkGray, White, DarkGray, White

    $newWare = New-Ware -WareId $id -Ware $addWare

    Publish-WareMacro -WareId $id
    Publish-ProductionMacro -WareId $id -CloneProductionModuleFrom $cloneProductionModuleFrom -Ware $newWare
    Publish-ProductionIcon -WareId $id -CloneProductionModuleFrom $cloneProductionModuleFrom
    Update-Manifest -WareId $id
    Update-Modules -WareId $id -CloneProductionModuleFrom $cloneProductionModuleFrom -Ware $newWare
    # Update-ModuleGroups -WareId $id -CloneProductionModuleFrom $cloneProductionModuleFrom -Ware $newWare  
    # Update-Baskets -WareId $id -CloneProductionModuleFrom $cloneProductionModuleFrom -Ware $newWare
    
    Write-Host " "
  }
  return 
}

function New-Ware {
  [OutputType([XmlDocument])]
  param (
    [string]$WareId,
    [XmlDocument]$Ware
  )
  $newWare = (Merge-WareDefaults -Node $Ware)
  $wareName = Get-WareName $WareId
  $addedAttribute = $newWare.DocumentElement.OwnerDocument.CreateAttribute('id')
  $addedAttribute.Value = $wareName
  $newWare.DocumentElement.Attributes.Append($addedAttribute) | Out-Null
  return $newWare
}

function Update-Manifest {
  [OutputType([void])]  
  param(
    [string]$WareId,
    [XmlDocument]$Ware
  )
  $prodMacroName = Get-ProductionMacroName -WareId $WareId
  $wareMacroName = Get-WareMacroName -WareId $WareId

  $relIndexMacrosXmlPath = "index/macros.xml"
  $relIconsXmlPath = "libraries/icons.xml"
  $relProdMacroPath = "assets/structures/production/macros/$prodMacroName.xml"
  $relWareMacroPath = "assets/wares/macros/$wareMacroName.xml"
  $relIconAssetPath = "assets/fx/gui/textures/stationmodules/$prodMacroName.dds"

  $indexMacrosXmlPath = Join-Path -Path $MOD_PATH -ChildPath $relIndexMacrosXmlPath
  $iconsXmlPath =  Join-Path -Path $MOD_PATH -ChildPath $relIconsXmlPath

  $relModWarePath = Join-Path -Path $MOD_REL_PATH -ChildPath $relWareMacroPath
  $relModProdPath = Join-Path -Path $MOD_REL_PATH -ChildPath $relProdMacroPath  
  $relModIconPath = Join-Path -Path $MOD_REL_PATH -ChildPath $relIconAssetPath

  $indexMacrosXml = Get-OrCreateXML -Path $indexMacrosXmlPath -CollectionName "index"
  $iconsXml = Get-OrCreateXML -Path $iconsXmlPath -CollectionName "icons"

  $indexMacrosPathExists = $(Test-Path $indexMacrosXmlPath -PathType Leaf)
  If ($indexMacrosPathExists) {
    Write-Color -Text "Get     ",  $indexMacrosXmlPath,  " <$CollectionName/>" -Color DarkCyan, DarkGray, DarkGreen
    [xml]$indexMacrosXml = Get-Content $indexMacrosPathExists
  } Else {
    Write-Color -Text "New     ",  $indexMacrosXmlPath,  " <$CollectionName/>" -Color DarkGreen, DarkGray, DarkGreen
    New-Item -Path $Path -Force | Out-Null
    [xml]$Doc = New-Object XmlDocument
    $Doc.CreateXmlDeclaration("1.0","UTF-8",$null) 
    $root = $Doc.CreateNode("element", $CollectionName, $null) 
    $Doc.AppendChild($root)
    $Doc.Save($Path)
    return $Doc
  }

  # Write to index/macros.xml
  Update-Index -xml $indexMacrosXml -Name $wareMacroName -Value $relModWarePath
  Update-Index -xml $indexMacrosXml -Name $prodMacroName -Value $relModProdPath
  $indexMacrosXml.Save($indexMacrosXmlPath)

  # Write to libraries/icons.xml
  Update-Icons $iconsXml -Name "module_$prodMacroName" -Texture $relModIconPath
  $iconsXml.Save($iconsXmlPath)
}

function Get-ModuleFromUnpacked {
  [OutputType([XmlElement])]
  param(
    [string]$ModuleId
  )
  $unpackedModulesXmlPath = Resolve-LibraryFilePathXml -Source "FromUnpacked" -Name "modules"  
  return (Select-XML -Path $unpackedModulesXmlPath -XPath "//module[@id='$ModuleId']").Node
}

function Update-Modules {
  [OutputType([void])]
  param(
    [string]$WareId,  
    [string]$CloneProductionModuleFrom,
    [XmlDocument]$Ware
  )

  $modulesXmlPath = Resolve-LibraryFilePathXml -Source "FromModule" -Name "modules"  
  [xml]$modulesXml = Get-OrCreateXML -Path $modulesXmlPath -CollectionName "modules"  
  $prodModuleId = "$($MOD_PREFIX)_prod_gen_$WareId"
  $moduleExist = (Select-XML -Xml $modulesXml -XPath "//module[@id=`"$($prodModuleId)`"]")

  if ($moduleExist -and -not $force) {
    Write-Color -Text "SKIP    ", $modulesXmlPath,  " (id ", $prodModuleId, " already exists)", $MSG_FORCE -Color Magenta, DarkGray, Red, White, Red, Gray
    return 
  }
  
  [XmlElement]$baseProdModuleSrc = Get-ModuleFromUnpacked -ModuleId $CloneProductionModuleFrom
  
  $baseProdModule = $baseProdModuleSrc.CloneNode($true)

  $prodName = Get-ProductionName -WareId $WareId
  $wareName = Get-WareName -WareId $WareId
  
  $baseProdModule.Attributes['id'].Value = $prodName
  $baseProdModule.Attributes['group'].Value = $prodName
  $baseProdModule.category.Attributes['ware'].Value = $wareName
  $baseProdModule.compatibilities.production[0].Attributes['ware'].Value = $wareName

  if ($null -eq $moduleExist) {
    Write-Color -Text "        NEW ", $prodName, " -> ", $wareName -Color DarkGreen, White, DarkGray, White
    $modulesXml.DocumentElement.AppendChild($modulesXml.ImportNode($baseProdModule, $true))
  } else {
    [XmlDocument]$baseProdModuleXml = $(New-XmlCollectionContent -CollectionName "modules").Node
    Write-Color -Text "        UPDATE ", $baseProdModule.Name, " -> ", $wareName -Color DarkGreen, White, DarkGray, White
    $baseProdModuleXml.AppendChild($baseProdModuleXml.ImportNode($baseProdModule, $true))
    [xml]$update = Merge-XML $baseProdModuleXml $modulesXml
    $modulesXml = $update
  }  

  $modulesXml.Save($modulesXmlPath)

}

function Publish-WareMacro {
  [OutputType([void])]
  param(
    [string]$WareId 
  )

  # Create Wares Macro
  $wareMacroName = Get-WareMacroName -WareId $WareId
  $sourceWareMacroPath = Resolve-WareMacroPath -Source "FromUnpacked"
  $destinationWareMacroPath = Resolve-WareMacroPath -Source "FromModule" -WareId $WareId
  $pathExists = $(Test-Path $destinationWareMacroPath -PathType Leaf)
  
  if ($pathExists -and -not $force) {
    Write-Color -Text "SKIP    ", $destinationWareMacroPath, " (File already exists)", $MSG_FORCE -Color Magenta, DarkGray, Red, Gray
    return     
  }
  Write-Color -Text "Publish ", $destinationWareMacroPath,  " (Ware Macro)" -Color DarkGreen, DarkGray, DarkGreen

  New-Item -Path $destinationWareMacroPath -Force | Out-Null
  Copy-Item $sourceWareMacroPath -Destination $destinationWareMacroPath 

  # update the copied macro to contain the new id
  [xml]$newWareMacroXml = Get-Content $destinationWareMacroPath
  $newWareMacroXml.macros.macro.name = $wareMacroName

  # save the updated xml
  $newWareMacroXml.save($destinationWareMacroPath)
}

function Publish-ProductionMacro {
  [OutputType([void])]
  param(
    [string]$WareId,
    [XmlDocument]$Ware,
    [string]$CloneProductionModuleFrom
  )
  $prodMacroName = Get-ProductionMacroName -WareId $WareId
  $sourcePath = Resolve-ProductionModuleFromPath -Source "FromUnpacked" -CloneProductionModuleFrom $CloneProductionModuleFrom
  $destinationPath = Resolve-ProductionModuleFromPath -Source "FromModule" -WareId $WareId
  $pathExists = $(Test-Path $destinationPath -PathType Leaf)

  if ($pathExists -and -not $force) {
    Write-Color -Text "SKIP    ", $destinationPath, " (File already exists)", $MSG_FORCE -Color Magenta, DarkGray, Red, Gray
    return     
  }
  Write-Color -Text "Publish ", $destinationPath,  " (Macro)" -Color DarkGreen, DarkGray, DarkGreen

  New-Item -Path $destinationPath -Force | Out-Null
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
  [OutputType([void])]
  param(
    [string]$WareId,
    [string]$CloneProductionModuleFrom
  )
  $sourcePath = Resolve-ProductionModuleIconFromPath -Source "FromUnpacked" -CloneProductionModuleFrom $CloneProductionModuleFrom
  $destinationPath = Resolve-ProductionModuleIconFromPath -Source "FromModule" -WareId $WareId
  $pathExists = Test-Path $destinationPath -PathType Leaf

  if ($pathExists -and -not $force) {
    Write-Color -Text "SKIP    ", $destinationPath, " (File already exists)", $MSG_FORCE -Color Magenta, DarkGray, Red, Gray
    return 
  }
  Write-Color -Text "Publish ", $destinationPath, " (Icon Texture)" -Color DarkGreen, DarkGray, DarkGreen

  New-Item -Path $destinationPath -Force | Out-Null
  Expand-GZ -infile $sourcePath -outfile $destinationPath
}

function Merge-WareDefaults {
  [OutputType([XmlDocument])]
  param(
      [xml]$Node
  )
  $wareDefaults = (Select-XML -Xml $addwaresXml -XPath '//configuration/defaults')
  return Merge-XML $wareDefaults $Node
}

function Get-WareName {
  [OutputType([string])]
  param(
    [string]$WareId
  )
  return "$($MOD_PREFIX)_$($WareId)"  
}

function Get-ProductionName {
  [OutputType([string])]
  param (
    [string]$WareId
  )
  return "$($MOD_PREFIX)_prod_gen_$($WareId)"
}

function Get-ProductionMacroName {
  [OutputType([string])]
  param(
    [string]$WareId
  )
  return  "$($MOD_PREFIX)_prod_gen_$($WareId)_macro"
}

function Get-WareMacroName {
  [OutputType([string])]  
  param(
    [string]$WareId
  )
  return "$($MOD_PREFIX)_ware_$($WareId)_macro"
}

function Resolve-WareMacroPath {
  [OutputType([string])]  
  param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('FromModule','FromUnpacked')]
    [string]$Source,    
    [string]$WareId
  )
  $wareMacroName = Get-WareMacroName -WareId $WareId
  switch ($Source) {
    'FromModule' {
      return Join-Path -Path $MOD_PATH -ChildPath "assets/wares/macros/$wareMacroName.xml"
    }
    'FromUnpacked' {
      return Join-Path -Path $UNPACKED_PATH -ChildPath "assets/wares/macros/ware_default_macro.xml"
    }
  }
}

function Resolve-LibraryFilePathXml {
  [OutputType([string])]  
  param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('FromModule','FromUnpacked')]
    [string]$Source,
    [string]$Name
  )
  $relPath = "libraries/$Name.xml"
  switch ($Source) {
    'FromModule' {
      return Join-Path -Path $MOD_PATH -ChildPath $relPath
    }
    'FromUnpacked' {
      return Join-Path -Path $UNPACKED_PATH -ChildPath $relPath
    }
  }
}

function Resolve-ProductionModuleIconFromPath {
  [OutputType([string])]  
  param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('FromModule','FromUnpacked')]
    [string]$Source,
    [string]$WareId,
    [string]$CloneProductionModuleFrom
  )
  Switch ($Source) {
    'FromModule' {
      $prodMacroName = Get-ProductionMacroName -WareId $WareId
      return Join-Path -Path $MOD_PATH -ChildPath "assets/fx/gui/textures/stationmodules/$prodMacroName.dds"
    }
    'FromUnpacked' {
      return Join-Path -Path $UNPACKED_PATH -ChildPath "assets/fx/gui/textures/stationmodules/$($CloneProductionModuleFrom)_macro.gz"
    }
  }
}

function Resolve-ProductionModuleFromPath {
  [OutputType([string])]  
  param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('FromModule','FromUnpacked')]
    [string]$Source,
    [string]$WareId,
    [string]$CloneProductionModuleFrom
  )
  Switch ($Source) {
    'FromModule' {
      $prodMacroName = Get-ProductionMacroName -WareId $WareId
      return Join-Path -Path $MOD_PATH -ChildPath "assets/structures/production/macros/$prodMacroName.xml"  
    }
    'FromUnpacked' {
      return Join-Path -Path $UNPACKED_PATH -ChildPath "assets/structures/production/macros/$($CloneProductionModuleFrom)_macro.xml"
    }
  }  
}

function New-XmlCollectionContent {
  [OutputType([xml])]  
  param (
    [string]$CollectionName
  )
  [xml]$Doc = New-Object XmlDocument
  $Doc.CreateXmlDeclaration("1.0","UTF-8",$null)
  $root = $Doc.CreateNode("element", $CollectionName, $null)
  $Doc.AppendChild($root)
  return $([xmlDocument]$Doc.OwnerDocument).OwnerDocument
}


function Update-Index {
  [OutputType([void])]  
  param(
		[XmlDocument]$xml,
    [string]$Name,
    [string]$Value
  )
  $entryExist = (Select-XML -Xml $xml -XPath "//entry[@name='$Name']")
  if ($entryExist -and -not $force) { 
    Write-Color -Text "        SKIP ", "(", "Index Entry: $Name", " already exists)", $MSG_FORCE -Color Magenta, Red, White, Red, Gray
    return 
  }
  
  $entry = $xml.CreateNode("element", "entry", $null)
  $entry.SetAttribute("name", $Name)
  $entry.SetAttribute("value", $Value)
  
  if ($null -eq $entryExist) {
    Write-Color -Text "        NEW ", $Name, " -> ", $Value -Color DarkGreen, White, DarkGray, White
    $xml.DocumentElement.AppendChild($entry)
  } else {
    Write-Color -Text "        UPDATE ", $Name, " -> ", $Value -Color DarkGreen, White, DarkGray, White
    $update = Merge-XML $xml $entry.OwnerDocument
    $xml = $update    
  }  
}

function Update-Icons {
  [OutputType([void])]  
  param(
		[XmlDocument]$xml,
    [string]$Name,
    [string]$Texture
  )
  $entryExist = (Select-XML -Xml $xml -XPath "//icon[@name='$Name']")
  if ($entryExist -and -not $force) {
    Write-Color -Text "        SKIP ", "(", "Icon: $Name", " already exists)", $MSG_FORCE -Color Magenta, Red, White, Red, Gray
    return
  }
  $entry = $xml.CreateNode("element", "icon", $null)
  $entry.SetAttribute("name", $Name)
  $entry.SetAttribute("texture", $Texture)

  if ($null -eq $entryExist) {
    Write-Color -Text "        NEW ", $Name, " -> ", $Texture -Color DarkGreen, White, DarkGray, White
    $xml.DocumentElement.AppendChild($entry)
  } else {
    Write-Color -Text "        UPDATE ", $Name, " -> ", $Texture -Color DarkGreen, White, DarkGray, White
    $update = Merge-XML $xml $entry.OwnerDocument
    $xml = $update    
  }
}


Start-Main

# $newWare = (Merge-Ware-Defaults -Node $ware[1])



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
