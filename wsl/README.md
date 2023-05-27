# Install Debian
wsl --install -d Debian<br/>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;# Enter Desired $USERNAME<br/>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;# Enter Desired Password<br/>
exit # Return back to the PowerShell<br/>
wsl --terminate Debian # Shutdown the new Debian instance

# Create a new micro node instance from the Debian install
$INSTANCE = Read-Host -Prompt 'Enter the desired name for the wsl micro node instance'<br/>
wsl --export Debian $HOME\debian.tar<br/>
wsl --import $INSTANCE $HOME\$INSTANCE $HOME\debian.tar

# Remove Debian (no longer needed)
wsl --unregister Debian<br/>
rm $HOME\debian.tar<br/>

# Link to boot the new instance
c:\windows\system32\wsl.exe -d $INSTANCE -u $USERNAME"
