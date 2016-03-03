﻿## --------------------------------------------------------------------------------------
## Configuration
## --------------------------------------------------------------------------------------

$isEnabled = $OctopusParameters["Octopus.Action.IISWebSite.CreateOrUpdateWebSite"]
if (!$isEnabled -or ![Bool]::Parse($isEnabled))
{
   exit 0
}

try {
    Add-PSSnapin WebAdministration
} catch {
    try {
        Import-Module WebAdministration
    } catch {
		Write-Warning "We failed to load the WebAdministration module. This usually resolved by doing one of the following:"
		Write-Warning "1. Install .NET Framework 3.5.1"
		Write-Warning "2. Upgrade to PowerShell 3.0 (or greater)"
        throw ($error | Select-Object -First 1)
    }
}

$WebSiteName = $OctopusParameters["Octopus.Action.IISWebSite.WebSiteName"]
$ApplicationPoolName = $OctopusParameters["Octopus.Action.IISWebSite.ApplicationPoolName"]
$bindingString = $OctopusParameters["Octopus.Action.IISWebSite.Bindings"]
$appPoolFrameworkVersion = $OctopusParameters["Octopus.Action.IISWebSite.ApplicationPoolFrameworkVersion"]
$webRoot = $OctopusParameters["Octopus.Action.IISWebSite.WebRoot"]
$enableWindows = $OctopusParameters["Octopus.Action.IISWebSite.EnableWindowsAuthentication"]
$enableBasic = $OctopusParameters["Octopus.Action.IISWebSite.EnableBasicAuthentication"]
$enableAnonymous = $OctopusParameters["Octopus.Action.IISWebSite.EnableAnonymousAuthentication"]
$applicationPoolIdentityType = $OctopusParameters["Octopus.Action.IISWebSite.ApplicationPoolIdentityType"]
$applicationPoolUsername = $OctopusParameters["Octopus.Action.IISWebSite.ApplicationPoolUsername"]
$applicationPoolPassword = $OctopusParameters["Octopus.Action.IISWebSite.ApplicationPoolPassword"]

if (! $webRoot) {
	$webRoot = "."
}

$maxFailures = $OctopusParameters["Octopus.Action.IISWebSite.MaxRetryFailures"]
if ($maxFailures -Match "^\d+$") {
    $maxFailures = [int]$maxFailures
} else {
    $maxFailures = 5
}

$sleepBetweenFailures = $OctopusParameters["Octopus.Action.IISWebSite.SleepBetweenRetryFailuresInSeconds"]
if ($sleepBetweenFailures -Match "^\d+$") {
    $sleepBetweenFailures = [int]$sleepBetweenFailures
} else {
    $sleepBetweenFailures = Get-Random -minimum 1 -maximum 4
}

if ($sleepBetweenFailures -gt 60) {
    Write-Host "Invalid Sleep time between failures.  Setting to max of 60 seconds"
    $sleepBetweenFailures = 60
}

# Helper to run a block with a retry if things go wrong
function Execute-WithRetry([ScriptBlock] $command) {
	$attemptCount = 0
	$operationIncomplete = $true

	while ($operationIncomplete -and $attemptCount -lt $maxFailures) {
		$attemptCount = ($attemptCount + 1)

		if ($attemptCount -ge 2) {
			Write-Host "Waiting for $sleepBetweenFailures seconds before retrying..."
			Start-Sleep -s $sleepBetweenFailures
			Write-Host "Retrying..."
		}

		try {
			& $command

			$operationIncomplete = $false
		} catch [System.Exception] {
			if ($attemptCount -lt ($maxFailures)) {
				Write-Host ("Attempt $attemptCount of $maxFailures failed: " + $_.Exception.Message)
			} else {
				throw
			}
		}
	}
}

$webRoot = (resolve-path $webRoot).ProviderPath

#Assess SNI support (IIS 8 or greater)
$iis = get-itemproperty HKLM:\SOFTWARE\Microsoft\InetStp\  | select setupstring 
$iisVersion = ($iis.SetupString.Substring(4)) -as [double]
$supportsSNI = $iisVersion -ge 8


$wsbindings = new-object System.Collections.ArrayList

function Write-IISBinding($message, $bindingObject) {
	if(-not ($bindingObject -is [PSObject])) {
		Write-Host "$message @{$([String]::Join("; ", ($bindingObject.Keys | % { return "$($_)=$($bindingObject[$_])" })))}"
	} else {
		Write-Host "$message $bindingObject"
	}
}

if($bindingString.StartsWith("[{")) {
	
	if(Get-Command ConvertFrom-Json -errorAction SilentlyContinue){
		$bindingArray = (ConvertFrom-Json $bindingString)
	} else {
		add-type -assembly system.web.extensions
		$serializer=new-object system.web.script.serialization.javascriptSerializer
		$bindingArray = ($serializer.DeserializeObject($bindingString))
	}

	ForEach($binding in $bindingArray){
		$sslFlagPart = @{$true=1;$false=0}[[Bool]::Parse($binding.requireSni)]  
		$bindingIpAddress =  @{$true="*";$false=$binding.ipAddress}[[string]::IsNullOrEmpty($binding.ipAddress)]
		$bindingInformation = $bindingIpAddress+":"+$binding.port+":"+$binding.host
		
		if([Bool]::Parse($binding.enabled)) {
			Write-IISBinding "Found binding: " $binding
			if ([Bool]::Parse($supportsSNI)) {
				$wsbindings.Add(@{ 
					protocol=$binding.protocol;
					ipAddress=$bindingIpAddress;
					port=$binding.port;
					host=$binding.host;
					bindingInformation=$bindingInformation;
					thumbprint=$binding.thumbprint.Trim();
					sslFlags=$sslFlagPart }) | Out-Null
			} else {
				$wsbindings.Add(@{ 
					protocol=$binding.protocol;
					ipAddress=$bindingIpAddress;
					port=$binding.port;
					host=$binding.host;
					bindingInformation=$bindingInformation;
					thumbprint=$binding.thumbprint.Trim() }) | Out-Null
			}
		} else {
			Write-IISBinding "Ignore binding: " $binding
		}
	}

} else {	
	# Each binding string consists of a protocol/binding information (IP, port, hostname)/SSL thumbprint/enabled/sslFlags
	# Binding strings are pipe (|) separated to allow multiple to be specified
	$bindingString.Split("|") | foreach-object {
		$bindingParts = $_.split("/")
		$skip = $false
		if ($bindingParts.Length -ge 4) {
			if (![String]::IsNullOrEmpty($bindingParts[3]) -and [Bool]::Parse($bindingParts[3]) -eq $false) {
				$skip = $true
			}
		}
		
		if ($skip -eq $false) {
			$addressParts = $bindingParts[1].split(':')
			$sslFlagPart = 0
			if($bindingParts.Length -ge 5){
				if (![String]::IsNullOrEmpty($bindingParts[4]) -and [Bool]::Parse($bindingParts[4]) -eq $true){
					$sslFlagPart = 1
				}
			}
			if ($supportsSNI -eq $true ){
				$wsbindings.Add(@{ 
					protocol=$bindingParts[0];
					bindingInformation=$bindingParts[1];
					thumbprint=$bindingParts[2].Trim();
					ipAddress=$addressParts[0];
					port= $addressParts[1];
					host=$addressParts[2];
					sslFlags=$sslFlagPart }) | Out-Null
				}
			else{
				$wsbindings.Add(@{ 
					protocol=$bindingParts[0];
					bindingInformation=$bindingParts[1];
					ipAddress=$addressParts[0];
					port= $addressParts[1];
					host=$addressParts[2];
					thumbprint=$bindingParts[2].Trim() }) | Out-Null
			}
		} else {
			Write-Host "Ignore binding: $_"
		}
	}
}


# For any HTTPS bindings, ensure the certificate is configured for the IP/port combination
$wsbindings | where-object { $_.protocol -eq "https" } | foreach-object {
    $sslCertificateThumbprint = $_.thumbprint.Trim()
    Write-Host "Finding SSL certificate with thumbprint $sslCertificateThumbprint"
    
    $certificate = Get-ChildItem Cert:\LocalMachine -Recurse | Where-Object { $_.Thumbprint -eq $sslCertificateThumbprint -and $_.HasPrivateKey -eq $true } | Select-Object -first 1
    if (! $certificate) 
    {
        throw "Could not find certificate under Cert:\LocalMachine with thumbprint $sslCertificateThumbprint. Make sure that the certificate is installed to the Local Machine context and that the private key is available."
    }

    $certPathParts = $certificate.PSParentPath.Split('\')
    $certStoreName = $certPathParts[$certPathParts.Length-1]

    Write-Host ("Found certificate: " + $certificate.Subject + " in: " + $certStoreName)

    $ipAddress = $_.ipAddress;
    if ((! $ipAddress) -or ($ipAddress -eq '*')) {
        $ipAddress = "0.0.0.0"
    }
    $port = $_.port
	$hostname = $_.host
	Execute-WithRetry { 
	
		#If we are supporting SNI then we need to bind cert to hostname instead of ip
		if($_.sslFlags -eq 1){
		
			$existing = & netsh http show sslcert hostnameport="$($hostname):$port"
			if ($LastExitCode -eq 0) {
				$hasThumb = ($existing | Where-Object { $_.IndexOf($certificate.Thumbprint, [System.StringComparison]::OrdinalIgnoreCase) -ne -1 })
				if ($hasThumb -eq $null) {
					Write-Host "A different binding exists for the Hostname/port combination, replacing..."
					
					& netsh http delete sslcert hostnameport="$($hostname):$port"
					if ($LastExitCode -ne 0 ){
						throw
					}

					$appid = [System.Guid]::NewGuid().ToString("b")
					& netsh http add sslcert hostnameport="$($hostname):$port" certhash="$($certificate.Thumbprint)" appid="$appid" certstorename="$certStoreName"
					if ($LastExitCode -ne 0 ){
						throw
					}

				} else {
					Write-Host "The required certificate binding is already in place"
				}
			} else {
				$appid = [System.Guid]::NewGuid().ToString("b")
				& netsh http add sslcert hostnameport="$($hostname):$port" certhash="$($certificate.Thumbprint)" appid="$appid" certstorename="$certStoreName"
				if ($LastExitCode -ne 0 ){
					throw
				}
			}	
		} else {
			$existing = & netsh http show sslcert ipport="$($ipAddress):$port"
			if ($LastExitCode -eq 0) {
				$hasThumb = ($existing | Where-Object { $_.IndexOf($certificate.Thumbprint, [System.StringComparison]::OrdinalIgnoreCase) -ne -1 })
				if ($hasThumb -eq $null) {
					Write-Host "A different binding exists for the IP/port combination, replacing..."
					
					& netsh http delete sslcert ipport="$($ipAddress):$port"
					if ($LastExitCode -ne 0 ){
						throw
					}

					$appid = [System.Guid]::NewGuid().ToString("b")
					& netsh http add sslcert ipport="$($ipAddress):$port" certhash="$($certificate.Thumbprint)" appid="$appid" certstorename="$certStoreName"
					if ($LastExitCode -ne 0 ){
						throw
					}
					
				} else {
					Write-Host "The required certificate binding is already in place"
				}
			} else {
				Write-Host "Adding a new SSL certificate binding..."
				$appid = [System.Guid]::NewGuid().ToString("b")
				& netsh http add sslcert ipport="$($ipAddress):$port" certhash="$($certificate.Thumbprint)" appid="$appid" certstorename="$certStoreName"
				if ($LastExitCode -ne 0 ){
					throw
				}
			}	
		}	
	}
}

## --------------------------------------------------------------------------------------
## Run
## --------------------------------------------------------------------------------------

pushd IIS:\

$appPoolPath = ("IIS:\AppPools\" + $ApplicationPoolName)
$sitePath = ("IIS:\Sites\" + $webSiteName)

# Set App Pool
Execute-WithRetry { 
	$pool = Get-Item $appPoolPath -ErrorAction SilentlyContinue
	if (!$pool) { 
		Write-Host "Application pool `"$ApplicationPoolName`" does not exist, creating..." 
		new-item $appPoolPath -confirm:$false
		$pool = Get-Item $appPoolPath
	} else {
		Write-Host "Application pool `"$ApplicationPoolName`" already exists"
	}
}

# Set App Pool Identity
Execute-WithRetry { 
	Write-Host "Set application pool identity: $applicationPoolIdentityType"
	if ($applicationPoolIdentityType -eq "SpecificUser") {
		Set-ItemProperty $appPoolPath -name processModel -value @{identitytype="SpecificUser"; username="$applicationPoolUsername"; password="$applicationPoolPassword"}
	} else {
		Set-ItemProperty $appPoolPath -name processModel -value @{identitytype="$applicationPoolIdentityType"}
	}
}

# Set .NET Framework
Execute-WithRetry { 
	Write-Host "Set .NET framework version: $appPoolFrameworkVersion" 
	Set-ItemProperty $appPoolPath managedRuntimeVersion $appPoolFrameworkVersion
}

# Create Website
Execute-WithRetry { 
	$site = Get-Item $sitePath -ErrorAction SilentlyContinue
	if (!$site) { 
		Write-Host "Site `"$WebSiteName`" does not exist, creating..." 
		$id = (dir iis:\sites | foreach {$_.id} | sort -Descending | select -first 1) + 1
		new-item $sitePath -bindings @{protocol="http";bindingInformation=":81:od-temp.example.com"} -id $id -physicalPath $webRoot -confirm:$false
	} else {
		Write-Host "Site `"$WebSiteName`" already exists"
	}
}

# Assign Website to App Pool
Execute-WithRetry { 
	$pool = Get-ItemProperty $sitePath -name applicationPool
	if ($ApplicationPoolName -ne $pool) {
		Write-Host "Assigning website `"$sitePath`" to application pool `"$ApplicationPoolName`"..."
		Set-ItemProperty $sitePath -name applicationPool -value $ApplicationPoolName
	} else {
		Write-Host "Application pool `"$ApplicationPoolName`" already assigned to website `"$sitePath`""
	}
}

# Set Path
Execute-WithRetry { 
	Write-Host ("Home directory: " + $webRoot)
	Set-ItemProperty $sitePath -name physicalPath -value "$webRoot"
}

function Bindings-AreEqual($bindingA, $bindingB) {
    return ($bindingA.protocol -eq $bindingB.protocol) -and ($bindingA.bindingInformation -eq $bindingB.bindinginformation) -and ($bindingA.sslFlags -eq $bindingB.sslFlags)
}

# Returns $true if existing IIS bindings are as specified in configuration, otherwise $false
function Bindings-AreCorrect($existingBindings, $configuredBindings) {
	# Are there existing assigned bindings that are not configured
	for ($i = 0; $i -lt $existingBindings.Collection.Count; $i = $i+1) {
		$binding = $existingBindings.Collection[$i]

		$matching = $configuredBindings | Where-Object {Bindings-AreEqual $binding $_ }
		
		if ($matching -eq $null) {
			Write-Host "Found existing non-configured binding: $($binding.protocol) $($binding.bindingInformation)"
			return $false
		}
	}

	# Are there configured bindings which are not assigned
	for ($i = 0; $i -lt $configuredBindings.Count; $i = $i+1) {
	    $wsbinding = $configuredBindings[$i]

	    $matching = $existingBindings.Collection | Where-Object {Bindings-AreEqual $wsbinding $_ }

	    if ($matching -eq $null) {
		    Write-Host "Found configured binding which is not assigned: $($wsbinding.protocol) $($wsbinding.bindingInformation)"
		    return $false
	    }
	}
	Write-Host "Looks OK"


    return $true
}

# Set Bindings
Execute-WithRetry { 
	Write-Host "Comparing existing IIS bindings with configured bindings..."
	$existingBindings = Get-ItemProperty $sitePath -name bindings

	if (-not (Bindings-AreCorrect $existingBindings $wsbindings)) {
        Write-Host "Existing IIS bindings do not match configured bindings."
		Write-Host "Clearing IIS bindings"
        Clear-ItemProperty $sitePath -name bindings

       	for ($i = 0; $i -lt $wsbindings.Count; $i = $i+1) {
		    Write-Host ("Assigning binding: " + ($wsbindings[$i].protocol + " " + $wsbindings[$i].bindingInformation))
		    New-ItemProperty $sitePath -name bindings -value ($wsbindings[$i])
	    }
    } else {
		Write-Host "Bindings are as configured. No changes required."
	}
}

$appCmdPath = $env:SystemRoot + "\system32\inetsrv\appcmd.exe"
if ((Test-Path $appCmdPath) -eq $false) {
	throw "Could not find appCmd.exe at $appCmdPath"
}

try {
	Execute-WithRetry { 
		Write-Host "Anonymous authentication enabled: $enableAnonymous"
		& $appCmdPath set config "$WebSiteName" -section:"system.webServer/security/authentication/anonymousAuthentication" /enabled:"$enableAnonymous" /commit:apphost
		if ($LastExitCode -ne 0 ){
			throw
		}		
	}

	Execute-WithRetry { 
		Write-Host "Basic authentication enabled: $enableBasic"
		& $appCmdPath set config "$WebSiteName" -section:"system.webServer/security/authentication/basicAuthentication" /enabled:"$enableBasic" /commit:apphost
		if ($LastExitCode -ne 0 ){
			throw
		}		
	}

	Execute-WithRetry { 
		Write-Host "Windows authentication enabled: $enableWindows"
		& $appCmdPath set config "$WebSiteName" -section:"system.webServer/security/authentication/windowsAuthentication" /enabled:"$enableWindows" /commit:apphost
		if ($LastExitCode -ne 0 ){
			throw
		}		
		
	}
} catch [System.Exception] {
	Write-Host "Authentication options could not be set. This can happen when there is a problem with your application's web.config. For example, you might be using a section that requires an extension that is not installed on this web server (such as URL Rewrtiting). It can also happen when you have selected an authentication option and the appropriate IIS module is not installed (for example, for Windows authentication, you need to enable the Windows Authentication module in IIS/Windows first)"
	throw
}

# It can take a while for the App Pool to come to life (#490)
Start-Sleep -s 1

# Start App Pool
Execute-WithRetry { 
	$state = Get-WebAppPoolState $ApplicationPoolName
	if ($state.Value -eq "Stopped") {
		Write-Host "Application pool is stopped. Attempting to start..."
		Start-WebAppPool $ApplicationPoolName
	}
}

# Start Website
Execute-WithRetry { 
	$state = Get-WebsiteState $WebSiteName
	if ($state.Value -eq "Stopped") {
		Write-Host "Web site is stopped. Attempting to start..."
		Start-Website $WebSiteName
	}
}

popd

Write-Host "IIS configuration complete"
