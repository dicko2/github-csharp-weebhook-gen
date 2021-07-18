FROM mcr.microsoft.com/powershell:latest
WORKDIR /src
VOLUME /output
VOLUME /finaloutput
#ADD https://github.com/octokit/webhooks/archive/refs/tags/v4.1.0.zip /output
#ADD https://github.com/agoda-com/NJsonSchema.CodeGeneration.CLI/releases/download/v1.1.8/linux-x64.zip /output
COPY gen-code.ps1 .
ENTRYPOINT [ "./gen-code.ps1", "-path", "/output"]