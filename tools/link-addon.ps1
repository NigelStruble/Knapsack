<#
.SYNOPSIS
Links the Satchel folder into World of Warcraft AddOns folders.

.DESCRIPTION
Creates directory junctions, so the game loads the addon straight from this
repository and edits show up after a /reload. -Remove deletes only the links,
never the files in the repository.

.EXAMPLE
.\tools\link-addon.ps1

.EXAMPLE
.\tools\link-addon.ps1 -Flavors _classic_beta_, _retail_

.EXAMPLE
.\tools\link-addon.ps1 -Flavors _classic_beta_ -Remove
#>
param(
	[string]$WowPath = 'E:\World of Warcraft Windows',
	[string[]]$Flavors = @('_classic_beta_'),
	[switch]$Remove
)

$source = (Resolve-Path (Join-Path $PSScriptRoot '..\Satchel')).Path

foreach ($flavor in $Flavors) {
	$addons = Join-Path $WowPath "$flavor\Interface\AddOns"
	if (-not (Test-Path $addons)) {
		Write-Warning "No AddOns folder for $flavor ($addons)"
		continue
	}
	$link = Join-Path $addons 'Satchel'
	$item = Get-Item $link -Force -ErrorAction SilentlyContinue

	if ($Remove) {
		if (-not $item) {
			"Nothing to remove in $flavor"
		} elseif ($item.LinkType -eq 'Junction') {
			# rmdir removes the junction itself and leaves the target alone.
			cmd /c rmdir "$link"
			"Removed $link"
		} else {
			Write-Warning "$link is a real folder, not a link; left alone"
		}
		continue
	}

	if ($item) {
		"Already present: $link"
		continue
	}
	New-Item -ItemType Junction -Path $link -Target $source | Out-Null
	"Linked $link -> $source"
}
