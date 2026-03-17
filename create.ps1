#################################################
# HelloID-Conn-Prov-Target-Wolterskluwer-Twinfield-Create
# PowerShell V2
#################################################

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

function New-CreateUserRequest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $AccessToken,

        [Parameter(Mandatory)]
        [string]
        $CompanyCode,

        [Parameter(Mandatory)]
        [object]
        $Data       
    )   

    $xmlUser = ('<![CDATA[<user>      
     <office><default>{0}</default><offices><office>{0}</office></offices></office>  
    <code>{1}</code>  
    <name>{2}</name>
    <shortname>{3}</shortname>    
    <type>{4}</type>    
    <password>{5}</password>
    <culture>{6}</culture>
    <email>{7}</email>
    <role>{8}</role>     
    <invitationstatus>{9}</invitationstatus> 
    <account><disable><from>{10}</from><to></to></disable></account>              
 </user>]]>' -f $CompanyCode, $Data.code, $Data.name,
        $Data.shortname, $Data.type, $Data.password, $Data.culture,
        $Data.email, $Data.role , $Data.invitationstatus,
        (Get-Date).ToString("yyyyMMddHHmmss"))    

    $xmlCreateUser = [xml] ('<?xml version="1.0" encoding="utf-8"?>
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

    $xmlCreateUser.Envelope.Header.Header.AccessToken = $AccessToken
    $xmlCreateUser.Envelope.Header.Header.CompanyCode = $CompanyCode   
   
    write-output $xmlCreateUser

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
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'
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

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        # Determine if a user needs to be [created] or [correlated]
        $splatreadUserRequest = @{
            AccessToken = $apiToken.access_token
            CompanyCode = $actionContext.Configuration.Companycode
            UserCode    = $correlationValue
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
                throw "The account [$($correlatedAccount.code)] that is supposed to be correlated is marked as deleted in Wolterskluwer-Twinfield. Please check the account status in Wolterskluwer-Twinfield and try again."
            }
            else {
                $action = 'CorrelateAccount'
            }              
        }
        elseif ($correlatedAccount.result -eq 0) {
            if ($correlatedAccount.status -eq 'default') {
                $action = 'CreateAccount'
            }
            else {
                $action = 'Unexpected'
            } 
        }
        else {
            $action = 'Unexpected' 
        }
    }
    else {
        throw 'Correlation is not enabled but this script is meant to be used with correlation. Please enable correlation and provide the correct configuration. If you are certain you do not want to use correlation, please change the script to not expect correlation and handle the creation of accounts accordingly. For example, you can set $action = "CreateAccount" by default if you are sure you always want to create accounts.'
        $action = 'CreateAccount'
    }

    # Process
    switch ($action) {
        'CreateAccount' {

            $headers = @{         
                'content-type' = 'text/xml; charset=utf-8' 
                # 'SOAPAction'   = "http://www.twinfield.com/Search"   
                'Host'         = $ApiUrl.Replace("https://", "")                               
            }
            $splatNewCreateUserRequest = @{
                AccessToken = $apiToken.access_token
                CompanyCode = $actionContext.Configuration.Companycode
                Data        = $ActionContext.Data
            }
            $xmlCreateUser = New-CreateUserRequest @splatNewCreateUserRequest

            $splatCreateUserParams = @{
                Uri     = $ApiUrl + '/webservices/processxml.asmx'
                Method  = 'POST'
                Body    = $xmlCreateUser.InnerXml
                Headers = $headers                        
            }

            if (-not  [string]::IsNullOrEmpty($actionContext.Configuration.ProxyAddress)) {
                $splatCreateUserParams['Proxy'] = $actionContext.Configuration.ProxyAddress
            }
            # Make sure to test with special characters and if needed; add utf8 encoding.
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information 'Creating and correlating Wolterskluwer-Twinfield account'              

                $createResponse = Invoke-RestMethod @splatCreateUserParams
                $createdUserInfo = [xml] $createResponse.Envelope.Body.ProcessXmlStringResponse.ProcessXmlStringResult
                if ($CreatedUserInfo.user.result -ne '1') {

                    $ErrorMessage = "Creating user $($ActionContext.Data.Code) [$($CreatedUserInfo.user.msg)]"
                    foreach ($property in $CreatedUserInfo.user.PSObject.Properties) {                      
                        $node = $CreatedUserInfo.user."$($property.Name)"                      
                        if (($node -is [System.Xml.XmlElement]) -and ($node.msgtype -eq 'error')) {                                                                        
                            $ErrorMessage += "[$($property.Name) : $($node.msg)]" 
                        }   
                    }
                    $ErrorMessage += "]"
                    $exception = [System.Net.WebException]::new("$($ErrorMessage)")
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'WolterskluwerTwinfieldCreateError', "InvalidResult", $ActionContext.Data)
                    $errorRecord.ErrorDetails = $CreatedUserInfo.user.OuterXml                    
                    throw $errorRecord 
                }
            
                $createdAccount = $CreatedUserInfo.user

                # Make sure to filter out arrays from $outputContext.Data (If this is not mapped to type Array in the fieldmapping). This is not supported by HelloID.
                $outputContext.Data = ConvertTo-HelloIDAccountObject -AccountObject $createdAccount
                $outputContext.AccountReference = $createdAccount.code
            }
            else {
                Write-Information '[DryRun] Create and correlate Wolterskluwer-Twinfield account, will be executed during enforcement'
            }
            $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
            break
        }

        'CorrelateAccount' {
            Write-Information 'Correlating Wolterskluwer-Twinfield account'            

            # Make sure to filter out arrays from $outputContext.Data (If this is not mapped to type Array in the fieldmapping). This is not supported by HelloID.
            $outputContext.Data = ConvertTo-HelloIDAccountObject -AccountObject $correlatedAccount
            $outputContext.AccountReference = $correlatedAccount.Code
            $outputContext.AccountCorrelated = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            break
        }
        'Unexpected' {
            $ErrorMessage = "Unexpected result while searching for user. Message: [$($correlatedAccount.msg)]"        
            $exception = [System.Net.WebException]::new("$($ErrorMessage)")
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'WolterskluwerTwinfieldReadError', "InvalidResult", $ActionContext.Data)
            $errorRecord.ErrorDetails = $ReadUserInfo.OuterXml      
            throw $errorRecord           
        }
    }
    $outputContext.success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = $action
            Message = $auditLogMessage
            IsError = $false
        })
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Wolterskluwer-TwinfieldError -ErrorObject $ex
        $auditMessage = "Could not create or correlate Wolterskluwer-Twinfield account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.FriendlyMessage) Details: [$($errorObj.ErrorDetails)]"
    }
    else {
        $auditMessage = "Could not create or correlate Wolterskluwer-Twinfield account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}