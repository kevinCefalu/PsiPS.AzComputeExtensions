
# Reference: bit.ly/CreateAnAzureVMSnapshot

param (
    [Parameter(Mandatory)]
    [string] $ResourceGroupName,

    [Parameter(Mandatory)]
    [string] $Location,

    [Parameter(Mandatory)]
    [string[]] $VMNames
);

foreach ($VMName in $VMNames)
{
    $VM = Get-AzVM `
        -ResourceGroupName $ResourceGroupName `
        -Name $VMName;

    $Snapshot = New-AzSnapshotConfig `
        -SourceUri $VM.StorageProfile.OsDisk.ManagedDisk.Id `
        -Location $Location `
        -CreateOption Copy;

    New-AzSnapshot `
        -Snapshot $Snapshot `
        -SnapshotName "$VMName-os-disk-snapshot-$(Get-Date -Format 'yyyyMMddHHmm')" `
        -ResourceGroupName $ResourceGroupName;

    $DataDiskIndex = 0;
    foreach ($DataDisk in $VM.StorageProfile.DataDisks)
    {
        $Snapshot = New-AzSnapshotConfig `
            -SourceUri $DataDisk.ManagedDisk.Id `
            -Location $Location `
            -CreateOption Copy;

        New-AzSnapshot `
            -Snapshot $Snapshot `
            -SnapshotName "$VMName-data-disk-$DataDiskIndex-snapshot-$(Get-Date -Format 'yyyyMMddHHmm')" `
            -ResourceGroupName $ResourceGroupName;

        $DataDiskIndex += 1;
    }
}
