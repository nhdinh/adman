#Requires -Version 5.1
<#
.SYNOPSIS
    ConvertTo-AdmanBulkInput - normalizes pipeline search output into the canonical
    bulk input record (D-01/D-02).

.DESCRIPTION
    Accepts objects from the pipeline (e.g. Find-AdmanUser, Find-AdmanComputer, or
    report verbs) and emits one bulk input record per object:
      { ObjectType, Identity, Action, TargetPath, GroupIdentity }.
    ObjectType defaults to 'User' when the input lacks it. Identity is taken from
    the input's DistinguishedName.
#>

Set-StrictMode -Version Latest

function ConvertTo-AdmanBulkInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject,

        [Parameter(Mandatory)]
        [ValidateSet('Disable', 'Enable', 'Move', 'AddGroup', 'RemoveGroup')]
        [string]$Action,

        [string]$TargetPath,

        [string]$GroupIdentity
    )

    process {
        $objectType = 'User'
        if ($InputObject.PSObject.Properties['ObjectType'] -and $InputObject.ObjectType) {
            $objectType = [string]$InputObject.ObjectType
        }

        $identity = [string]$InputObject
        if ($InputObject.PSObject.Properties['DistinguishedName'] -and $InputObject.DistinguishedName) {
            $identity = [string]$InputObject.DistinguishedName
        }

        [pscustomobject]@{
            ObjectType    = $objectType
            Identity      = $identity
            Action        = $Action
            TargetPath    = $TargetPath
            GroupIdentity = $GroupIdentity
        }
    }
}
