#################################################
# HelloID-Conn-Prov-Target-Wolterskluwer-Twinfield-Import
# PowerShell V2
#################################################

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
        $httpErrorObj.FriendlyMessage = "Error: [$($ErrorObject.Exception.Message)] details: [$($httpErrorObj.ErrorDetails)]"        
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
function New-FindUserRequest {
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
        $SearchPattern,  
        
        [Parameter(Mandatory = $false)]
        [int]        $FirstRow = 1,
    
        [Parameter(Mandatory = $false)]
        [int]
        $MaxRows = 100
    )
    $xmlFinduser = [xml] ('<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XmlSchema-instance" xmlns:xsd="http://www.w3.org/2001/XmlSchema">
    <soap:Header>
        <Header xmlns="http://www.twinfield.com/">
            <AccessToken></AccessToken>
            <CompanyCode></CompanyCode> 
        </Header>
    </soap:Header>
    <soap:Body>
         <Search xmlns="http://www.twinfield.com/">
            <type>USR</type>
            <pattern></pattern>
            <field>1</field>
            <firstRow></firstRow>
            <maxRows></maxRows>
            <options>
                <ArrayOfString>
                    <string>company</string>
                    <string>{0}</string>                   
                </ArrayOfString>
            </options>
        </Search>
    </soap:Body>
</soap:Envelope>'  -f $CompanyCode ) 

    $xmlFinduser.Envelope.Header.Header.AccessToken = $AccessToken
    $xmlFinduser.Envelope.Header.Header.CompanyCode = $CompanyCode  #Note code both in header and options, as some parameters are only accepted in options.
    $xmlFinduser.Envelope.Body.Search.pattern = $SearchPattern   
    $xmlFinduser.Envelope.Body.Search.firstRow = "$($FirstRow)"
    $xmlFinduser.Envelope.Body.Search.maxRows = "$($MaxRows)"
    write-output $xmlFinduser
}
function Confirm-FindResponse {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $response
    )
    if ($response -is [System.Xml.XmlDocument]) { 
        $errorFound = $false                  

        if ($null -ne $response.Envelope.Body.SearchResponse.searchResult.MessageOfErrorCodes) {
            $errorMessage = $response.Envelope.Body.SearchResponse.searchResult.MessageOfErrorCodes.text
            $errorFound = $true
        }
        if ($null -eq $response.Envelope.Body.SearchResponse.data) {
            $errorMessage = "Unknown error occurred while searching for user."  
            $errorFound = $true
        }
        if ($errorFound) {
            $exception = [System.Net.WebException]::new("$($ErrorMessage)")             
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'WolterskluwerTwinfieldSearchError', "InvalidResult", $ActionContext.Data)
            $errorRecord.ErrorDetails = $response.Envelope.Body.SearchResponse.OuterXml                    
            throw $errorRecord 
        }  
         
    }
}
function ConvertTo-HelloIDImportAccountObject {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $AccountObject
    )
    process {
        # Making sure only fieldMapping fields are imported
        $helloidImportAccountObject = [PSCustomObject]@{} 
        foreach ($field in $actionContext.ImportFields) {            
            switch ($field) {
                default {
                    if ($field -In $AccountObject.PSObject.Properties.Name) {
                        if ($AccountObject.$($field) -is [System.Xml.XmlElement]) {
                            $helloidImportAccountObject | Add-Member -MemberType NoteProperty -Name $field -Value $AccountObject.$($field).InnerText
                        }
                        else {
                            $helloidImportAccountObject | Add-Member -MemberType NoteProperty -Name $field -Value $AccountObject.$($field)
                        }
                    }
                } 
            }
        }
        Write-Output $helloidImportAccountObject        
    }
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions

#endregion

try { 
    
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
    
    $findHeaders = @{         
        'content-type' = 'text/xml; charset=utf-8' 
        'SOAPAction'   = "http://www.twinfield.com/Search"   
        'Host'         = $ApiUrl.Replace("https://", "")                               
                
    }
    [int] $take = 50  
    if ($actionContext.DryRun) {
        [int]$take = 10     
    }
    [int] $startIndex = 1  #startindex is 1-based index, as the API expects firstrow parameter to be 1-based.   
    do {

        $splatNewFindUserRequest = @{
            AccessToken   = $apiToken.access_token
            CompanyCode   = $actionContext.Configuration.Companycode
            SearchPattern = '*' 
            FirstRow      = $startIndex
            MaxRows       = $take
        }
        $xmlFinduser = New-FindUserRequest @splatNewFindUserRequest
    
        $splatFindUserParams = @{
            Uri     = $ApiUrl + '/webservices/finder.asmx'
            Method  = 'POST'
            Body    = $xmlFinduser.InnerXml
            Headers = $findHeaders        
        }

        if (-not  [string]::IsNullOrEmpty($actionContext.Configuration.ProxyAddress)) {
            $splatFindUserParams['Proxy'] = $actionContext.Configuration.ProxyAddress                
        }

        $findResponse = Invoke-RestMethod @splatFindUserParams 
        Confirm-FindResponse($findResponse)
        $accountsInfo = $findResponse.Envelope.Body.SearchResponse.data 
        if ($null -ne $accountsInfo.Items) {

            $accountCount = $accountsInfo.Items.Arrayofstring.Count
        }
        else {
            $accountCount = 0
        }        
        $totalResults = $accountsInfo.TotalRows        
        
        if ($accountCount -gt 0) {
            $Columns = $accountsInfo.Columns.string
            $userCodeIndex = $Columns.IndexOf('Code')
            $userNameIndex = $Columns.IndexOf('Naam')
            if ($userCodeIndex -eq -1 -or $userNameIndex -eq -1) {
                $message = "Could not find expected column indexes for 'Code' and 'Naam'. Columns found: $($Columns -join ','). Adjust field mapping if needed."
                Write-Warning $message
                throw $message
            }
            foreach ($account in $accountsInfo.Items.Arrayofstring) {
                $curUserCode = $account.String[$userCodeIndex]
                $curUserName = $account.String[$userNameIndex]
                $fullAccount = $null   
                [int] $retryCount = 0             
                # Extend account with details from read user request, to be able to import additional details and enabled state.

                try {
                    $splatreadUserRequest = @{
                        AccessToken = $apiToken.access_token
                        CompanyCode = $actionContext.Configuration.Companycode
                        UserCode    = $CurUserCode  
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

                    $readResponse = $null
                    do {
                        try {
                            $readResponse = Invoke-RestMethod @splatReadUserParams 
                            $retryCount = 0 #reset retry count after successful call
                        }
                        catch {
                            if ($_.Exception.Response.StatusCode -eq 429) {
                                $retryCount++
                                start-sleep -Seconds ($retryCount * 5)                                
                                continue                         
                            }
                            else {
                                throw $_
                            }
                        }
                    }
                    while ($retryCount -gt 0 -and $retryCount -le 10) 
                  
                    $ReadUserInfo = [xml] $readResponse.Envelope.Body.ProcessXmlStringResponse.ProcessXmlStringResult
                    $Accountdetails = $ReadUserInfo.user
                    if ($Accountdetails.result -eq 1) {
                        if ($Accountdetails.status -eq 'deleted') {                       
                            Continue
                        } 
                        $fullAccount = $Accountdetails
                    }
                    else {
                        Write-Warning "Error reading user details for usercode $($curUserCode). Error: $($PSItem.Exception.Message)"                   
                    }  
                }
                catch {
                    Write-Warning "Error reading user details for usercode $($curUserCode). Error: $($PSItem.Exception.Message)"
                }
                # Check if the account is disabled based on disable from/to fields. If parsing of disable details fails, user is assumed to be enabled, but warning is logged.             
                # 
                try {  
                    $isEnabled = $false;
                    $culture = [Globalization.CultureInfo]::InvariantCulture    
                    if ($null -eq $fullAccount.account.Disable) {
                        $isEnabled = $true
                    }
                    elseif ([string]::IsNullOrWhiteSpace($fullAccount.account.Disable.From)) {
                        if ([string]::IsNullOrWhiteSpace($fullAccount.account.Disable.To)) { 
                            $isEnabled = $true
                        }
                        else {                                                        
                            $disableTo = [datetime]::ParseExact($fullAccount.account.Disable.To, "yyyyMMddHHmmss", $culture)
                            if ($disableTo -lt (Get-Date)) {
                                $isEnabled = $true
                            }
                        }                                            
                    }                     
                    else { 
                        
                        $disableFrom = [datetime]::ParseExact($fullAccount.account.Disable.From, "yyyyMMddHHmmss", $culture)
                        if ($disableFrom -ge (Get-Date)) { 
                            $isEnabled = $true
                        }
                        else {                            
                            if (-not [string]::IsNullOrWhiteSpace($fullAccount.account.Disable.To)) {                            
                                $disableTo = [datetime]::ParseExact($fullAccount.account.Disable.To, "yyyyMMddHHmmss", $culture)
                                if ($disableTo -lt (Get-Date)) {
                                    $isEnabled = $true
                                }                             
                                
                            }                        
                        }
                           
                    }                                           
                }
                catch { 
                    $isEnabled = $false
                    Write-Warning "Error reading disable details for usercode $($curUserCode). Error: $($PSItem.Exception.Message)"
                }  

                $displayName = $CurUsername
                if ([string]::IsNullOrWhiteSpace($displayName)) {
                    $DisplayName = $curUserCode 
                } 
               
                if ($null -ne $fullAccount) {
                    $data = ConvertTo-HelloidImportAccountObject( $fullAccount ) 
                }        
                else {
                    $data = @{
                        Code = $curUserCode
                        Name = $curUserName                
                    }
                } 
            
                Write-Output @{
                    AccountReference = $curUserCode
                    displayName      = $DisplayName
                    UserName         = $CurUserName
                    Enabled          = $isEnabled
                    Data             = $data
                }
                $startIndex++
            }
        }
    } while (($accountCount -gt 0) -and ($startIndex -lt $totalResults))       
        
    Write-Information 'Wolterskluwer-Twinfield account entitlement import completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Wolterskluwer-TwinfieldError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import Wolterskluwer-Twinfield account entitlements. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import Wolterskluwer-Twinfield account entitlements. Error: $($ex.Exception.Message)"
    }
}
