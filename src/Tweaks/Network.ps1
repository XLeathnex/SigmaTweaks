<#
.SYNOPSIS
    TCP/IP and name-resolution tweaks.
#>

@(
    @{
        Id              = 'net.nagle'
        Name            = 'Disable Nagle''s algorithm'
        Category        = 'Network'
        Description     = 'Nagle batches small outbound packets to save bandwidth, which adds up to 200 ms of latency to the tiny packets games and voice chat send. Disabling it trades a little extra overhead for lower latency.'
        Risk            = 'Medium'
        RequiresRestart = $true
        Apply           = {
            $root = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
            $changed = 0
            foreach ($iface in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
                $props = Get-ItemProperty -LiteralPath $iface.PSPath -ErrorAction SilentlyContinue
                # Only interfaces that actually hold an address are worth touching.
                if (-not ($props.DhcpIPAddress -or $props.IPAddress)) { continue }
                Set-SigmaRegistryValue -Path $iface.PSPath -Name 'TcpAckFrequency' -Type DWord -Value 1 | Out-Null
                Set-SigmaRegistryValue -Path $iface.PSPath -Name 'TCPNoDelay' -Type DWord -Value 1 | Out-Null
                $changed++
            }
            if ($changed -eq 0) {
                Write-SigmaLog 'No configured network interfaces were found.' -Level Warn
                return $false
            }
            Write-SigmaLog "Nagle disabled on $changed interface(s)." -Level Debug
            return $true
        }
        Revert          = {
            $root = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
            foreach ($iface in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
                Remove-SigmaRegistryValue -Path $iface.PSPath -Name 'TcpAckFrequency' | Out-Null
                Remove-SigmaRegistryValue -Path $iface.PSPath -Name 'TCPNoDelay' | Out-Null
            }
            return $true
        }
        Test            = {
            $root = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
            $interfaces = @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
                $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                if ($props.DhcpIPAddress -or $props.IPAddress) { $props }
            })
            if ($interfaces.Count -eq 0) { return 'Unknown' }

            $tweaked = @($interfaces | Where-Object { $_.TcpAckFrequency -eq 1 -and $_.TCPNoDelay -eq 1 }).Count
            if ($tweaked -eq 0) { return 'NotApplied' }
            if ($tweaked -eq $interfaces.Count) { return 'Applied' }
            return 'Partial'
        }
    }

    @{
        Id          = 'net.llmnr'
        Name        = 'Disable LLMNR'
        Category    = 'Network'
        Description = 'Link-Local Multicast Name Resolution broadcasts any name your machine fails to resolve onto the local network, where anyone can answer it. Turning it off removes a well-known credential-relay vector and a little broadcast noise. DNS is unaffected.'
        Risk        = 'Low'
        Recommended = $true
        Registry    = @(
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'; Name = 'EnableMulticast'; Type = 'DWord'; Value = 0; Default = $null }
        )
    }

    @{
        Id              = 'net.netbios'
        Name            = 'Disable NetBIOS over TCP/IP'
        Category        = 'Network'
        Description     = 'Switches every adapter off NetBIOS name resolution, another legacy broadcast protocol that answers for names DNS could not resolve. Only turn this on if nothing on your network still browses shares by NetBIOS name.'
        Risk            = 'Medium'
        RequiresRestart = $true
        Apply           = {
            $root = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'
            $changed = 0
            foreach ($iface in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
                # 2 = disable NetBIOS over TCP/IP, 0 = use the DHCP server's setting.
                if (Set-SigmaRegistryValue -Path $iface.PSPath -Name 'NetbiosOptions' -Type DWord -Value 2) { $changed++ }
            }
            return ($changed -gt 0)
        }
        Revert          = {
            $root = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'
            foreach ($iface in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
                Set-SigmaRegistryValue -Path $iface.PSPath -Name 'NetbiosOptions' -Type DWord -Value 0 | Out-Null
            }
            return $true
        }
        Test            = {
            $root = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'
            $all = @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue |
                ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue })
            if ($all.Count -eq 0) { return 'Unknown' }

            $disabled = @($all | Where-Object { $_.NetbiosOptions -eq 2 }).Count
            if ($disabled -eq 0) { return 'NotApplied' }
            if ($disabled -eq $all.Count) { return 'Applied' }
            return 'Partial'
        }
    }

    @{
        Id          = 'net.dnscloudflare'
        Name        = 'Use Cloudflare DNS (1.1.1.1)'
        Category    = 'Network'
        Description = 'Points every active adapter at 1.1.1.1 and 1.0.0.1 instead of whatever your router hands out. Usually faster to resolve than an ISP resolver. Reverting hands DNS back to DHCP - if you had DNS servers set by hand, note them down first.'
        Risk        = 'Medium'
        Apply       = {
            $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
            if ($adapters.Count -eq 0) {
                Write-SigmaLog 'No connected network adapters were found.' -Level Warn
                return $false
            }
            foreach ($adapter in $adapters) {
                try {
                    Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses @('1.1.1.1', '1.0.0.1') -ErrorAction Stop
                    Write-SigmaLog "DNS set on $($adapter.Name)." -Level Debug
                } catch {
                    Write-SigmaLog "Could not set DNS on $($adapter.Name): $($_.Exception.Message)" -Level Warn
                }
            }
            Start-Process -FilePath 'ipconfig.exe' -ArgumentList '/flushdns' -Wait -NoNewWindow | Out-Null
            return $true
        }
        Revert      = {
            $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
            foreach ($adapter in $adapters) {
                try {
                    Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction Stop
                } catch {
                    Write-SigmaLog "Could not reset DNS on $($adapter.Name): $($_.Exception.Message)" -Level Warn
                }
            }
            return $true
        }
        Test        = {
            $servers = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty ServerAddresses)
            if ($servers -contains '1.1.1.1') { return 'Applied' }
            return 'NotApplied'
        }
    }
)
