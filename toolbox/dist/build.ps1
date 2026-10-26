# SPDX-License-Identifier: GPL-3.0-only
# Compatibility entry point: all releases use the current component installer.
param([string]$Root = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
& ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $Root 'build-setup.ps1')))) -BuildDirectory $Root
