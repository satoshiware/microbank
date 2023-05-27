# Install Debian Instance
wsl --install -d Debian<br/>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;# Enter Username<br/>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;# Enter Password<br/>
exit # Return back to the PowerShell<br/>
wsl --terminate Debian # #################################Return back to the PowerShell<br/>

# Create a new micro node instance from the Debian install
$INSTANCE = Read-Host -Prompt 'Enter the desired name for the wsl micro node instance'
wsl --export Debian $HOME\debian.tar
wsl --import $INSTANCE $HOME\$INSTANCE $HOME\debian.tar

# Let's remove the Debian instance now that we are done.
wsl --unregister Debian # Remove the Debian Instance (no longer needed)
rm $HOME\debian.tar

# Provide user the link to boot their new instance
echo "wsl -d $INSTANCE -u $USERNAME"
