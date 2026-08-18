$re = 'dsh[\\/]lib[\\/]bin\.js|@deepseek-ai[\\/]dsh'
Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
  Where-Object { $_.CommandLine -match $re } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
