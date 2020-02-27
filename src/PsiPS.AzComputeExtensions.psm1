
[cmdletbinding()]
param ( );

<# $OnImport = @(
    Get-ChildItem (Join-Path -Path $PSScriptRoot -ChildPath 'on-import') `
        -Filter '*.ps1' -Recurse -ErrorAction:Stop
); #>

$Private = @(
    Get-ChildItem (Join-Path -Path $PSScriptRoot -ChildPath 'private') `
        -Filter '*.ps1' -Recurse -ErrorAction:Stop
);

$Public = @(
    Get-ChildItem (Join-Path -Path $PSScriptRoot -ChildPath 'public') `
        -Filter '*.ps1' -Recurse -ErrorAction:Stop
);

foreach ($Import in @($OnImport + $Private + $Public))
{
    try
    {
        . $Import.FullName;
    }
    catch
    {
        throw "Unable to dot source [$($Import.FullName)]";
    }
}

Export-ModuleMember -Function $Public.Basename
