#!/usr/bin/env pwsh
Param(
[string]$webhookSchemaVersion="4.1.0",
[string]$path="$PWD"
)
$ResultPath="webhooks-$webhookSchemaVersion/payload-schemas/api.github.com"
cd $path


$ctrlrStart = @"
using Microsoft.AspNetCore.Mvc;
using System.Threading.Tasks;
using Github.WebHooks.Services;
using Newtonsoft.Json.Linq;

namespace Github.WebHooks.Controllers
{
    [ApiController]
    [Route("webhook")]
    public class WebHookController : ControllerBase
    {
        private readonly IWebHookService _webHookService;

        public WebHookController(IWebHookService webHookService)
        {
            _webHookService = webHookService;
        }

"@

$ctrlrMid = @"

        [HttpPost]
        public async Task WebHookName([FromBody] JObject webHookName)
        {

"@

$interfaceStart =@"
using System.Threading.Tasks;

namespace Github.WebHooks.Services
{
    public interface IWebHookService
    {
"@

$interafaceMid =@"

      Task ProcessWebHookName(WebHookName webHookName);
"@

function ToPascalCase
{
Param([String] $t
)
return (Get-Culture).TextInfo.ToTitleCase(($t.ToLower() -replace "_", " ")) -replace " ", ""
}

if(!(Test-Path nJsonSchemaCodeGeneration.exe))
{
Invoke-WebRequest https://Github.com/agoda-com/NJsonSchema.CodeGeneration.CLI/releases/download/v1.1.8/linux-x64.zip -OutFile linux-x64.zip
Add-Type -Assembly 'System.IO.Compression.FileSystem'
[System.IO.Compression.ZipFile]::ExtractToDirectory("$path/linux-x64.zip","$path")
chmod 777 nJsonSchemaCodeGeneration
}

if(!(Test-Path "v$webhookSchemaVersion"))
{
Invoke-WebRequest "https://Github.com/octokit/webhooks/archive/refs/tags/v$webhookSchemaVersion.zip" -OutFile "v$webhookSchemaVersion.zip"
Add-Type -Assembly 'System.IO.Compression.FileSystem'
[System.IO.Compression.ZipFile]::ExtractToDirectory("$path/v$webhookSchemaVersion.zip","$path/v$webhookSchemaVersion")
}

foreach($dir in Get-ChildItem "$path/v$webhookSchemaVersion/$ResultPath" -Directory)
{
    if($dir.Name -ne "common")
    {
        if(!(Test-Path ($dir.FullName + "/common")))
        {
         copy-item "$path/v$webhookSchemaVersion/$ResultPath/common" $dir.FullName -Recurse
        }
         # Change folder name to pascal casing
         $newFodlerName = ToPascalCase -t $dir.Name 
         $fullNewFolderName = ($dir.Parent.FullName + "/" + $newFodlerName)
         move-item $dir.FullName $fullNewFolderName -Force
         $fullNewFolderName 
    }
}
remove-item "$path/v$webhookSchemaVersion/$ResultPath/common" -Force -Recurse
./nJsonSchemaCodeGeneration -s "$path/v$webhookSchemaVersion/$ResultPath" -c csharp -n Github.WebHooks
$outputPath = "csharp/"
mkdir "$outputPath/Controllers"
mkdir "$outputPath/Services"
foreach($folder in Get-ChildItem "csharp" -Directory)
{

if($folder.Name -ne "common")
{
$objKind = $folder.Name
$IWebHookService = "IWebHookService$objKind"
$ctrlrFinal = @"

using Github.WebHooks.$objKind;

"@
$ctrlrFinal += $ctrlrStart
$ctrlrFinal = $ctrlrFinal.Replace("WebHookController",("WebHook" + $objKind + "Controller"))
$ctrlrFinal = $ctrlrFinal.Replace("IWebHookService",$IWebHookService)
$ctrlrFinal = $ctrlrFinal.Replace("WebHookName", "$objKind").Replace("`"webhook`"","`"api/$objKind`"")

$ctrlrFinal += $ctrlrMid
$interfaceFinal = @"

using Github.WebHooks.$objKind;

"@ + $interfaceStart.Replace("IWebHookService",$IWebHookService)

   $x = New-Object Collections.Generic.List[String]

    foreach($file in Get-ChildItem $folder.FullName -File)
    {
    
        $snakeCase = $file.Name.Substring(0, $file.Name.Length-3)
        $x.Add($snakeCase);
        $newName = (ToPascalCase -t $file.Name.Substring(0, $file.Name.Length-3).Replace("-", "_"))
        $newFullName = $folder.FullName + "/" + $newName + ".cs"
        move-item $file.FullName $newFullName
        
        $interfaceFinal += $interafaceMid.Replace("ProcessWebHookName", "Process$objKind").Replace("WebHookName", "$newName")

        $content = [System.IO.File]::ReadAllText($newFullName).Replace("public partial class Json","public partial class $newName")
        [System.IO.File]::WriteAllText($newFullName, $content)

    }
    if($x.Count -eq 1)
    {
    $switch = "await _webHookService.Process$objKind(JsonConvert.DeserializeObject<$newName>(webHookName.ToString()));"
    }
    else
    {

    #switch statement
    $switch = @"
            switch(webHookName["action"])
            {

"@
    foreach($case in $x)
    {
    $pcase = ToPascalCase -t $case
    $switch += @"
              case "$case":
                await _webHookService.Process$objKind(JsonConvert.DeserializeObject<$pcase>(webHookName.ToString()));

"@
    }
    $switch += @"
                default:
                     throw new Exception("Action " + webHookName["action"] + " in Event $objKind not recognised");
            }

"@
    }
    $ctrlrFinal +=$switch;
    $ctrlrFinal += @"
        }
    }
}
"@
$interfaceFinal+= @"

    }
}
"@
$extraUsing =""
foreach($case in $x)
{
    $pcase = ToPascalCase -t $case
    $extraUsing =@"

    using Github.WebHooks.$objKind.$pcase;
"@
}
$ctrlrFinal | Out-File ("$outputPath/Controllers/WebHook" + $objKind + "Controller.cs")
$interfaceFinal | Out-File "$outputPath/Services/$IWebHookService.cs"
}
}


@"
<Project Sdk="Microsoft.NET.Sdk.Web">

  <PropertyGroup>
    <TargetFramework>net5.0</TargetFramework>
  </PropertyGroup>
  
  <ItemGroup>
    <PackageReference Include="Newtonsoft.Json" Version="13.0.1" />
  </ItemGroup>

</Project>
"@ | Out-File "$outputPath/Github.WebHooks.csproj"

@"
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Hosting;

namespace Github.WebHooks
{
    public class Program
    {
        public static void Main(string[] args)
        {
            CreateHostBuilder(args).Build().Run();
        }

        public static IHostBuilder CreateHostBuilder(string[] args) =>
            Host.CreateDefaultBuilder(args)
                .ConfigureWebHostDefaults(webBuilder =>
                {
                    webBuilder.UseStartup<Startup>();
                });
    }
}

"@ | Out-File "$outputPath/Program.cs"

@"

using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace Github.WebHooks
{
    public class Startup
    {
        public Startup(IConfiguration configuration)
        {
            Configuration = configuration;
        }

        public IConfiguration Configuration { get; }

        // This method gets called by the runtime. Use this method to add services to the container.
        public void ConfigureServices(IServiceCollection services)
        {

            services.AddControllers();
        }

        // This method gets called by the runtime. Use this method to configure the HTTP request pipeline.
        public void Configure(IApplicationBuilder app, IWebHostEnvironment env)
        {
            if (env.IsDevelopment())
            {
                app.UseDeveloperExceptionPage();
            }

            app.UseRouting();

            app.UseAuthorization();

            app.UseEndpoints(endpoints =>
            {
                endpoints.MapControllers();
            });
        }
    }
}

"@ | Out-File "$outputPath/Startup.cs"

copy-item csharp /finaloutput -Recurse -Force