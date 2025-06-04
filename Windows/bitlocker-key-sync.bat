@echo off
setlocal

:: Check encryption status
for /F "tokens=3 delims= " %%A in ('manage-bde -status %systemdrive% ^| findstr "    Encryption Method:"') do (
    if "%%A"=="AES" goto EncryptionCompleted
    if "%%A"=="XTS-AES" goto EncryptionCompleted
    if "%%A"=="None" goto TPMActivate
)

goto ElevateAccess

:TPMActivate
powershell Get-BitLockerVolume

echo.
echo  =============================================================
echo  = It looks like your System Drive (%systemdrive%\) is not   =
echo  = encrypted. Let's try to enable BitLocker.                 =
echo  =============================================================

for /F %%A in ('wmic /namespace:\\root\cimv2\security\microsofttpm path win32_tpm get IsEnabled_InitialValue ^| findstr "TRUE"') do (
    if "%%A"=="TRUE" goto starttpm
)

goto TPMFailure

:starttpm
powershell Initialize-Tpm

:bitlock
manage-bde -protectors -disable %systemdrive%
bcdedit /set {default} recoveryenabled No
bcdedit /set {default} bootstatuspolicy ignoreallfailures

manage-bde -protectors -delete %systemdrive% -type RecoveryPassword
manage-bde -protectors -add %systemdrive% -RecoveryPassword

:: Backup new recovery key to AD
for /F "tokens=2 delims=: " %%A in ('manage-bde -protectors -get %systemdrive% -type RecoveryPassword ^| findstr "ID:"') do (
    echo Backing up recovery key ID %%A to AD...
    manage-bde -protectors -adbackup %systemdrive% -id %%A
)

manage-bde -protectors -enable %systemdrive%
manage-bde -on %systemdrive% -SkipHardwareTest

goto VerifyBitLocker

:VerifyBitLocker
for /F "tokens=3 delims= " %%A in ('manage-bde -status %systemdrive% ^| findstr "    Encryption Method:"') do (
    if "%%A"=="AES" goto EncryptionCompleted
    if "%%A"=="XTS-AES" goto EncryptionCompleted
    if "%%A"=="None" goto TPMFailure
)

:TPMFailure
echo.
echo  =============================================================
echo  = System Volume Encryption on drive (%systemdrive%\) failed.=
echo  = The problem could be the TPM chip is off in the BIOS.     =
echo  = Make sure the TPM is present and ready.                   =
echo  =============================================================

powershell get-tpm

echo  Closing session in 30 seconds...
TIMEOUT /T 30 /NOBREAK
exit

:EncryptionCompleted
echo.
echo  =============================================================
echo  = Your system drive (%systemdrive%) is already encrypted.   =
echo  = Attempting to backup the recovery key to AD...            =
echo  =============================================================

:: Backup existing recovery key to AD
for /F "tokens=2 delims=: " %%A in ('manage-bde -protectors -get %systemdrive% -type RecoveryPassword ^| findstr "ID:"') do (
    echo Backing up existing recovery key ID %%A to AD...
    manage-bde -protectors -adbackup %systemdrive% -id %%A
)

powershell Get-BitLockerVolume

echo  Closing session in 20 seconds...
TIMEOUT /T 20 /NOBREAK
exit

:ElevateAccess
echo.
echo  =============================================================
echo  = It looks like you need to run this program as Admin.      =
echo  = Please right-click and choose 'Run as Administrator'.     =
echo  =============================================================

echo  Closing session in 20 seconds...
TIMEOUT /T 20 /NOBREAK
exit
