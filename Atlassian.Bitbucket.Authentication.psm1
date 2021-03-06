using module .\Classes\Atlassian.Bitbucket.Auth.psm1
using module .\Classes\Atlassian.Bitbucket.Settings.psm1

<#
    .SYNOPSIS
        Login to Bitbucket

    .DESCRIPTION
        Allows logins to Bitbucket for both Basic authentication or OAuth 2.0.

    .EXAMPLE
        Login-Bitbucket -Credential (Get-Credential)
        # Provide authentication for API calls using Basic Auth

    .EXAMPLE
        Login-Bitbucket -AtlassianCredential (Get-Credential) -OAuthConsumer (Get-Credential)
        # Provide authentication for API calls using OAuth 2.0

    .PARAMETER Credential
        Username and password in Bitbucket for basic authentication.

    .PARAMETER AtlassianCredential
        Email and password for Atlassian Authentication.  Used with OAuthConsumer to generate token.

    .PARAMETER OAuthConsumer
        Key and Secret for OAuth Consumer.  https://confluence.atlassian.com/bitbucket/oauth-on-bitbucket-cloud-238027431.html#OAuthonBitbucketCloud-Createaconsumer
#>
function New-BitbucketLogin {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Low', DefaultParameterSetName='Basic')]
    [Alias('Login-Bitbucket')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Basic')]
        [PSCredential]$Credential,
        [Parameter(Mandatory = $true, ParameterSetName = 'OAuth2')]
        [PSCredential]$AtlassianCredential,
        [Parameter(Mandatory = $true, ParameterSetName = 'OAuth2')]
        [PSCredential]$OAuthConsumer,
        [Switch]$Save
    )
    if ($pscmdlet.ShouldProcess('Bitbucket Login', 'create'))
    {
        switch ($PSCmdlet.ParameterSetName) {
            'Basic' {
                $Auth = [BitbucketAuth]::NewInstance($Credential)
            }
            'OAuth2' {
                $Auth = [BitbucketAuth]::NewInstance($AtlassianCredential, $OAuthConsumer)
            }
            Default {
                'You must specify either Basic or OAuth Credentials.'
            }
        }

        Write-Output "Welcome $($Auth.User.display_name)"

        Select-BitbucketTeam

        if($Save){
            Save-BitbucketLogin
        }
    }
}

function Save-BitbucketLogin {
    [CmdletBinding()]
    param(
    )

    $Auth = [BitbucketAuth]::GetInstance()
    $Auth.save()
}

function Get-BitbucketLogin {
    [CmdletBinding()]
    param(
    )

    $Auth = [BitbucketAuth]::GetInstance()

    return $Auth.User
}

function Remove-BitbucketLogin {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Low')]
    param(
    )
    if ($pscmdlet.ShouldProcess('Bitbucket Login', 'remove'))
    {
        [BitbucketAuth]::ClearInstance()
    }
}

function Invoke-BitbucketAPI {
    [CmdletBinding()]
    param(
        [String]$Path = '',
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method = 'Get',
        [Object]$Body,
        [Switch]$Paginated,
        [Switch]$InternalAPI
    )
    $Auth = [BitbucketAuth]::GetInstance()

    if($InternalAPI){
        $URI = [BitbucketSettings]::INTERNAL_URL + $Path
        if($Auth.AuthType -ne 'Bearer'){
            Throw 'You must use OAuth 2.0 for Internal APIs.  Login using: Login-Bitbucket -AtlassianCredential (Get-Credential) -OAuthConsumer (Get-Credential)'
        }
    }else{
        $URI = [BitbucketSettings]::VERSION_URL + $Path
    }

    if($Paginated){
        $_endpoint = $URI

        # Process Pagination
        do
        {
            Write-Debug "URI: $_endpoint"
            $return = Invoke-RestMethod -Uri $_endpoint -Method $Method -Body $Body -Headers $Auth.GetAuthHeader()  -ContentType 'application/json'
            $_endpoint = $return.next
            $response += $return.values
        }
        while ($return.next)

        return $response
    }else{
        if($Body){
            Write-Debug 'Sending request with a body and content type'
            Write-Debug "Body: $Body"
            return Invoke-RestMethod -Uri $URI -Method $Method -Body $Body -Headers $Auth.GetAuthHeader()  -ContentType 'application/json'
        }else{
            Write-Debug 'Sending request with no body or content type'
            return Invoke-RestMethod -Uri $URI -Method $Method -Headers $Auth.GetAuthHeader()
        }
    }
}

function Get-BitbucketTeam {
    [CmdletBinding()]
    param(
        [ValidateSet('admin', 'contributor', 'member')]
        [String]$Role = 'member'
    )
    $endpoint = "teams?role=$Role"

    return (Invoke-BitbucketAPI -Path $endpoint).values
}

function Get-BitbucketSelectedTeam {
    [CmdletBinding()]
    param(
    )

    $Auth = [BitbucketAuth]::GetInstance()
    return $Auth.Team
}

function Select-BitbucketTeam {
    [CmdletBinding()]
    param(
        [String]$Team
    )

    if(!$Team){
        $Teams = Get-BitbucketTeam
        $index = 0

        if($Teams.count -gt 1){

            for ($i = 0; $i -lt $Teams.Count; $i++) {
                Write-Output "$i - $($Teams[$i].username)"
            }
            [int]$index = Read-Host 'Which team would you like to use?'
        }
        $Team = $Teams[$index].username
    }

    $Auth = [BitbucketAuth]::GetInstance()
    $Auth.Team = $Team
}