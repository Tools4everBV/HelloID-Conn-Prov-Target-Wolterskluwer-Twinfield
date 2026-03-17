##################################################
# HelloID-Conn-Prov-Target-Wolterskluwer-Twinfield-Disable
# PowerShell V2
##################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
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
function New-DisableUserRequest {
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
    $xmlUser = ('<![CDATA[<user>
    <code>{0}</code>
    <type>{1}</type>
    <account><disable><from>{2}</from><to></to></disable></account>
    </user>]]>' -f $actionContext.References.Account, $Type , (Get-Date).ToString("yyyyMMddHHmmss"))    

    $xmlDisableUser = [xml] ('<?xml version="1.0" encoding="utf-8"?>
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

    $xmlDisableUser.Envelope.Header.Header.AccessToken = $AccessToken
    $xmlDisableUser.Envelope.Header.Header.CompanyCode = $CompanyCode      
    write-output $xmlDisableUser
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

#endregion

try {
    # Verify if [AccountReference] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    Write-Information 'Verifying if a Wolterskluwer-Twinfield account exists'    

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
            $action = 'DisableAccount'
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
        'DisableAccount' {
 $headers = @{         
                'content-type' = 'text/xml; charset=utf-8'                
                'Host'         = $ApiUrl.Replace("https://", "")                               
            }
            $splatNewDisableUserRequest = @{
                AccessToken = $apiToken.access_token
                CompanyCode = $actionContext.Configuration.Companycode
                Type        = $correlatedAccount.type.'#text'
            }
            $xmlDisableUser = New-DisableUserRequest @splatNewDisableUserRequest

            $splatDisableUserParams = @{
                Uri     = $ApiUrl + '/webservices/processxml.asmx'
                Method  = 'POST'
                Body    = $xmlDisableUser.InnerXml
                Headers = $headers                        
            }
            if (-not  [string]::IsNullOrEmpty($actionContext.Configuration.ProxyAddress)) {
                $splatDisableUserParams['Proxy'] = $actionContext.Configuration.ProxyAddress
            }

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Disabling Wolterskluwer-Twinfield account with accountReference: [$($actionContext.References.Account)]"
                $disableResponse = Invoke-RestMethod @splatDisableUserParams
                $disabledUserInfo = [xml] $disableResponse.Envelope.Body.ProcessXmlStringResponse.ProcessXmlStringResult
                if ($disabledUserInfo.user.result -ne '1') {

                    $ErrorMessage = "Disabling user $($ActionContext.References.Account) [$($disabledUserInfo.user.msg)]"
                    foreach ($property in $disabledUserInfo.user.PSObject.Properties) {                      
                        $node = $disabledUserInfo.user."$($property.Name)"                      
                        if (($node -is [System.Xml.XmlElement]) -and ($node.msgtype -eq 'error')) {                                                                        
                            $ErrorMessage += "[$($property.Name) : $($node.msg)]" 
                        }   
                    }
                    $ErrorMessage += "]"
                    $exception = [System.Net.WebException]::new("$($ErrorMessage)")
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'WolterskluwerTwinfieldDisableError', "InvalidResult", $ActionContext.Data)
                    $errorRecord.ErrorDetails = $disabledUserInfo.user.OuterXml                    
                    throw $errorRecord 
                }
            
                $disabledAccount = $disabledUserInfo.user
                $outputContext.Data = ConvertTo-HelloIDAccountObject -AccountObject $disabledAccount

            }
            else {
                Write-Information "[DryRun] Disable Wolterskluwer-Twinfield account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            # Make sure to filter out arrays from $outputContext.Data (If this is not mapped to type Array in the fieldmapping). This is not supported by HelloID.
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Disable Wolterskluwer-Twinfield account with accountReference [$($actionContext.References.Account)] was successful. Action initiated by: [$($actionContext.Origin)]"
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "Wolterskluwer-Twinfield account: [$($actionContext.References.Account)] could not be found, indicating that it may have been  deleted. Action initiated by: [$($actionContext.Origin)]"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Wolterskluwer-Twinfield account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted. Action initiated by: [$($actionContext.Origin)]"
                    IsError = $false
                })
            break
        }
        'deleted' {
            Write-Information "Wolterskluwer-Twinfield account: [$($actionContext.References.Account)] exists, but has already the deleted status: Skipping the disable action. Action initiated by: [$($actionContext.Origin)]"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Wolterskluwer-Twinfield account: [$($actionContext.References.Account)]exists, but has already the deleted status: Skipping the disable action. Action initiated by: [$($actionContext.Origin)]"
                    IsError = $false
                })
            break
        }
        'Unexpected' {
            $ErrorMessage = "Unexpected result while searching for user [$($actionContext.References.Account)]. Action initiated by: [$($actionContext.Origin)]. Message: [$($correlatedAccount.msg)]"        
            $exception = [System.Net.WebException]::new("$($ErrorMessage)")
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'WolterskluwerTwinfieldDisableError', "InvalidResult", $ActionContext.Data)
            $errorRecord.ErrorDetails = $ReadUserInfo.OuterXml      
            throw $errorRecord       
        }
    }
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Wolterskluwer-TwinfieldError -ErrorObject $ex
        $auditMessage = "Could not disable Wolterskluwer-Twinfield account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.FriendlyMessage) Details: [$($errorObj.ErrorDetails)])"
    }
    else {
        $auditMessage = "Could not disable Wolterskluwer-Twinfield account. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}