function Convert-PeRvaToFileOffset {
    param(
        [Parameter(Mandatory = $true)][UInt32]$Rva,
        [Parameter(Mandatory = $true)][object[]]$Sections
    )

    foreach ($section in $Sections) {
        $start = [UInt64]$section.VirtualAddress
        $span = [Math]::Max([UInt64]$section.VirtualSize, [UInt64]$section.SizeOfRawData)
        $end = $start + $span
        if ([UInt64]$Rva -ge $start -and [UInt64]$Rva -lt $end) {
            return [Int64]([UInt64]$section.PointerToRawData + ([UInt64]$Rva - $start))
        }
    }
    return $null
}

function Get-PeSecurityProfile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $stream = [IO.File]::Open($fullPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($stream.Length -lt 256) { throw "Tệp quá nhỏ để là PE hợp lệ: $fullPath" }
        if ($reader.ReadUInt16() -ne 0x5A4D) { throw "Thiếu chữ ký MZ: $fullPath" }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 0 -or ($peOffset + 24) -gt $stream.Length) { throw "PE offset không hợp lệ: $fullPath" }

        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) { throw "Thiếu chữ ký PE: $fullPath" }
        $machine = $reader.ReadUInt16()
        $numberOfSections = $reader.ReadUInt16()
        $timeDateStamp = $reader.ReadUInt32()
        [void]$reader.ReadUInt32()
        [void]$reader.ReadUInt32()
        $sizeOfOptionalHeader = $reader.ReadUInt16()
        $characteristics = $reader.ReadUInt16()
        $optionalHeaderOffset = $stream.Position
        if (($optionalHeaderOffset + $sizeOfOptionalHeader) -gt $stream.Length) { throw "Optional header vượt kích thước tệp." }

        $magic = $reader.ReadUInt16()
        $isPe32Plus = $magic -eq 0x20B
        if (-not $isPe32Plus -and $magic -ne 0x10B) { throw ("Optional header magic không hỗ trợ: 0x{0:X4}" -f $magic) }

        $stream.Position = $optionalHeaderOffset + 70
        $dllCharacteristics = $reader.ReadUInt16()
        $numberOfRvaAndSizesOffset = $optionalHeaderOffset + $(if ($isPe32Plus) { 108 } else { 92 })
        $dataDirectoryOffset = $optionalHeaderOffset + $(if ($isPe32Plus) { 112 } else { 96 })
        $stream.Position = $numberOfRvaAndSizesOffset
        $numberOfRvaAndSizes = $reader.ReadUInt32()

        $loadConfigRva = [UInt32]0
        $loadConfigSize = [UInt32]0
        $clrRva = [UInt32]0
        $clrSize = [UInt32]0
        if ($numberOfRvaAndSizes -gt 10) {
            $stream.Position = $dataDirectoryOffset + (10 * 8)
            $loadConfigRva = $reader.ReadUInt32()
            $loadConfigSize = $reader.ReadUInt32()
        }
        if ($numberOfRvaAndSizes -gt 14) {
            $stream.Position = $dataDirectoryOffset + (14 * 8)
            $clrRva = $reader.ReadUInt32()
            $clrSize = $reader.ReadUInt32()
        }

        $sectionOffset = $optionalHeaderOffset + $sizeOfOptionalHeader
        $sections = New-Object System.Collections.Generic.List[object]
        for ($index = 0; $index -lt $numberOfSections; $index++) {
            $stream.Position = $sectionOffset + ($index * 40)
            $nameBytes = $reader.ReadBytes(8)
            $name = ([Text.Encoding]::ASCII.GetString($nameBytes)).Trim([char]0)
            $virtualSize = $reader.ReadUInt32()
            $virtualAddress = $reader.ReadUInt32()
            $sizeOfRawData = $reader.ReadUInt32()
            $pointerToRawData = $reader.ReadUInt32()
            $stream.Position = $stream.Position + 12
            $sectionCharacteristics = $reader.ReadUInt32()
            [void]$sections.Add([pscustomobject]@{
                Name = $name
                VirtualSize = $virtualSize
                VirtualAddress = $virtualAddress
                SizeOfRawData = $sizeOfRawData
                PointerToRawData = $pointerToRawData
                Characteristics = $sectionCharacteristics
            })
        }

        $corFlags = [UInt32]0
        if ($clrRva -ne 0 -and $clrSize -ge 20) {
            $clrOffset = Convert-PeRvaToFileOffset -Rva $clrRva -Sections $sections.ToArray()
            if ($null -ne $clrOffset -and ($clrOffset + 20) -le $stream.Length) {
                $stream.Position = $clrOffset + 16
                $corFlags = $reader.ReadUInt32()
            }
        }

        $guardFlags = [UInt32]0
        $loadConfigPresent = $loadConfigRva -ne 0 -and $loadConfigSize -ne 0
        if ($loadConfigPresent) {
            $loadConfigOffset = Convert-PeRvaToFileOffset -Rva $loadConfigRva -Sections $sections.ToArray()
            $guardFlagsOffset = if ($isPe32Plus) { 144 } else { 88 }
            if ($null -ne $loadConfigOffset -and $loadConfigSize -ge ($guardFlagsOffset + 4) -and ($loadConfigOffset + $guardFlagsOffset + 4) -le $stream.Length) {
                $stream.Position = $loadConfigOffset + $guardFlagsOffset
                $guardFlags = $reader.ReadUInt32()
            }
        }

        $architecture = switch ($machine) {
            0x8664 { "x64" }
            0x014C { "x86" }
            default { "0x{0:X4}" -f $machine }
        }
        $managed = [bool]($clrRva -ne 0)
        $clrIlOnly = [bool](($corFlags -band 0x00000001) -ne 0)
        $clr32BitRequired = [bool](($corFlags -band 0x00000002) -ne 0)
        $clr32BitPreferred = [bool](($corFlags -band 0x00020000) -ne 0)
        $managedPlatform = if ($managed -and $machine -eq 0x014C -and $clrIlOnly -and -not $clr32BitRequired -and -not $clr32BitPreferred) {
            "AnyCPU"
        } elseif ($managed -and $machine -eq 0x014C -and $clr32BitRequired) {
            "x86"
        } elseif ($managed -and $machine -eq 0x8664) {
            "x64"
        } else {
            "Unknown"
        }
        $epoch = [DateTime]::SpecifyKind((New-Object DateTime(1970, 1, 1)), [DateTimeKind]::Utc)

        return [pscustomobject]@{
            Path = $fullPath
            Architecture = $architecture
            ManagedPlatform = $managedPlatform
            Machine = ("0x{0:X4}" -f $machine)
            PeFormat = if ($isPe32Plus) { "PE32+" } else { "PE32" }
            TimeDateStampUtc = $epoch.AddSeconds($timeDateStamp).ToString("o")
            Managed = $managed
            ClrIlOnly = $clrIlOnly
            Clr32BitRequired = $clr32BitRequired
            Clr32BitPreferred = $clr32BitPreferred
            LargeAddressAware = [bool](($characteristics -band 0x0020) -ne 0)
            HighEntropyVa = [bool](($dllCharacteristics -band 0x0020) -ne 0)
            DynamicBase = [bool](($dllCharacteristics -band 0x0040) -ne 0)
            NxCompat = [bool](($dllCharacteristics -band 0x0100) -ne 0)
            NoSeh = [bool](($dllCharacteristics -band 0x0400) -ne 0)
            ControlFlowGuardHeader = [bool](($dllCharacteristics -band 0x4000) -ne 0)
            TerminalServerAware = [bool](($dllCharacteristics -band 0x8000) -ne 0)
            LoadConfigurationDirectoryPresent = [bool]$loadConfigPresent
            LoadConfigurationDirectorySize = [UInt32]$loadConfigSize
            GuardFlags = ("0x{0:X8}" -f $guardFlags)
            ControlFlowGuardInstrumented = [bool](($guardFlags -band 0x00000100) -ne 0)
            ControlFlowGuardFunctionTable = [bool](($guardFlags -band 0x00000400) -ne 0)
        }
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}
