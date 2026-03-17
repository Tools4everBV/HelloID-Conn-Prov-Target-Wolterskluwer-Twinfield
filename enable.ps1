#################################################
# HelloID-Conn-Prov-Target-Wolterskluwer-Twinfield-Enable
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
function Resolve-Wolterskluwer-TwinfieldError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        $httpErrorObj.FriendlyMessage = "$($ErrorObject.Exception.Message)"        
        Write-Output $httpErrorObj
    }
}
function Get-AuthToken {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $ClientID,

        [Parameter(Mandatory)]
        [string]
        $ClientSecret,

        [Parameter(Mandatory)]
        [string]
        $TokenUri,

        [Parameter(Mandatory)]
        [string]
        $RefreshToken
    )

    try {

        $headers = @{
            'content-type' = 'application/x-www-form-urlencoded'
            Authorization  = "Basic " + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($ClientID):$($ClientSecret)"))   
        }

        $body = @{
            grant_Type    = "refresh_token"   
            refresh_token = $RefreshToken   
        }
        $splatApitoken = @{
            Uri     = $TokenUri
            Method  = 'POST'
            Body    = $body
            Headers = $headers
        }
        $result = Invoke-RestMethod @splatApitoken
        Write-Output $result
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
function New-ReadUserRequest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $AccessToken,

        [Parameter(Mandatory)]
        [string]
        $CompanyCode,

        [Parameter(Mandatory)]
        [string]
        $UserCode
          
    )
    [xml]$xmlRequestuser = ( '<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XmlSchema-instance" xmlns:xsd="http://www.w3.org/2001/XmlSchema">
    <soap:Header>
        <Header xmlns="http://www.twinfield.com/">
            <AccessToken></AccessToken>
            <CompanyCode></CompanyCode>
        </Header>
    </soap:Header>
    <soap:Body>
        <ProcessXmlString xmlns="http://www.twinfield.com/">
            <xmlRequest><![CDATA[<read><type>user</type><code>{0}</code></read>]]></xmlRequest>
        </ProcessXmlString>
    </soap:Body>
</soap:Envelope>' -f $UserCode)

    $xmlRequestuser.Envelope.Header.Header.AccessToken = $AccessToken
    $xmlRequestuser.Envelope.Header.Header.CompanyCode = $CompanyCode 
    write-output $xmlRequestuser

}
function New-EnableUserRequest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $AccessToken,

        [Parameter(Mandatory)]
        [string]
        $CompanyCode,

        [Parameter(Mandatory)]
        [string]
        $Type       
    )
    $xmlUser = ('<![CDATA[<user >
    <code>{0}</code>
    <type>{1}</type>
    <account><disable><from></from><to></to></disable></account>
    </user>]]>' -f $actionContext.References.Account,  $Type )    

    $xmlEnableUser = [xml] ('<?xml version="1.0" encoding="utf-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XmlSchema-instance" xmlns:xsd="http://www.w3.org/2001/XmlSchema">
    <soap:Header>
        <Header xmlns="http://www.twinfield.com/">
            <AccessToken></AccessToken>
            <CompanyCode></CompanyCode>
        </Header>
    </soap:Header>
    <soap:Body>
        <ProcessXmlString xmlns="http://www.twinfield.com/">
            <xmlRequest>{0}</xmlRequest>
        </ProcessXmlString>
    </soap:Body>
</soap:Envelope>' -f $xmlUser)

    $xmlEnableUser.Envelope.Header.Header.AccessToken = $AccessToken
    $xmlEnableUser.Envelope.Header.Header.CompanyCode = $CompanyCode      
    write-output $xmlEnableUser
}
function ConvertTo-HelloIDAccountObject {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $AccountObject
    )
    process {
        # Making sure only fieldMapping fields are imported
        $helloidAccountObject = [PSCustomObject]@{} 
        foreach ($property in $outputContext.Data.PSObject.Properties) {            
            switch ($property.Name) {
                default {
                    if ($property.Name -In $AccountObject.PSObject.Properties.Name) {
                        if ($AccountObject.$($property.Name) -is [System.Xml.XmlElement]) {
                            $helloidAccountObject | Add-Member -MemberType NoteProperty -Name $property.Name -Value $AccountObject.$($property.Name).InnerText
                        }
                        else {
                            $helloidAccountObject | Add-Member -MemberType NoteProperty -Name $property.Name -Value $AccountObject.$($property.Name)
                        }
                    }
                } 
            }
        }
        Write-Output $helloidAccountObject        
    }
}
#region functions

#endregion

try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    $splatApiToken = @{
        ClientId     = $ActionContext.Configuration.ClientId
        ClientSecret = $ActionContext.Configuration.ClientSecret
        TokenUri     = $ActionContext.Configuration.TokenUrl
        RefreshToken = $ActionContext.Configuration.RefreshToken             
    }
    $apiToken = Get-AuthToken @splatApiToken
    $splatClusterInfo = @{
        Uri         = "https://login.twinfield.com/auth/authentication/connect/accesstokenvalidation?token=$($apiToken.access_token)"
        Method      = 'GET'
        ContentType = 'application/x-www-form-urlencoded'    
    }
    $ClusterInfo = Invoke-RestMethod @splatClusterInfo
    $ApiUrl = $ClusterInfo.'twf.clusterUrl'  
   

    $splatreadUserRequest = @{
        AccessToken = $apiToken.access_token
        CompanyCode = $actionContext.Configuration.Companycode
        UserCode    = $actionContext.References.Account
    }
    $xmlReaduser = New-ReadUserRequest @splatreadUserRequest
    $headers = @{         
        'content-type' = 'text/xml; charset=utf-8'                
        'Host'         = $ApiUrl.Replace("https://", "")                               
    }
    $splatReadUserParams = @{
        Uri     = $ApiUrl + '/webservices/processxml.asmx'
        Method  = 'POST'
        Body    = $xmlReaduser.InnerXml
        Headers = $headers                        
    }
    if (-not  [string]::IsNullOrEmpty($actionContext.Configuration.ProxyAddress)) {
        $splatReadUserParams['Proxy'] = $actionContext.Configuration.ProxyAddress
    }
    $readResponse = Invoke-RestMethod @splatReadUserParams 
    $ReadUserInfo = [xml] $readResponse.Envelope.Body.ProcessXmlStringResponse.ProcessXmlStringResult
    $correlatedAccount = $ReadUserInfo.user        
    if ($correlatedAccount.result -eq 1) {

        if ($correlatedAccount.status -eq 'deleted') {                       
            $action = "deleted"
        }
        else {
            $action = 'EnableAccount'
        }   
    }
    elseif ($correlatedAccount.result -eq 0) {

        if ($readuserinfo.user.status -eq 'default') {
            $action = 'NotFound'
        }
        else {
            $action = 'Unexpected'
        }      
    }
    else {
        $action = 'Unexpected'
    } 

    # Process
    switch ($action) {
        'EnableAccount' {
            $headers = @{         
                'content-type' = 'text/xml; charset=utf-8'                
                'Host'         = $ApiUrl.Replace("https://", "")                               
            }
            $splatNewEnableUserRequest = @{
                AccessToken = $apiToken.access_token
                CompanyCode = $actionContext.Configuration.Companycode
                Type        = $correlatedAccount.type.'#text'
            }
            $xmlEnableUser = New-EnableUserRequest @splatNewEnableUserRequest

            $splateEnableUserParams = @{
                Uri     = $ApiUrl + '/webservices/processxml.asmx'
                Method  = 'POST'
                Body    = $xmlEnableUser.InnerXml
                Headers = $headers                        
            }
            if (-not  [string]::IsNullOrEmpty($actionContext.Configuration.ProxyAddress)) {
                $splateEnableUserParams['Proxy'] = $actionContext.Configuration.ProxyAddress
            }

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Enabling Wolterskluwer-Twinfield account with accountReference: [$($actionContext.References.Account)]"
                $enableResponse = Invoke-RestMethod @splateEnableUserParams
                $enabledUserInfo = [xml] $enableResponse.Envelope.Body.ProcessXmlStringResponse.ProcessXmlStringResult
                if ($enabledUserInfo.user.result -ne '1') {

                    $ErrorMessage = "Enabling user $($ActionContext.Data.Code) [$($enabledUserInfo.user.msg)]"
                    foreach ($property in $enabledUserInfo.user.PSObject.Properties) {                      
                        $node = $enabledUserInfo.user."$($property.Name)"                      
                        if (($node -is [System.Xml.XmlElement]) -and ($node.msgtype -eq 'error')) {                                                                        
                            $ErrorMessage += "[$($property.Name) : $($node.msg)]" 
                        }   
                    }
                    $ErrorMessage += "]"
                    $exception = [System.Net.WebException]::new("$($ErrorMessage)")
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'WolterskluwerTwinfieldEnableError', "InvalidResult", $ActionContext.Data)
                    $errorRecord.ErrorDetails = $enabledUserInfo.user.OuterXml                    
                    throw $errorRecord 
                }
            
                $enabledAccount = $enabledUserInfo.user
                $outputContext.Data = ConvertTo-HelloIDAccountObject -AccountObject $enabledAccount

            }
            else {
                Write-Information "[DryRun] Enable Wolterskluwer-Twinfield account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            # Make sure to filter out arrays from $outputContext.Data (If this is not mapped to type Array in the fieldmapping). This is not supported by HelloID.
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Enable Wolterskluwer-Twinfield account with accountReference [$($actionContext.References.Account)] was successful. Action initiated by: [$($actionContext.Origin)]"
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "Wolterskluwer-Twinfield account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted. Action initiated by: [$($actionContext.Origin)]"
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Wolterskluwer-Twinfield account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted. Action initiated by: [$($actionContext.Origin)]"
                    IsError = $true
                })
            break
        }
        'deleted' {
            Write-Information "Wolterskluwer-Twinfield account: [$($actionContext.References.Account)] exists, but has the deleted status. 
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Wolterskluwer-Twinfield account: [$($actionContext.References.Account)] exists, but has the deleted status."
                    IsError = $true
                })
            
            break
        }
        
        'Unexpected' {
            $ErrorMessage = "Unexpected result while searching for user [$($actionContext.References.Account)]. Message: [$($correlatedAccount.msg)]"        
            $exception = [System.Net.WebException]::new("$($ErrorMessage)")
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'WolterskluwerTwinfieldEnableError', "InvalidResult", $ActionContext.Data)
            $errorRecord.ErrorDetails = $ReadUserInfo.OuterXml      
            throw $errorRecord
        
        }
    }
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Wolterskluwer-TwinfieldError -ErrorObject $ex
        $auditMessage = "Could not enable Wolterskluwer-Twinfield account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.FriendlyMessage) Details: [$($errorObj.ErrorDetails)]"
    } else {
        $auditMessage = "Could not enable Wolterskluwer-Twinfield account. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}