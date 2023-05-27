# WSL Micro Node
The Windows Subsystem for Linux (WSL) lets developers run a GNU/Linux environment, including most command-line tools, utilities, and applications directly on Windows! However, the environment is not very secure and could pose risks building a network on top of it. Therefore, it is highly recommended to only implement a WSL node for limited purposes and to take additional measures to secure funds (i.e. store large amounts offline; e.g Satoshi Savings Card) and secure the connection to the network: highly recommended only operate with one outbound node connection and take the security of the Windows OS seriously.<br/><br/>

To make your WSL node experience more successful, make sure to turn off automatic updates (prevent windows from rebooting unknowingly). Also, disable sleep/hibernation mode. Even though there are workarounds, the most straightforward way to keep your WSL instance alive is to always leave the WSL terminal window open.<br/><br/>

Note: If you haven't discovered the new "Windows Terminal" software readily available for download. Check it out before you get started (optional).

## Install WSL
\# Run PowerShell (as administrator)<br/>
wsl --install<br/>
dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart # Make sure Virtual Machines are enabled.<br/>
\# Restart the Computer!

## Update the Kernel
\# Download and install [Link wsl_update_x64](https://docs.microsoft.com/en-us/windows/wsl/install-manual#step-4---download-the-linux-kernel-update-package)<br/>
\# Restart the Computer... Again!

## Update and Configure WSL
\# Run PowerShell (as administrator)<br/>
wsl --set-default-version 2<br/>
wsl --update

## Install Debian
wsl --unregister Debian # Let's make sure we are starting with a fresh install<br/>
wsl --install -d Debian<br/>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;# Enter Desired $USERNAME<br/>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;# Enter Desired Password<br/>
exit # Return back to the PowerShell<br/>
wsl --terminate Debian # Shutdown the new Debian instance

## Create a new micronode instance from the Debian install
$INSTANCE = Read-Host -Prompt 'Enter the desired name for the wsl micro node instance'<br/>
wsl --export Debian $HOME\debian.tar<br/>
wsl --import $INSTANCE $HOME\\$INSTANCE $HOME\debian.tar

## Remove Debian (no longer needed)
wsl --unregister Debian<br/>
rm $HOME\debian.tar

## Link to boot the new instance
c:\windows\system32\wsl.exe -d $INSTANCE -u $USERNAME

## WSL Commands
wsl -d $INSTANCE # Run desired instance<br/>
wsl -d $INSTANCE -u $USERNAME # Run instance with desired user on startup<br/>
wsl -t micro-node # Stop (Turn Off)<br/>
wsl -l -v # List WSL instances and their status<br/>
wsl --unregister $INSTANCE # Uninstall desired instance<br/>
wsl --shutdown # Shutdown (restart) WSL and all instances
