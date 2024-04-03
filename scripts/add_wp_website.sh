#!/bin/bash

# Make sure we are not running as root, but that we have sudo privileges.
if [ "$(id -u)" = "0" ]; then
    echo "This script must NOT be run as root (or with sudo)!"
    echo "if you need to create a sudo user (e.g. satoshi), run the following commands:"
    echo "   sudo adduser satoshi"
    echo "   sudo usermod -aG sudo satoshi"
    echo "   sudo su satoshi # Switch to the new user"
    exit 1
elif [ "$(sudo -l | grep '(ALL : ALL) ALL' | wc -l)" = 0 ]; then
    echo "You do not have enough sudo privileges!"
    exit 1
fi
cd ~; sudo pwd # Print Working Directory; have the user enable sudo access if not already.

# Give the user pertinent information about this script and how to use it.
clear
echo "This script will install a single wordpress site on an already configured Apache 2 server."
echo "Make sure your DNS records are already configured."
echo "Uses \"Let's Encrypt\" SSL Certificate Authority."
echo ""
echo "To edit, configure, and design the wordpress website, goto \"\$DNS/wp-admin\"."
echo ""
echo "The command to update the administrator email for \"Let's Encrypt\" certbot:"
echo "    \"sudo certbot update_account --no-eff-email --email \$EMAIL\""
echo "The \"Administration Email Address\" for Wordpress can be changed in \"wp-admin\" Settings."
echo ""
echo "Plugins that are installed with the script: "
echo "    \"Limit Login Attempts Reloaded\""
echo "    \"Salt Shaker\""
echo "    \"UpdraftPlus\""
echo "    \"WP Mail SMTP\""
read -p "Press the enter key to continue..."

########## Get Setup Parameters from The User ##############
read -p "Web site/server title? (e.g. BTCofAZ): " TITLE
read -p "Domain name address? (e.g. btcofaz.com): " DNS; DNS=${DNS,,}; DNS=${DNS#http://}; DNS=${DNS#https://}; DNS=${DNS#www.} # Make lowercase and remove http and www if they exist.
read -p "Administrator email? (e.g. satoshi@btcofaz.com): " EMAIL; EMAIL=${EMAIL,,} # Make lowercase

# Create site folders, files, and websites with correct permissions
sudo mkdir -p /var/www/$DNS
sudo chown -R www-data:www-data /var/www
sudo chmod -R 755 /var/www/$DNS

# Site configuration
cat << EOF | sudo tee /etc/apache2/sites-available/$DNS.conf
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    ServerName $DNS
    ServerAlias www.$DNS
    DocumentRoot /var/www/$DNS
    ErrorLog \${APACHE_LOG_DIR}/$DNS.error.log
    CustomLog \${APACHE_LOG_DIR}/$DNS.access.log combined
    <Directory /var/www/$DNS>
        AllowOverride All
    </Directory>
</VirtualHost>
EOF

sudo a2ensite $DNS
sudo a2enmod rewrite
sudo systemctl restart apache2 # Restart apache server

########## Create admin (satoshi) and database passwords ##############
# Create secure wordpress admin password replacing '/' with '0', '+' with '1', and '=' with ''
WP_PASSWD=$(openssl rand -base64 14); WP_PASSWD=${WP_PASSWD//\//0}; WP_PASSWD=${WP_PASSWD//+/1}; WP_PASSWD=${WP_PASSWD//=/}
echo "${WP_PASSWD}" | sudo tee ~/wp_satoshi_passwd.txt
sudo chmod 600 ~/wp_satoshi_passwd.txt
# Create secure wordpress database password replacing '/' with '0', '+' with '1', and '=' with ''
DB_PASSWD=$(openssl rand -base64 14); DB_PASSWD=${DB_PASSWD//\//0}; DB_PASSWD=${DB_PASSWD//+/1}; DB_PASSWD=${DB_PASSWD//=/}

########## Install Wordpress ##############
# Download Wordpress
cd /var/www/$DNS; sudo -u www-data wp core download

# Create new database and new user
sudo mysql -e "CREATE USER IF NOT EXISTS 'wpmaria_${DNS//./_}'@'localhost' IDENTIFIED BY ''"
sudo mysql -e "SET PASSWORD FOR 'wpmaria_${DNS//./_}'@'localhost' = PASSWORD('${DB_PASSWD}')"
sudo mysql -e "CREATE DATABASE IF NOT EXISTS mariadb_${DNS//./_}"
sudo mysql -e "GRANT ALL PRIVILEGES ON mariadb_${DNS//./_}.* TO 'wpmaria_${DNS//./_}'@'localhost'"
sudo mysql -e "FLUSH PRIVILEGES"

# Configure Wordpress
sudo -u www-data wp config create --dbname=mariadb_${DNS//./_} --dbuser=wpmaria_${DNS//./_} --dbpass=${DB_PASSWD}
sudo -u www-data wp core install --url=$DNS --title="$TITLE" --admin_user=satoshi --admin_password=$WP_PASSWD --admin_email=$EMAIL

# Set up auto Wordpress updates
cat << EOF | sudo tee /etc/cron.daily/wp-core-update-$DNS
cd /var/www/$DNS
sudo -u www-data wp core update
sudo -u www-data wp theme update --all
EOF
sudo chmod -R 755 /etc/cron.daily/wp-core-update-$DNS # Keep wordpress updated

########## Install Plugins ##############
cd /var/www/$DNS
sudo -u www-data wp plugin install limit-login-attempts-reloaded --force --activate # Limit Login Attempts Reloaded
sudo -u www-data wp plugin install salt-shaker --force --activate # Salt Shaker
sudo -u www-data wp plugin install updraftplus --force --activate # UpdraftPlus
sudo -u www-data wp plugin install wp-mail-smtp --force --activate # WP Mail SMTP

########## Configure the "Let's Encrypt" certbot for SSL certificates ##############
# If there is no subdomain (only a single '.'), add a second (identical) DNS with the "www." prefix
if [[ ${DNS//[^.]} == "." ]]; then DNS=$DNS,www.$DNS; fi
# Get new certificate and have certbot edit the apache configurations automatically
sudo certbot --apache --agree-tos --redirect --hsts --uir --staple-ocsp --no-eff-email --email $EMAIL -d $DNS