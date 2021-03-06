function Push-Job {
    [CmdletBinding()]
    param (
            [Parameter(Mandatory=$true)]
            [string]
            $Name,

            [Parameter(Mandatory=$true,
                ValueFromPipeline=$true)]
            [ScriptBlock]
            $ScriptBlock,

            [Parameter(Mandatory=$false)]
            [ScriptBlock]
            $InitializationScript,

            [Parameter(Mandatory=$false)]
            [int]
            $ParallelJobCount=10,

            [Parameter(Mandatory=$false)]
            [switch]
            $Wait=$false
          )

    PROCESS {
        if ($global:JobWatcher -eq $null) {
            $global:JobWatcher = @{}
        }

        if ($global:JobWatcher[$Name] -eq $null) {
            $global:JobWatcher[$Name] = New-Object System.Collections.ArrayList
        }

        do {
            $submitted = $false
            if ($ParallelJobCount -eq -1 -or $global:JobWatcher[$Name].Count -le $ParallelJobCount) {
                $job = Start-Job -ScriptBlock $ScriptBlock -InitializationScript $InitializationScript
                $global:JobWatcher[$Name].Add($job) | Out-Null
                $submitted = $true
                Write-Verbose "Started job $($job.Id)"
            } else {
                Pop-Jobs -Name $Name
                if ($global:JobWatcher[$Name].Count -gt $ParallelJobCount) {
                    Write-Warning "Maximum concurrent jobs running."
                    Start-Sleep -Milliseconds 1000
                }
            }
            Pop-Jobs -Name $Name
        } while ($submitted -eq $false)
    }

    END {
        if ($Wait) {
            Watch-Jobs -Name $Name
        }
    }
}

function Pop-Jobs {
    [CmdletBinding()]
    param (
            [Parameter(Mandatory=$true)]
            [string]
            $Name
          )

    $jobs = $global:JobWatcher[$Name].ToArray()
    foreach ($job in $jobs) {
        if ($job.State -ne "Running" -or $job.State -eq "Suspended") {
            Write-Verbose "Removing job $($job.Id) from the queue"
            $global:JobWatcher[$Name].Remove($job) | Out-Null
            Receive-Job $job
            Remove-Job $job
        }
    }
}

function Watch-Jobs {
    [CmdletBinding()]
    param (
            [Parameter(Mandatory=$true)]
            [string]
            $Name,

            [Parameter(Mandatory=$false)]
            [int]
            $UpdateInterval=10
          )

    $now = Get-Date
    while ($global:JobWatcher[$Name].Count -gt 0) {
        Pop-Jobs -Name $Name
        Start-Sleep -Milliseconds 250
        if (((Get-Date) - $now).Seconds -ge 10) {
            Write-Warning "$($global:JobWatcher[$Name].Count) jobs still executing"
            $now = Get-Date
        }
    }
    $global:JobWatcher.Remove($Name) | Out-Null
}
