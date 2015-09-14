$start_time = Get-Date
Add-Type -assembly "system.io.compression.filesystem"

$32_bit_links =
@("http://dl.bintray.com/oneclick/rubyinstaller/rubyinstaller-2.1.7.exe",
 "http://dl.bintray.com/oneclick/rubyinstaller/DevKit-mingw64-32-4.7.2-20130224-1151-sfx.exe",
 "https://github.com/git-for-windows/git/releases/download/v2.5.2.windows.1/PortableGit-2.5.2-32-bit.7z.exe",
 "http://curl.haxx.se/ca/cacert.pem")

$64_bit_links =
@("https://dl.bintray.com/oneclick/rubyinstaller/rubyinstaller-2.1.7-x64.exe",
 "http://dl.bintray.com/oneclick/rubyinstaller/DevKit-mingw64-64-4.7.2-20130224-1432-sfx.exe",
 "https://github.com/git-for-windows/git/releases/download/v2.5.2.windows.1/PortableGit-2.5.2-64-bit.7z.exe",
 "http://curl.haxx.se/ca/cacert.pem")

 If([Environment]::Is64BitProcess){
    $links = $64_bit_links}
 Else{
    $links = $32_bit_links}

 foreach ($source in $links) {
    $Filename = [System.IO.Path]::GetFileName($source)
    $dependencies_output = "$PSScriptRoot\installers\dependencies\"
    
    New-Item -ItemType Directory -Force -Path $dependencies_output
    $output_file = "$dependencies_output\$Filename"
    Echo $output_file

    If(Test-Path $output_file){
        "File already exists"
    }Else{
        "Downloading " + $Filename
        (New-Object System.Net.WebClient).DownloadFile($source, $output_file)
    }
 }
$notepad = "https://notepad-plus-plus.org/repository/6.x/6.8.3/npp.6.8.3.bin.zip"
$Filename = [System.IO.Path]::GetFileName($notepad)
$tools_folder = "$PSScriptRoot\installers\helpful_tools\"
New-Item -ItemType Directory -Force -Path $tools_folder
$notepad_installer = "$tools_folder\$Filename"
$notepad_destination = "$tools_folder\Notepad++"
New-Item -ItemType Directory -Force -Path $notepad_destination
if( (Get-ChildItem $notepad_destination | Measure-Object).Count -eq 0){
    "Downloading " + $Filename
    (New-Object System.Net.WebClient).DownloadFile($notepad, $notepad_installer)
    [io.compression.zipfile]::ExtractToDirectory($notepad_installer, $notepad_destination)
    Remove-Item $notepad_installer
}
Else{
    "Notepad already extracted."
}

Write-Output "Time taken: $((Get-Date).Subtract($start_time).Seconds) second(s)"