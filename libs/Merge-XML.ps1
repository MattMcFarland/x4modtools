function Get-NodePath()
{
	<#
		.SYNOPSIS
			Returns an xPath for a given node
		.PARAMETER node
			The node for which the xPath is needed
	#>

	[cmdletbinding()]
	param(
		[Parameter(Mandatory=$true,Position=0)]
		$node
	)

	$tmpNode = $node
	$path = "/$($node.LocalName)"

	while ($tmpNode.ParentNode -ne $null)
	{
		if($($tmpNode.ParentNode.LocalName) -Notlike "#document")
		{
			$path = "/$($tmpNode.ParentNode.LocalName)$path"
		}

		$tmpNode = $tmpNode.ParentNode
	}
	return $path
}
function Import-Nodes()
{
	<#
		.SYNOPSIS
			Imports a node into overrideXML.  overrideXML is assumed to be set.
		.PARAMETER node
			The node which is to be imported into overrideXML.
	#>

	[cmdletbinding()]
	param(
		[Parameter(Mandatory=$true,Position=0)]
		$node
	)

	if($overrideXML -eq $null)
	{
		Throw "overrideXML is not set"
	}

	if($node.LocalName -ne "#text")
	{
		$path = Get-NodePath $node
		write-verbose "path : $path"
		try
		{
			$nodeCheck = $overrideXML | select-xml -xPath "$path" 2> $null
		}
		catch 
		{
			$nodeCHeck = $null
		}
		#if doesn't exist in overrideXML
		if($nodeCheck -eq $null)
		{
			try {
			$lastIndex = $path.LastIndexOf("/")
			$parentPath = $path.SubString(0,$lastIndex)
			$parentNode = $overrideXML | select-xml -xPath "$parentPath"
			$($parentNode.Node).AppendChild($overrideXML.ImportNode($Node, $true)) | Out-Null
			} catch {
				write-verbose "skipping $($node.LocalName)"
			}

			write-verbose "$($node.LocalName) doesn't exist in destination xml"
		}
	}
	Foreach ($childNode in $node.ChildNodes) 
	{
		Import-Nodes $childNode
	}
}
function Merge-XML()
{
	<#
		.SYNOPSIS
			Merges XML nodes from one XML file into another.
		.PARAMETER fromXML
			The XML object that contains the nodes to be merged.
		.PARAMETER overrideXML
			The XML object to which the nodes will be merged. 
	#>

	[cmdletbinding()]
	param(
		[Parameter(Mandatory=$true,Position=0)]
		[xml]$fromXML,
		[Parameter(Mandatory=$true,Position=1)]
		[xml]$overrideXML
	)
	Import-Nodes $fromXML
	return $overrideXML
}
