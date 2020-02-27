
$ModuleName = 'PsiPS.AzComputeExtensions';

Remove-Module `
    -Name $ModuleName `
    -ErrorAction:SilentlyContinue;

Import-Module "$PSScriptRoot\..\src\$ModuleName.psd1";
