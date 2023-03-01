#!/usr/bin/bash

echo "updating system"
sudo apt update -y 

#packages list
packages="apache2 php unzip php-mysql php-cgi php-cli php-gd mariadb-client libapache2-mod-php "

echo "installaing packages"
sudo apt install -y $packages


echo "creating dbscript"
echo "CREATE DATABASE wordpress;CREATE USER 'wpuser'@'10.0.%.%' IDENTIFIED BY 'yourpassword';GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'10.0.%.%';FLUSH PRIVILEGES;" > dbscript

echo "creating databse in rds"
RESULT_VARIABLE="$(mysql -h rdsendpoint -P 3306 -u admin -pyourpassword -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = 'wpuser')")"

if [ "$RESULT_VARIABLE" = 1 ]; then
echo "already exists"
else
  mysql -h rdsendpoint -P 3306 -u admin -pyourpassword < dbscript
fi


echo "Downloading wordpress"
wget https://wordpress.org/latest.zip

echo "unziping latest.zip"
unzip latest.zip

echo "after unziping cd to wordpress"
cd wordpress

echo "copying wordpress files to /var/www/html"
sudo cp -r * /var/www/html

echo "cd to home directory"
cd

echo "now cd to /var/www/html"
cd /var/www/html

echo "Removing index.html"
sudo rm -rf index.html

echo "changing apache permissions"
sudo chown -R www-data:www-data /var/www

echo "cd to home directory"
cd


echo "cd to /var/www/html"
cd /var/www/html

echo "creating health.html"
echo -e '<html>\n<html>\n\t<body>\n\t\t<h1>Hello World!</h1>\n\t</body>\n</html>' > health.html

echo "creating config.php from the sample.php"
sudo cp wp-config-sample.php wp-config.php


sudo sed -i "s/database_name_here/wordpress/;s/username_here/wpuser/;s/password_here/yourpassword/;s/localhost/rdsendpoint/" wp-config.php



echo "Restarting apache2 "
sudo systemctl restart apache2
