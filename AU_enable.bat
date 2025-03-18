reg add HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU  /v NoAutoUpdate /t REG_DWORD  /d 0 /f
net stop wuauserv
net start wuauserv
wuauclt.exe /resetauthorization /detectnow
