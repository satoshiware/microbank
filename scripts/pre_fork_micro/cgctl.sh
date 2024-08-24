#!/bin/bash

# Make sure we are not running as root, but that we have sudo privileges.
if [ "$(id -u)" = "0" ]; then
   echo "This script must NOT be run as root (or with sudo)!"
   exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
   echo "You do not have enough sudo privileges!"
   exit 1
fi

# See which teller parameter was passed and execute accordingly
if [[ $1 = "--help" ]]; then # Show all possible paramters
    cat << EOF
    Options:
      --start       Start cgminer
      --stop        Stop cgminer
      --restart     Restart cgminer
      --log         Update the log on the web server @ http://$(hostname -I | grep -Eo '([0-9]*\.){3}[0-9]*' | tr '\n' '\n')/log.html
      --screen      Post the latest cgminer to the web server @ http://$(hostname -I | grep -Eo '([0-9]*\.){3}[0-9]*' | tr '\n' '\n')/screen.html
EOF

elif [[ $1 = "--install" ]]; then # Installs or updates this script (payouts) /w a "payouts -o" cron job (Run "crontab -e" as $USER to see all ${USER}'s cron jobs)
    echo "Installing this script (cgctl) in /usr/local/sbin/"
    if [ -f /usr/local/sbin/cgctl ]; then
        echo "This script (cgctl) already exists in /usr/local/sbin!"
        read -p "Would you like to reinstall it? (y|n): "
        if [[ "${REPLY}" = "y" || "${REPLY}" = "Y" ]]; then
            sudo rm /usr/local/sbin/cgctl
            cd ~; git clone https://github.com/satoshiware/microbank
            bash ~/microbank/scripts/pre_fork_micro/cgctl.sh --install
            rm -rf microbank
            exit 0
        else
            exit 0
        fi
    fi

    sudo cat $0 | sudo tee /usr/local/sbin/cgctl > /dev/null
    sudo chmod +x /usr/local/sbin/cgctl

    # Add Cron Jobs
    (crontab -l | grep -v -F "/usr/local/sbin/cgctl --start" ; echo "@reboot /bin/bash -lc \"/usr/local/sbin/cgctl --start\"" ) | crontab - # Start cgminer @ boot
    (crontab -l | grep -v -F "/usr/local/sbin/cgctl --log" ; echo "*/5 * * * * /bin/bash -lc \"/usr/local/sbin/cgctl --log\"" ) | crontab - # Cron Job: Update log (on the web) every 5 minutes
    (crontab -l | grep -v -F "/usr/local/sbin/cgctl --screen" ; echo "*/5 * * * * /bin/bash -lc \"/usr/local/sbin/cgctl --screen\"" ) | crontab - # Cron Job: Update screen shot (on the web) every 5 minutes
    (crontab -l | grep -v -F "/usr/local/sbin/cgctl --restart" ; echo "0 0 * * * /bin/bash -lc \"/usr/local/sbin/cgctl --restart\"" ) | crontab - # Cron Job: Restart every day

elif [[ $1 == "--start" ]]; then # Start cgminer
    # If there is not a "cgscreen screen" then start one with cgminer running
    if [[ -z $(sudo screen -ls | grep "cgscreen") ]]; then
        sudo screen -S cgscreen -dm bash -c 'cgminer -c /etc/cgminer.conf 2>> /var/log/cgminer/cgminer.log' # Start new screen as root in detached mode called "cgscreen" and run cgminer
        echo "New \"cgscreen screen\" running cgminer has been launched!"
    else
        echo "There is already an instance of \"cgscreen screen\"!"
    fi

elif [[ $1 == "--stop" ]]; then # Stop cgminer
    sudo screen -S cgscreen -X quit # Close the "cgscreen screen"

elif [[ $1 == "--restart" ]]; then # Restart cgminer
    $0 --stop
    echo "Wait 5 seconds..."; sleep 5
    $0 --start

elif [[ $1 == "--log" ]]; then # Update the log on the web server
    # Read tail end of cgminer log
    output=$(sudo tail -500 /var/log/cgminer/cgminer.log)
    output=${output//$'\n'/'<br>'}
    output=${output// /\&nbsp;}
    echo $output | sudo tee /var/www/html/log.html

elif [[ $1 == "--screen" ]]; then # Post the latest cgminer to the web server
    # Get a screen shot of "cgscreen screen"
    if [[ ! -z $(sudo screen -ls | grep "cgscreen") ]]; then
        cd ~; sudo screen -S cgscreen -X hardcopy
        clear; output=$(tail -100 ~/hardcopy.0); sudo rm ~/hardcopy.0
        output=${output//$'\n'/'<br>'}
        output=${output// /\&nbsp;}
        echo $output | sudo tee /var/www/html/screen.html
    else
        echo "Error! There is no \"cgscreen screen\" available!" | sudo tee /var/www/html/screen.html
    fi

else
    $0 --help
    echo "Script Version 0.02"
fi