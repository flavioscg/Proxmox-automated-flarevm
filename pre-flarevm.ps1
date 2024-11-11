(New-Object net.webclient).DownloadFile('https://raw.githubusercontent.com/mandiant/flare-vm/main/install.ps1',"$([Environment]::GetFolderPath("Desktop"))\install.ps1")
Unblock-File .\flarevm.ps1

Set-ExecutionPolicy Unrestricted -Force

.\install.ps1 -noWait -noGui -noPassword
