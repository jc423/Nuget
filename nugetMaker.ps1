param(
	[string]$solutionName,
	[string]$projectName,
	[string]$projectFolderPath
)

if(-not($solutionName)) { Throw "You must supply a solution name" }
if(-not($projectName)) { Throw "You must supply a project name" }
if(-not($projectFolderPath)) { Throw "You must supply path to folder containing csproj file" }

function CopyReferencedProject ($projectName)
{
	"Copying files for "+$projectName
	$pathToReferenceProject = $global:projectFolderPath -replace "\\[^\\]*$" , "\"
    $folder = $pathToReferenceProject+$projectName
	xcopy /s /q $folder $global:solutionPath\$projectReference\
}

function IsProjectNotInList ($projectName){
	$isNotInList = $true
	foreach($project in $global:projectsList.GetEnumerator()){
		if($project.Value -eq $projectName){
			$isNotInList = $false
		}
	}
	return $isNotInList
}


function GetProjectReferences ($projectReference) 
{
	$isNotInProjectList = IsProjectNotInList($projectReference)
	if($isNotInProjectList){
	    CopyReferencedProject($projectReference)
	    $projFile = Get-ChildItem -Path $global:solutionPath\$projectReference\ .\*csproj
	    $prjXML = New-Object XML
	    $prjXML.Load($global:solutionPath+"\"+$projectReference+"\"+$projFile.Name)
	    $projectGuid = ($prjXML.Project.PropertyGroup | Where-Object { $_['ProjectGuid'] -ne $null}).ProjectGuid
	    $prjXML.Project.ItemGroup.ProjectReference
	    $projectReferences = $prjXML.Project.ItemGroup.ProjectReference.Name
        "Adding "+$projectReference+" to projects List"
	    $global:projectsList.Add($projectGuid,$projectReference)
	    foreach($projectReference in $projectReferences){
		    $projectReference
		    GetProjectReferences($projectReference)
	    }
	}

}

cd "C:\IH\NET\Nuget"
"Creating Solution Folder"
mkdir $solutionName
cd $solutionName
$global:solutionPath = $pwd.path
$global:projectFolderPath = $projectFolderPath
$global:projectsList = New-Object "collections.generic.dictionary[guid,string]"
mkdir $projectName

"Copying Project Folder to Solution Folder"
xcopy /s /q $projectFolderPath $global:solutionPath\$projectName

"Get csproj File"
$projFile = Get-ChildItem -Path $global:solutionPath\$projectName .\*csproj
$prjXML = New-Object XML
$prjXML.Load($global:solutionPath+"\"+$projectName+"\"+$projFile.Name)

#region get proj properties
"Getting project Guid needed to add project to solution"
$projectGuid = ($prjXML.Project.PropertyGroup | Where-Object { $_['ProjectGuid'] -ne $null}).ProjectGuid
$projectReferences = $prjXML.Project.ItemGroup.ProjectReference.Name

"Setting RootNamespace and AssemblyName"
($prjXML.Project.PropertyGroup | Where-Object { $_['RootNamespace'] -ne $null}).RootNamespace = $projectName
($prjXML.Project.PropertyGroup | Where-Object { $_['AssemblyName'] -ne $null}).AssemblyName = $projectName
$projectGuid = $prjXML.Project.PropertyGroup[0].ProjectGuid
#endregion

Get-ChildItem -Path $global:solutionPath\$projectName -Filter .\*.user | Rename-Item -NewName $projectName".csproj.user"
Get-ChildItem -Path $global:solutionPath\$projectName -Filter .\*.vspscc | Rename-Item -NewName $projectName".csproj.vspscc"

#region postbuild event
"Adding postbuild event"
$ns = "http://schemas.microsoft.com/developer/msbuild/2003"
$propertyGroup = $prjXML.CreateElement("PropertyGroup",$ns)
$postBuildEvent = $prjXML.CreateElement("PostBuildEvent",$ns)
$postBuildEvent.InnerXml = @"
nuget.exe pack `"`$(ProjectPath)`" -Prop Configuration=Release
xcopy /Y `"`$(TargetDir)$projectName.*.nupkg`" C:\NugetPackages
del `"`$(TargetDir)$projectName.*.nupkg`" 
"@

"Including nuget file (actual file not yet created)"
$prjXML.Project.AppendChild($propertyGroup)
$propertyGroup.AppendChild($postBuildEvent)
$itemGroup = $prjXML.CreateElement("ItemGroup",$ns)
$none = $prjXML.CreateElement("None",$ns)
$none.SetAttribute("Include",$projectName + ".nuspec")
$subType = $prjXML.CreateElement("SubType",$ns)
$subType.InnerXml = "Designer"

$prjXML.Project.AppendChild($itemGroup)
$itemGroup.AppendChild($none)
$none.AppendChild($subType)

"Removing old .csproj file"
Remove-Item -Path $global:solutionPath\$projectName\$projFile

$prjXML.Save($global:solutionPath+"\"+$projectName+"\"+$projectName+".csproj")

$global:projectsList.Add($projectGuid,$projectName)

#endregion

"Copying over all project that are referenced"
$pathToReferenceProject = $projectFolderPath -replace "\\[^\\]*$" , "\"

"Getting Referenced Projects CSPROJ File"
foreach($projectReference in $projectReferences)
{
	GetProjectReferences($projectReference)
}

"Creating Solution File"
"Adding All Projects"

$projectsString = ""

foreach($project in $global:projectsList.GetEnumerator()){
	$projectString = "`""+$project.Value+"`", `""+$project.Value+"\"+$project.Value+".csproj`""
	$projectsString = $projectsString + "`nProject(`"{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}`") = "+$projectString+", `"{"+$project.Key+"}`"`nEndProject"
}


"Adding csproj info to solution file"
$solutionFile = "Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio 2013
VisualStudioVersion = 12.0.31101.0
MinimumVisualStudioVersion = 10.0.40219.1`n"+$projectsString+"`nGlobal
	GlobalSection(SolutionProperties) = preSolution
		HideSolutionNode = FALSE
	EndGlobalSection
EndGlobal"

$solutionPath = $global:solutionPath+"\"+$solutionName+".sln"
$solutionFile > $solutionPath

"Creating nuspec file"
cd $projectName
nuget spec $projectName".csproj"



