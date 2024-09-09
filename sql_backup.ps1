<#
# CITRA IT - EXCELÊNCIA EM TI
# SCRIPT PARA BACKUP DE BANCOS DE DADOS MSSQL
# AUTOR: luciano@citrait.com.br
# DATA: 10/10/2021
# EXAMPLO DE USO: Powershell -ExecutionPolicy ByPass -File C:\scripts\sql_backup.ps1 -TIPO <FULL|DIFF|LOG>
#
# Pré-Requisitos:
# 1. Definir o modelo de recuperação do banco de dados como FULL
# 2. Configurar a autenticação integrada do SQL Server e usar a conta configurada para executar este script.
# 3. A conta utilizada (de preferência administrator) deve ter permissão de escrita na pasta destino do backup.

#>
Param(
	[Parameter(Mandatory=$true)]
	[String]
	[ValidateSet("FULL","DIFF","LOG")]
	$TIPO
)


# Pasta raiz onde salvar os backups
$BACKUP_BASE_PATH = "C:\BACKUP"

# Nome da instância do MS SQL
$MSSQL_INSTANCE = ".\SQLEXPRESS"






#---------------------------------------------------------------------------
# DO NOT MODIFY ABOVE unless you know exactly what you are doing .-.
#---------------------------------------------------------------------------

#
# Function to display log messages on screen
#
Function Log
{
	Param([String]$text)
	$timestamp = Get-Date -Format G
	Write-Host -ForegroundColor Green "$timestamp`: $text"
}


#
# Function to display log error messages on screen
#
Function LogError
{
	Param([String]$text)
	$timestamp = Get-Date -Format G
	Write-Host -ForegroundColor Red "$timestamp`: $text"
}



# Logging the type of backup
Log("-------  STARTING THE BACKUP SCRIPT  -------")
Log("Going to run a $TIPO backup")


# Searching WHERE SQLCMD lives
$sqlcmd_path = ""
$sqlcmd_binary_found = $false
$path_dirs = $env:path.split(";")
ForEach($path_dir in $path_dirs)
{
	$possible_path = Join-Path -Path $path_dir -ChildPath "SQLCMD.EXE"
	If([System.IO.File]::Exists($possible_path))
	{
		$sqlcmd_binary_found = $true
		$sqlcmd_path = $possible_path
		Log("SQLCMD found at $sqlcmd_path")
	}
}
If(-Not $sqlcmd_binary_found)
{
	LogError("Could not find the SQLCMD.exe executable in this system !")
	LogError("Is this script running from a MSSQL Server? Make sure the SQLCMD.exe can be found on PATH")
	LogError("Exiting....")
	[System.Threading.Thread]::Sleep(5000)
	Exit(0)
}


# Getting datetime
$YearMonthDay = Get-Date -Format "yyyyMMdd"
$TimeStamp    = (Get-Date -Format O).substring(0,16).replace(":","-")
Log("Backup is going to folder $BACKUP_BASE_PATH`\$YearMonthDay")


# Checking if destination directory already exists
$DayDestinationDirectory = Join-Path -Path $BACKUP_BASE_PATH -ChildPath $YearMonthDay
If(-Not [System.IO.Directory]::Exists($DayDestinationDirectory))
{
	try{
		[System.IO.Directory]::CreateDirectory($DayDestinationDirectory) | Out-Null
	}catch [UnauthorizedAccessException] {
		LogError("The user running this script can't create the destination folder!")
		LogError("Make sure this user can write to $DayDestinationDirectory")
		LogError("Exiting....")
		[System.Threading.Thread]::Sleep(5000)
		Exit(0)
	}
}


# Internal databases that do not apply to backup
$databases_blacklist = @("tempdb","model","msdb")


# Querying actual databases on this server
$databases_found = &SQLCMD -E -S .\SQLEXPRESS -Q "SET NOCOUNT ON SELECT NAME FROM SYS.DATABASES" -h -1 -W


# Blacklisting some databases
$databases_to_backup = New-Object System.Collections.ArrayList
ForEach($db in $databases_found)
{
	If($db -notin $databases_blacklist )
	{
		$databases_to_backup.Add($db) | Out-Null
	}
	
}
Log("We are going to backup the following databases: $databases_to_backup")


# Backuping each database
ForEach($db in $databases_to_backup)
{
	# Verifying if the path of $DEST\YEAR_MONTH_DAY\DB_NAME\ exists or create it
	$db = $db.ToUpper()
	$DestinationDataBaseDirectory = Join-Path -Path $DayDestinationDirectory -ChildPath $db
	If(-Not [System.IO.Directory]::Exists($DestinationDataBaseDirectory))
	{
		try{
			[System.IO.Directory]::CreateDirectory($DestinationDataBaseDirectory) | Out-Null
		}catch [UnauthorizedAccessException] {
			LogError("The user running this script can't create the destination folder!")
			LogError("Make sure this user can write to $DestinationDataBaseDirectory")
			LogError("Exiting....")
			[System.Threading.Thread]::Sleep(5000)
			Exit(0)
		}
	}
	
	# The generated output file full path
	if($TIPO -eq "FULL" -or $TIPO -eq "DIFF")
	{
		$db_filename = [String]::Concat($TIPO, "_", $db, "_", $TimeStamp, ".BAK")
	}elseif($TIPO -eq "LOG")
	{
		$db_filename = [String]::Concat($TIPO, "_", $db, "_", $TimeStamp, ".TRN")
	}
	
	$DestinationFileName = Join-Path -Path $DestinationDataBaseDirectory -ChildPath $db_filename
	Log("Starting backup for database $db")
	Log("Saving a $TIPO backup of $db at $DestinationFileName")
	
	# Calling SQLCMD in a Child Process
	$pinfo = New-Object System.Diagnostics.ProcessStartInfo
	$pinfo.FileName = $sqlcmd_path
	$pinfo.RedirectStandardError = $true
	$pinfo.RedirectStandardOutput = $true
	$pinfo.UseShellExecute = $false
	
	# Switching argument to match backup type
	If($TIPO -eq "FULL")
	{
		$sqlcmd_arguments = [String]::Format("-E -S {0} -Q `"SET NOCOUNT ON BACKUP DATABASE [{1}] TO DISK='{2}'`"", $MSSQL_INSTANCE, $db, $DestinationFileName)
	}elseif($TIPO -eq "DIFF")
	{
		$sqlcmd_arguments = [String]::Format("-E -S {0} -Q `"SET NOCOUNT ON BACKUP DATABASE [{1}] TO DISK='{2}' WITH DIFFERENTIAL`"", $MSSQL_INSTANCE, $db, $DestinationFileName)
	}elseif($TIPO -eq "LOG")
	{
		$sqlcmd_arguments = [String]::Format("-E -S {0} -Q `"SET NOCOUNT ON BACKUP LOG [{1}] TO DISK='{2}'`"", $MSSQL_INSTANCE, $db, $DestinationFileName)
	}
	$pinfo.Arguments = $sqlcmd_arguments
	$backup_process = New-Object System.Diagnostics.Process
	$backup_process.StartInfo = $pinfo
	$backup_process.Start() | Out-Null
	$backup_process.WaitForExit()
	$stdout = $backup_process.StandardOutput.ReadToEnd()
	$stderr = $backup_process.StandardError.ReadToEnd()
	# Write-Host "stdout: $stdout"
	# Write-Host "stderr: $stderr"
	If($backup_process.ExitCode -eq 0)
	{
		Log("Successfully saved $db at $DestinationFileName")
	}Else{
		LogError("Error backuping the database $db with sqlcmd exit code " + $backup_process.ExitCode)
		LogError($stdout)
		LogError($stderr)
	}
	

}


<# 
Recovering Notes

Generally you do a full backup at the starting of the day, and many log (incremental) backups during the day.
To restore the whole chain, 
1. Delete the original database on SQL Server.
2. Construct a T-Script to execute with the following sentences ( for example):
----------------------------------------------------------------------------------------------------------
RESTORE DATABASE [MYDATABASE] FROM DISK='C:\backup\20211010\MYDATABASE\FULL_DB1_2021-10-10T23-07.BAK' WITH NORECOVERY
GO
RESTORE LOG [MYDATABASE] FROM DISK='C:\backup\20211010\MYDATABASE\LOG_DB1_2021-10-10T23-09.TRN' WITH NORECOVERY
GO
RESTORE LOG [MYDATABASE] FROM DISK='C:\backup\20211010\MYDATABASE\LOG_DB1_2021-10-10T23-10.TRN' WITH RECOVERY
GO
----------------------------------------------------------------------------------------------------------
Note that all but least restore instruction should have option "WITH NORECOVERY", so it keeps the database in a restore mode and the last restore set "WITH RECOVERY"
that brings the whole database online again !!

#>
<#
REFERENCES:

1. https://docs.microsoft.com/pt-br/sql/t-sql/statements/backup-transact-sql?view=sql-server-ver15
2. https://docs.microsoft.com/pt-br/sql/relational-databases/backup-restore/recovery-models-sql-server?view=sql-server-ver15

#>


