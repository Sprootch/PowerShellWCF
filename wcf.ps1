<#  
.SYNOPSIS  
	Functions to call WCF Services With PowerShell.
.NOTES
	Version 1.1 10.02.2012
	Requires Powershell v2 and .NET 3.5

	Original version by Christian Glessner
	Blog: http://www.iLoveSharePoint.com
	Twitter: http://twitter.com/cglessner
	Codeplex: http://codeplex.com/iLoveSharePoint
	
	PowerShell v2.0 modification by Justin Dearing
	Blog: http://justaprogrammer.net
	Twitter: http://twitter.com/zippy1981 
.LINK  
	Blog describing original version: http://www.ilovesharepoint.com/2008/12/call-wcf-services-with-powershell.html
	Posted to PoshCode.org http://poshcode.org/?lang=&q=PS2WCF
#>

# load WCF assemblies
Add-Type -AssemblyName "System.ServiceModel"
Add-Type -AssemblyName "System.Runtime.Serialization"

<#  
.SYNOPSIS  
	Get metadata of a service

.DESCRIPTION  
	Parses a wsdl or mex and generates a WsdlImporter object from it.
.EXAMPLE
	Get-WsdlImporter 'http://localhost.fiddler:14232/EchoService.svc/mex'
.EXAMPLE
	Get-WsdlImporter 'http://localhost.fiddler:14232/EchoService.svc' -HttpGet
.EXAMPLE
	Get-WsdlImporter 'http://localhost.fiddler:14232/EchoService.svc?wsdl' -HttpGet 

#>
function global:Get-WsdlImporter([CmdletBinding()][Parameter(Mandatory=$true, ValueFromPipeline=$true)][string]$wsdlUrl, [switch]$httpGet)
{
	if($httpGet -eq $true)
	{
		$local:mode = [System.ServiceModel.Description.MetadataExchangeClientMode]::HttpGet
	}
	else
	{
		$local:mode = [System.ServiceModel.Description.MetadataExchangeClientMode]::MetadataExchange
	}
	
	$mexClient = New-Object System.ServiceModel.Description.MetadataExchangeClient((New-Object System.Uri($wsdlUrl)),$mode)
	$mexClient.MaximumResolvedReferences = [System.Int32]::MaxValue
	$metadataSet = $mexClient.GetMetadata()
	$wsdlImporter = New-Object System.ServiceModel.Description.WsdlImporter($metadataSet)
	
	return $wsdlImporter	
}

<#  
.SYNOPSIS  
    Generate wcf proxy types

.DESCRIPTION  
    Examines a web services meta data (wsdl or mex) and generates the types for the client proxy, 
	as well as request and response contracts.
.EXAMPLE  
    $proxyType = Get-WcfProxyType $wsdlImporter
	$endpoints = $wsdlImporter.ImportAllEndpoints();
	$proxy = New-Object $proxyType($endpoints[0].Binding, $endpoints[0].Address);
#>
function global:Get-WcfProxyType(
	[CmdletBinding()]
	[Parameter(ParameterSetName='WsdlImporter', Position=0, Mandatory=$true, ValueFromPipeline=$true)][ServiceModel.Description.WsdlImporter] $wsdlImporter,
	[Parameter(ParameterSetName='WsdlUrl', Position=0, Mandatory=$true, ValueFromPipeline=$true)][string] $wsdlUrl, 
	[string] $proxyPath
) {
	switch ($PsCmdlet.ParameterSetName)
	{
		"WsdlUrl" {
			$wsdlImporter = Get-WsdlImporter -wsdlUrl $wsdlUrl
			trap [Exception]
			{
				$script:wsdlImporter = Get-WsdlImporter -wsdlUrl $wsdlUrl -httpGet $true
				continue
			}
			break
		}
		"WsdlImporter" { break }
	}
	
	$generator = new-object System.ServiceModel.Description.ServiceContractGenerator
	
	foreach($contractDescription in $wsdlImporter.ImportAllContracts())
	{
		[void]$generator.GenerateServiceContractType($contractDescription)
	}
	
	$parameters = New-Object System.CodeDom.Compiler.CompilerParameters
	if($proxyPath -eq $null)
	{
		$parameters.GenerateInMemory = $true
	}
	else
	{
		$parameters.OutputAssembly = $proxyPath
	}
	
	$providerOptions = New-Object "Collections.Generic.Dictionary[String,String]"
	[void]$providerOptions.Add("CompilerVersion","v3.5")
	
	$compiler = New-Object Microsoft.CSharp.CSharpCodeProvider($providerOptions)
	$result = $compiler.CompileAssemblyFromDom($parameters, $generator.TargetCompileUnit);
	
	if($result.Errors.Count -gt 0)
	{
		throw "Proxy generation failed"       
	}
	
	return $result.CompiledAssembly.GetTypes() | Where-Object {$_.BaseType.IsGenericType -and $_.BaseType.GetGenericTypeDefinition().FullName -eq "System.ServiceModel.ClientBase``1" }
}

<#  
.SYNOPSIS  
    Generate wcf proxy

.DESCRIPTION  
    Generate wcf proxy in a manner similar to a Get-WebServiceProxy
.EXAMPLE
    $proxy = Get-WcfProxy 'http://localhost.fiddler:14232/EchoService.svc/mex'
	$proxy.Echo("Justin Dearing");
#>
function global:Get-WcfProxy(
	[CmdletBinding()]
	[Parameter(ParameterSetName='WsdlImporter', Position=0, Mandatory=$true, ValueFromPipeline=$true)][ServiceModel.Description.WsdlImporter] $wsdlImporter,
	[Parameter(ParameterSetName='WsdlUrl', Position=0, Mandatory=$true, ValueFromPipeline=$true)][string] $wsdlUrl, 
	[string]
	[string] $proxyPath
) {
	switch ($PsCmdlet.ParameterSetName)
	{
		"WsdlUrl" {
			$wsdlImporter = Get-WsdlImporter -wsdlUrl $wsdlUrl
			trap [Exception]
			{
				$script:wsdlImporter = Get-WsdlImporter -wsdlUrl $wsdlUrl -httpGet $true
				continue
			}
			break
		}
	}
  $proxyType = Get-WcfProxyType $wsdlImporter

  $endpoints = $wsdlImporter.ImportAllEndpoints();
  return New-Object $proxyType($endpoints[0].Binding, $endpoints[0].Address);
}
