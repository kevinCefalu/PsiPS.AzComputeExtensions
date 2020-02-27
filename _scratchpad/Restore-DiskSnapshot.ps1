
<# Reference Material:
    - http://bit.ly/2ux7bsL
    - http://bit.ly/CreateAnAzureVMFromSnapshot
#>

# TODO: Convert the following hard-coded variables to parameters, and
# TODO: (Potentially) break up logic into separate functions

# TODO: Convert throws to Write-Errors to avoid exiting the main foreach loop, and
# TODO: Investigate ErrorRecord(Exception, String, ErrorCategory, Object)

# TODO: Investigate "using" to replace long .Net class names, or
# TODO: Create a class that inherits from .NET class

# TODO: Clean up comments and regions

[string] $Location = '';
[string] $ResourceGroupName = '';
[PSCustomObject[]] $VMReferences = @(
    [PSCustomObject] @{
        Name = '';
        Size = '';
        StorageAccount = '';
        SnapShotNames = [PSCustomObject] @{
            OSDisk = '';
            DataDisks = [string[]] @(
                ''
            );
        };
    },
    [PSCustomObject] @{
        Name = '';
        Size = '';
        StorageAccount = '';
        SnapShotNames = [PSCustomObject] @{
            OSDisk = '';
            DataDisks = [string[]] @(
                ''
            );
        };
    }
);

function New-DiskName
{
    [CmdletBinding(DefaultParameterSetName = 'OSDisk')]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string] $VMName,

        [Parameter(Mandatory)]
        [ValidateSet('os-disk', 'data-disk')]
        [string] $DiskType,

        [Parameter(Mandatory, ParameterSetName = 'DataDisk')]
        [UInt16] $Index
    );

    $DiskName = "${VMName}-${DiskType}";

    if ($PSCmdlet.ParameterSetName -eq 'OSDisk')
    {
        $DiskName += '';
    }
    else
    {
        $DiskName += ('-' + $Index.ToString().PadLeft(2, '0'));
    }

    $DiskName += ('_' + (New-Guid).Guid.Replace('-', ''));

    return $DiskName;
}

$TempPSDefaultParameterValues = $PSDefaultParameterValues.Clone();

$PSDefaultParameterValues += @{
    'New-AzDiskConfig:CreateOption' = 'Copy';
    'New-Az*:Location' = $Location;
    '*-Az*:ResourceGroupName' = $ResourceGroupName;
    'Stop-AzVM:Force' = $true;
    'Remove-AzVM:Force' = $true;
    'Remove-AzDisk:Force' = $true;
    'Remove-AzStorageContainer:Force' = $true;
};

$TempErrorActionPreference = $ErrorActionPreference;
$ErrorActionPreference = 'Stop';

foreach ($VMReference in $VMReferences)
{
    #region Collect Existing VM Configuration(s)

    try
    {
        # Get the Existing VM
        $ExistingVM = Get-AzVM -Name $VMReference.Name;

        # Get the Existing VM's managed OS disk
        $ExistingOSDisk = Get-AzDisk -DiskName $ExistingVM.StorageProfile.OSDisk.Name;

        # Check if the existing VM has any managed data disks, and if so capture them
        if ($null -ne $ExistingVM.StorageProfile.DataDisks)
        {
            $ExistingDataDisks = [Collections.Generic.List[Microsoft.Azure.Commands.Compute.Automation.Models.PSDisk]]::new();

            foreach ($DataDiskReference in $ExistingVM.StorageProfile.DataDisks)
            {
                $ExistingDataDisks.Add((
                    Get-AzDisk -DiskName $DataDiskReference.Name
                ));
            }
        }

        # TODO: Check if one was configured on the existing VM and attempt to capture the storage account
        if (-not [String]::IsNullOrEmpty($VMReference.StorageAccount))
        {
            # Check if the existing VM has boot diagnostics
            # enabled, and capture the storage account container
            Set-AzCurrentStorageAccount -StorageAccountName `
                $VMReference.StorageAccount | Out-Null;

            $BootDiagnosticContainer = Get-AzStorageContainer `
                | Where-Object { $_.Name -match $ExistingVM.VMId };
        }

        #region Get the requested disk snapshot(s)

        # Get the VM's requested OS disk snapshot
        $OSDiskSnapshot = Get-AzSnapshot -SnapshotName `
            $VMReference.SnapShotNames.OSDisk;

        #endregion Get the requested disk snapshot(s)
    }
    catch
    {
        throw $_.Exception;

        continue;
    }

    #endregion Collect Existing VM Configuration(s)

    #region Set absent required configuration default(s) based on the existing VM

    # If no size is provided for the new VM, use the existing VM's size
    if ([String]::IsNullOrEmpty($VMReference.Size))
    {
        $VMReference.Size = $ExistingVM.HardwareProfile.VMSize;
    }

    <# # TODO: Add caching option to OS disk configuration (remember to check for references to OG value below)
    # If no disk caching configuration is provided for the managed OS
    # disk, use the existing VM's managed OS disk caching configuration
    if ([String]::IsNullOrEmpty($VMReference.SnapShotNames.OSDisk.Caching))
    {
        $VMReference.SnapShotNames.OSDisk.Caching = $ExistingVM.StorageProfile.OsDisk.Caching;
    } #>

    <# # TODO: Add caching option to data disk configuration (remember to check for references to OG value below)
    # If no data caching configuration is provided for the managed data
    # disk(s), use the existing VM's managed OS disk caching configuration
    if ([String]::IsNullOrEmpty($VMReference.SnapShotNames.OSDisk.Caching))
    {
        $VMReference.SnapShotNames.OSDisk.Caching = $ExistingVM.StorageProfile.OsDisk.Caching;
    } #>

    #endregion Set absent required configuration default(s) based on the existing VM

    #region Create new managed disk(s) from the requested disk snapshot(s)

    try
    {
        <# TODO: Remove if the following works
            -DiskName (
                $ExistingOSDisk.Name.SubString(0,
                    $ExistingOSDisk.Name.IndexOf('_') + 1) +
                (New-Guid).Guid.Replace('-', '')
            ) `
        #>

        # Create the new managed OS disk
        $NewOSDisk = New-AzDisk `
            -DiskName (
                New-DiskName `
                    -VMName $ExistingVM.Name `
                    -DiskType 'OSDisk'
            ) `
            -Disk (
                New-AzDiskConfig `
                    -AccountType $OSDiskSnapshot.Sku.Name `
                    -SourceResourceId $OSDiskSnapshot.Id
            );
    }
    catch
    {
        throw $_.Exception;

        continue;
    }

    try
    {
        # If any were requested, create the new managed data disk(s)
        if ($null -ne $VMReference.SnapShotNames.DataDisks)
        {
            $LunNumber = 0;
            $NewDataDisks = [Collections.Generic.List[Microsoft.Azure.Commands.Compute.Automation.Models.PSDisk]]::new();

            foreach ($SnapshotName in $VMReference.SnapShotNames.DataDisks)
            {
                # TODO: Move this to the top data "collection" region
                # Get the VM's requested data disk snapshot
                $DataDiskSnapshot = Get-AzSnapshot -SnapshotName $SnapshotName;

                <# TODO: Remove if the following works
                    -DiskName (
                        $VMReference.Name + '-data-disk-' +
                        $LunNumber.ToString().PadLeft(2, '0') +
                        '_' + (New-Guid).Guid.Replace('-', '')
                    ) `
                #>

                # Create the new managed data disk
                $NewDataDisks.Add((New-AzDisk `
                    -DiskName (
                        New-DiskName `
                            -VMName $ExistingVM.Name `
                            -DiskType 'DataDisk' `
                            -Index $LunNumber
                    ) `
                    -Disk (
                        New-AzDiskConfig `
                            -AccountType $DataDiskSnapshot.Sku.Name `
                            -SourceResourceId $DataDiskSnapshot.Id
                    )
                ));

                $LunNumber += 1;
            }
        }
    }
    catch
    {
        throw $_.Exception;

        continue;
    }

    #endregion Create new managed disk(s) from the requested disk snapshot(s)

    #region Stop & Remove the Existing VM

    try
    {
        # Stop the existing VM
        $StopExistingVMResponse = $ExistingVM | Stop-AzVM;

        <# TODO: Capture output: bit.ly/PSComputeLongRunningOperation
            OperationId : 4e1ce895-bf15-4195-8aac-aaa45e46b78b
            Status      : Succeeded
            StartTime   : 2020-02-26 05:11:24 PM
            EndTime     : 2020-02-26 05:12:10 PM
            Error       :
        #>

        # Remove the existing VM
        $RemoveExistingVMResponse = $ExistingVM | Remove-AzVM;

        <# TODO: Capture output: bit.ly/PSComputeLongRunningOperation
            OperationId : f71ee995-a3d6-4bac-8bb5-b174e35916a7
            Status      : Succeeded
            StartTime   : 2020-02-26 05:12:11 PM
            EndTime     : 2020-02-26 05:12:52 PM
            Error       :
        #>
    }
    catch
    {
        throw $_.Exception;

        continue;
    }

    #endregion Stop & Remove the Existing VM

    #region Remove the orphaned resource(s)

    #region Remove the orphaned managed disk(s)

    try
    {
        # Remove the orphaned managed OS disk
        $RemoveExistingOSDiskResponse = $ExistingOSDisk | Remove-AzDisk;

        <# TODO: Capture output: bit.ly/PSComputeLongRunningOperation
            Name      : a55cc433-d05b-46f4-9c7d-c435937aee23
            StartTime : 2020-02-26 07:29:11 PM
            EndTime   : 2020-02-26 07:29:42 PM
            Status    : Succeeded
            Error     :
        #>
    }
    catch
    {
        Write-Warning (
            "Failed to remove the orphaned $($ExistingOSDisk.Name) " +
            "managed OS disk! Please try again, later. Moving on..."
        );

        continue;
    }

    # If any exist, remove the orphaned managed data disk(s)
    if ($null -ne $ExistingDataDisks)
    {
        foreach ($ExistingDataDisk in $ExistingDataDisks)
        {
            try
            {
                # Remove the orphaned managed data disk
                $RemoveExistingDataDiskResponse = $ExistingDataDisk | Remove-AzDisk;

                <# TODO: Capture output: bit.ly/PSComputeLongRunningOperation
                    Name      : fc2e9bea-a10d-46d6-a107-38f0d518225f
                    StartTime : 2020-02-26 05:21:29 PM
                    EndTime   : 2020-02-26 05:22:00 PM
                    Status    : Succeeded
                    Error     :
                #>
            }
            catch
            {
                Write-Warning (
                    "Failed to remove the orphaned $($ExistingDataDisk.Name) " +
                    "managed data disk! Please try again, later. Moving on..."
                );

                continue;
            }
        }
    }

    #endregion Remove the orphaned managed disk(s)

    try
    {
        # If it exists, remove the orphaned boot diagnostics storage account container
        if ($null -ne $BootDiagnosticContainer)
        {
            if (-not ($BootDiagnosticContainer | Remove-AzStorageContainer -PassThru))
            {
                throw [Exception]::new((
                    "Failed to remove the $($BootDiagnosticContainer) container in " +
                    "the $() storage account. Please try again, later. Moving on..."
                ));
            }
        }
    }
    catch
    {
        Write-Warning $_.Exception.Message;

        # return;
    }

    #endregion Remove the orphaned resource(s)

    #region Create the New VM's Configuration

    try
    {
        # Create the new VM's base configuration, and
        # add the NIC from the previously existing VM
        $NewVMConfig = New-AzVMConfig `
                -VMName $ExistingVM.Name `
                -VMSize $VMReference.Size `
            | Add-AzVMNetworkInterface `
                -Id $ExistingVM.NetworkProfile.NetworkInterfaces.Id;

        # Add the new managed OS disk to the new VM's configuration
        $NewVMConfig = Set-AzVMOSDisk `
            -VM $NewVMConfig `
            -Name $NewOSDisk.Name `
            -CreateOption 'Attach' `
            -ManagedDiskId $NewOSDisk.Id `
            -Caching $ExistingVM.StorageProfile.OsDisk.Caching `
            -Windows;

        # If any were created, add the new managed
        # data disk(s) to the new VM's configuration
        if ($null -ne $NewDataDisks)
        {
            $LunNumber = 0;

            foreach ($NewDataDisk in $NewDataDisks)
            {
                # TODO: Get caching from either configuration or from existing configuration
                $NewVMConfig = Add-AzVMDataDisk `
                    -VM $NewVMConfig `
                    -Name $NewDataDisk.Name `
                    -CreateOption 'Attach' `
                    -ManagedDiskId $NewDataDisk.Id `
                    -Caching 'ReadOnly' `
                    -Lun $LunNumber;

                $LunNumber += 1;
            }
        }

        # If a storage account was defined, enable boot diagnostics
        # on the new VM, and set the storage location as it was defined
        if (-not [String]::IsNullOrEmpty($VMReference.StorageAccount))
        {
            $NewVMConfig = Set-AzVMBootDiagnostic `
                -VM $NewVMConfig `
                -StorageAccountName $VMReference.StorageAccount `
                -Enable;
        }
    }
    catch
    {
        throw $_.Exception;

        continue;
    }

    #endregion Create the New VM's Configuration

    try
    {
        # Create the New VM
        $NewVMResponse = $NewVMConfig | New-AzVM;

        <# TODO: Capture output: bit.ly/PSAzureOperationResponse
        RequestId IsSuccessStatusCode StatusCode ReasonPhrase
        --------- ------------------- ---------- ------------
                                True         OK OK
        #>
    }
    catch
    {
        throw $_.Exception;

        continue;
    }
}

$ErrorActionPreference = $TempErrorActionPreference;

$PSDefaultParameterValues = $TempPSDefaultParameterValues.Clone();

# TODO: Clean up variables
