# HelloID-Conn-Prov-Target-Wolterskluwer-Twinfield

<!--
** for extra information about alert syntax please refer to [Alerts](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts)
-->


> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

> [!IMPORTANT]
> The delete action in the delete script is a soft-delete. Currently reboarding of soft deleted accounts is not possible.  If HelloId would create an account with the same code as a deleted account, an error will be logged, and no user is created.

<p align="center">
  <img src="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Wolterskluwer-Twinfield/blob/main/Logo.png?raw=true">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Wolterskluwer-Twinfield](#helloid-conn-prov-target-connectorname)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Wolterskluwer-Twinfield_ is a _target_ connector. _Wolterskluwer-Twinfield_ provides a set of Soap/xml api's that allow you to programmatically interact with its data.

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                                 | Remarks           |
| ----------------------------------------- | --------- | --------------------------------------- | ----------------- |
| **Account Lifecycle**                     | ✅         | Create, Update, Enable, Disable, Delete |                   |
| **Permissions**                           | ❌         |                                        |                    |
| **Resources**                             | ❌         | -                                       |                   |
| **Entitlement Import: Accounts**          | ✅ ⚠️     | -                                       |                   |
| **Entitlement Import: Permissions**       | ❌         | -                                       |                   |
| **Governance Reconciliation Resolutions** | ✅        | -                                       |                   |


### ⚠️ Entitlement Import: Accounts
The finder webservice only retrieves the code and name fields, other fields require a separate call to the read endpoint for each account.
This may cause performance issues when there is a very large number of accounts

<!-- 
Example
### ⚠️ Governance Reconciliation Resolutions
Governance reconciliation is supported for reporting purposes.
Resolutions are not possible because... 
-->

## Getting started

### HelloID Icon URL
URL of the icon used for the HelloID Provisioning target system.
```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Wolterskluwer-Twinfield/refs/heads/main/Icon.png
```

### Requirements

- Correlation is done by matching the sAMAccountName directly with the account "code" field. This requires that the sAMAccountName adheres to the Requirements of twinfield Code field (Such as no dots in the name). 

### Connection settings

The following settings are required to connect to the API.

| Setting  | Description                          | Mandatory |
| -------- | ----------------------------------   | --------- |
| ClientId | The UserName to connect to the API   | Yes       |
| ClientSecrtet | The Password to connect to the API  | Yes       |
| RefreshToken | The refresh token to attain the access token to connect to the API               | Yes       |
| TokenUrl | The Uri to the Token generation endpoint. "https://login.twinfield.com/auth/authentication/connect/token"  | Yes       |
| CompanyCode | The CompanyCode to connect to the API. | Yes    |

The basic url to the cluster that hosts the endpoints is automatically determined in the code, so there is no separate BaseUrl 

- Due to API rate limitations it is quite easy to exceed this rate limit. Therfore it is recommended to set the maximum concurrent session in Helloid to 1.  

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Wolterskluwer-Twinfield_ to a person in _HelloID_.

| Setting                   | Value                             |
| ------------------------- | --------------------------------- |
| Enable correlation        | `True`                            |
| Person correlation field  | `Accounts.MicosoftActiveDirectory.sAMAccountName` |
| Account correlation field | `Code` 

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file. 
Note that the update action only updates the name, shortname and email fields. Most of the other fields are mapped to None for all actions but the create action, to indicate a output only field. 

The type field is a mapped to the fixed value of "accountant" for all actions, and cannot be mapped to None for any action as it required by the read api call.

### Account Reference

The account reference is populated with the `Code` property from the account in _Wolterskluwer-Twinfield_  This is also the value on wich the account is correlated. There is no internal "id" property available. This also means that it is not possible the change the user code in the update actions.

## Remarks

- The user Code field can only contain the character values  A until Z, 0 untol 9, _, - and +  and have a maximum length of 16 characters."  Assumed is that Your sAMAccount name does adhere to this. If not, the correlation process should be changed.

- The user fields "type", Culture, Role, and InvitationStatus have a fixed value in the Field Mapping. It may be required to change that to other fixed values depending on the actual Twinfield implementation used. 

- The Password field is required on account create.

- The Company Code is used as default office for the created user, as an office is required when createing a new account.

- The delete action is a soft-delete. Currently reboarding of soft deleted accounts is not possible.  If HelloId would create an account with the same code as a deleted account, an error will be logged, and no user is created.


- The import script will not list deleted accounts, as they are not returned by the finder.  Also it needs to query the twinfield api for each account to collect detailed data.

-API calls may be slow and also may be rate-limited. There is some limited retry mechanism implemented in the import script where this is most likeley to occur , but not in the other scripts. It may be required to fine-tune this per implementation.

- When an application level api error occurs, the result code is 200 (success) and the error is inside the particular item in the xml response. It is tried to parse this info into a meaningfull error message. However this process may not always succeed. Therefore instead of throwing a simple error string, a [System.Management.Automation.ErrorRecord] object is thrown with the full xml response in the errordetails, which is handled as usual in the standard error function in the outer catch. 

- When executing this connector with the "Execute on-premises" switch on, the read call may fail to correctly read some very special characters that may occur in user names.  

## Development resources

### API endpoints

The following endpoints are used by the connector

| Endpoint |  Description  |
|-----------|--------------|
|//webservices/processxml.asmx  | General endpoint for all xml commands. read,create,update,delete specific objects |
| //webservices/finder.asmx   | General endpoint for al search actions, only used in import script |

### API documentation

https://developers.twinfield.com/documentation/api/authentication/openid-connect-auth
https://developers.twinfield.com/documentation/api/master-data/users/
https://developers.twinfield.com/documentation/api/miscellaneous/finder/

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
