[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $path
)

docker build . -t githubwebhook:latest
docker run -v ${path}:/finaloutput githubwebhook:latest
