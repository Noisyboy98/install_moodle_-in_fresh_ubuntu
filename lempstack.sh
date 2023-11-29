#!/bin/bash
checkroot() {
    if (( $EUID != 0 )); then
        # If user not is root, print message and exit script
        echo "Please run this script by user root ."
        exit
    else
		# If user is root, continue to function init
		init
    fi
}

update_os() {
    echo "Update and Upgrade"
	apt update
	apt upgrade -y
}

allow_ufw_port() {
	########## SSH, HTTP and HTTPS ##########
	ufw allow 22
	ufw allow 80
	ufw allow 443
}

set_timezone() {
	#Set the timezone to UTC
	echo "Set the timezone to UTC"
	ln -sf /usr/share/zoneinfo/UTC /etc/localtime
}

install_lemp() {
	########## Install nginx ##########
	echo "Install nginx"
	apt-get install -y curl nano wget lftp zip unzip git
	sudo apt install nginx -y
	sudo systemctl enable nginx
	sudo systemctl start nginx
	
	sudo ufw allow http

	sudo chown www-data:www-data /usr/share/nginx/html -R
	sudo chown www-data:www-data /var/www/ -R

	########## Install PHP7.4 and common PHP packages ##########
	echo "Install PHP 7.4"

	sudo apt install software-properties-common -y
	sudo add-apt-repository ppa:ondrej/php -y
	sudo apt install -y php7.4 php7.4-{fpm,mysql,common,cli,common,json,opcache,readline,mbstring,xml,gd,curl,zip,intl,xmlrpc,soap,pgsql}
						
	sudo systemctl enable php7.4-fpm
	sudo systemctl start php7.4-fpm
	
	########## Install Mysql ##########
	echo "Install Mysql"
	sudo apt install mysql-server -y
	sudo systemctl enable mysql
	sudo systemctl start mysql
	
	while true; do
		echo "Create new username (Press enter to use default username : moodleuser) or enter a new username :"
		read user
		if [ -n "$user" ]
		then
			username="$user"
		else
			username="moodleuser"
		fi
		echo "Create new password (Press enter to use default password : Videa@2022) or enter a new password :"
		read pass
		if [ -n "$pass" ]
		then
			password="$pass"
		else
			password="Videa@2022"
		fi
		read -p "Using $username-$password. Confirm ? [y/n]" yn
		case $yn in 
			[Yy]* ) break;;
			[Nn]* ) continue;;
			* ) echo "Please answer y or no.";;
		esac
	done
	echo  "Using $username-$password"
	

	while true; do
		echo "Create new database name (Press enter to use default database : moodle)"
		read dbname
		if [ -n "$dbname" ]
		then
			databasename="$dbname"
		else
			databasename="moodle"
		fi
		read -p "Using $databasename. Confirm ? [y/n]" yn
		case $yn in 
			[Yy]* ) break;;
			[Nn]* ) continue;;
			* ) echo "Please answer y or no.";;
		esac
	done
	
	mysql -uroot <<MYSQL_SCRIPT
CREATE DATABASE ${databasename};
CREATE USER '${username}'@'localhost' IDENTIFIED BY '${password}';
GRANT ALL PRIVILEGES ON *.* TO '${username}'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
	
	#Restart PHP-FPM - Nginx - Mysql
	sudo chown www-data:www-data /usr/share/nginx/html -R
	sudo chown www-data:www-data /var/www/ -R
	systemctl restart php7.4-fpm; 
	systemctl restart nginx;
	systemctl restart mysql;
}

install_composer() {
	#Install Composer
	curl -sS https://getcomposer.org/installer | php
	mv composer.phar /usr/local/bin/composer

	#Install and configure Memcached
	apt-get install -y memcached
	sed -i 's/-l 0.0.0.0/-l 127.0.0.1/' /etc/memcached.conf
	systemctl restart memcached
	
	while true; do
		read -p "Do you wish to install phpMyAdmin [y/n]" yn
		case $yn in
        [Yy]* )
			#We will install phpMyAdmin using Composer as Ubuntu packages are no longer being maintained.
			mkdir -pv /var/www/
			cd /var/www
			composer create-project phpmyadmin/phpmyadmin
			cp /var/www/phpmyadmin/config.sample.inc.php /var/www/phpmyadmin/config.inc.php
			mysql -u root -pYOUR_ROOT_PASSWORD < /var/www/phpmyadmin/sql/create_tables.sql
			sed -i "s/\$cfg\['blowfish_secret'\] = '';.*/\$cfg\['blowfish_secret'\] = '$(uuidgen)';/" /var/www/phpmyadmin/config.inc.php
			mkdir -pv /var/www/phpmyadmin/tmp; chown www-data:www-data /var/www/phpmyadmin/tmp;

			#Symlink phpMyAdmin, create logs dir and set permissions and ownership on /var/www
			ln -s /var/www/phpmyadmin/ /var/www/html/phpmyadmin;  mkdir -pv /var/www/logs;  chown www-data:www-data /var/www/html; chown www-data:www-data /var/www/logs; chown www-data:www-data /var/www; chmod -R g+rw /var/www;
			break;;
        [Nn]* )
			break;;
        * ) 
			echo "Please answer yes or no.";;
		esac
	done
	
}

install_nodeJs() {
	#Install latest NodeJS LTS
	echo "Install latest NodeJS LTS"
	curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash -
	apt-get install -y nodejs
}

config_hostname(){
	#Create Nginx virtual host config
	newdomain=""
	domain=$1
	rootPath=$2
	sitesEnable='/etc/nginx/sites-enabled/'
	sitesAvailable='/etc/nginx/sites-available/'
	sitesConfd='/etc/nginx/conf.d/'
	serverRoot='/var/www/html/'
	
	while true; do
		echo "Please provide your PRIMARY domain (sub domain not required) :"
		read domain
		
		if [ -n "$domain" ]
		then
			newdomain="$domain"
		else
			newdomain="dev.moodle.com"
		fi
		
		echo "Enter sub domain (optional): "
        read subdomain

		if [ -z "$subdomain" ];then
			domainname="$newdomain"
			echo $domainname
		else
			domainname="${subdomain}.${newdomain}"
		fi
		
		read -p "Using $domainname Confirm ? [y/n]" yn
		case $yn in 
			[Yy]* ) break;;
			[Nn]* ) continue;;
			* ) echo "Please answer y or no.";;
		esac
	done
	configName=${newdomain%%.*}
	if [ "$rootPath" = "" ]; then
		rootPath=$serverRoot$configName
	fi
	
	if ! [ -d $rootPath ]; then
        mkdir -pv $rootPath
        chmod 777 $rootPath	
	
	fi
	
	if ! [ -d $sitesEnable ]; then
        mkdir -pv $sitesEnable
        chmod 777 $sitesEnable
	fi

	if ! [ -d $sitesAvailable ]; then
		mkdir -pv $sitesAvailable
		chmod 777 $sitesAvailable
	fi
	
	if ! echo "server {
	  server_name $domainname;
	  root $serverRoot$configName;
	  index index.php index.html;
	  client_max_body_size 1024M;
	  
	  access_log /var/log/nginx/access.log;
	  error_log /var/log/nginx/error.log;
	  
	  location / {
		try_files \$uri \$uri/ =404;
	  }
	  
	  error_page 404 /404.html;
	  error_page 500 502 503 504 /50x.html;
	  
	  location = /50x.html {
		root /var/www/html;
	  }
	  
	  location ~ ^(.+\.php)(.*)$ {
	    fastcgi_split_path_info  ^(.+\.php)(/.+)$;
		fastcgi_index            index.php;
		fastcgi_pass             unix:/run/php/php7.4-fpm.sock;
		include                  fastcgi_params; 
		fastcgi_param   PATH_INFO       \$fastcgi_path_info;
		fastcgi_param   SCRIPT_FILENAME \$document_root$fastcgi_script_name;
	  }
	}" > $sitesAvailable$configName.conf
	then
		echo "There is an ERROR create $configName file"
		exit;
	else
		echo "New Virtual Host Created"
	fi
	
	#Symlink
	sudo ln -s /etc/nginx/sites-available/$configName.conf /etc/nginx/sites-enabled/

	rm /etc/nginx/sites-available/default	
	rm /etc/nginx/sites-enabled/default	
	
	while true; do
		read -p "Do you wish to install certbot [y/n]? " yn
		case $yn in
			[Yy]* ) 
				apt install -y python3-certbot-nginx certbot
				sudo certbot --nginx -d $configName -d www.$configName
			break;;
			[Nn]* ) break;;
			* ) echo "Please answer yes or no.";;
		esac
	done
	
	systemctl restart nginx;
	
} 

install_fromgit(){
	# Check condition if run in function config_hostname will get old variable
	if [ "$newdomain" = "" ]; then
		serverRoot='/var/www/html/'
		temp_dir='temp_dir'
	fi
	
	
	# Get clone URL from user input
	read -p "Enter clone URL: " clone_url

	# Clone the repository
	git clone $clone_url temp_dir
	
	# Change directory to the cloned repository 
	cd $serverRoot$temp_dir

	# Fetch all Git branches
	git fetch --all

	# Create an array of all Git branches
	branches=($(git branch -r | awk -F/ '{print $2}')) 

	# Create a select menu for the user to choose a branch
	PS3="Choose a branch: "
	select branch in "${branches[@]}"; do
	  # Checkout the selected branch
	  git checkout $branch
	  break
	done
	
	git config --global --add safe.directory $serverRoot$temp_dir

	sudo chown -R www-data:www-data $serverRoot$temp_dir
	sudo chmod -R 755 $serverRoot$temp_dir
	sudo systemctl restart nginx

	echo "Installation of Moodle ${version} complete!"
}

nginx_gzip(){
	#Configure Gzip for Nginx
	cat > /etc/nginx/conf.d/gzip.conf << EOF
gzip_comp_level 5;
gzip_min_length 256;
gzip_proxied any;
gzip_vary on;
gzip_types
application/atom+xml
application/javascript
application/json
application/rss+xml
application/vnd.ms-fontobject
application/x-web-app-manifest+json
application/xhtml+xml
application/xml
font/otf
font/ttf
image/svg+xml
image/x-icon
text/css
text/plain;
EOF

}

config_php_cli_fpm(){
	#Update PHP CLI configuration
	sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php/7.4/cli/php.ini
	sed -i "s/display_errors = .*/display_errors = On/" /etc/php/7.4/cli/php.ini
	sed -i "s/memory_limit = .*/memory_limit = 512M/" /etc/php/7.4/cli/php.ini
	sed -i "s/;date.timezone.*/date.timezone = UTC/" /etc/php/7.4/cli/php.ini

	#Tweak PHP-FPM settings
	sed -i "s/error_reporting = .*/error_reporting = E_ALL \& ~E_NOTICE \& ~E_STRICT \& ~E_DEPRECATED/" /etc/php/7.4/fpm/php.ini
	sed -i "s/display_errors = .*/display_errors = Off/" /etc/php/7.4/fpm/php.ini
	sed -i "s/memory_limit = .*/memory_limit = 512M/" /etc/php/7.4/fpm/php.ini
	sed -i "s/upload_max_filesize = .*/upload_max_filesize = 256M/" /etc/php/7.4/fpm/php.ini
	sed -i "s/post_max_size = .*/post_max_size = 256M/" /etc/php/7.4/fpm/php.ini
	sed -i "s/;date.timezone.*/date.timezone = UTC/" /etc/php/7.4/fpm/php.ini

	#Tune PHP-FPM pool settings
	sed -i "s/;listen\.mode =.*/listen.mode = 0666/" /etc/php/7.4/fpm/pool.d/www.conf
	sed -i "s/;request_terminate_timeout =.*/request_terminate_timeout = 60/" /etc/php/7.4/fpm/pool.d/www.conf
	sed -i "s/pm\.max_children =.*/pm.max_children = 70/" /etc/php/7.4/fpm/pool.d/www.conf
	sed -i "s/pm\.start_servers =.*/pm.start_servers = 20/" /etc/php/7.4/fpm/pool.d/www.conf
	sed -i "s/pm\.min_spare_servers =.*/pm.min_spare_servers = 20/" /etc/php/7.4/fpm/pool.d/www.conf
	sed -i "s/pm\.max_spare_servers =.*/pm.max_spare_servers = 35/" /etc/php/7.4/fpm/pool.d/www.conf
	sed -i "s/;pm\.max_requests =.*/pm.max_requests = 500/" /etc/php/7.4/fpm/pool.d/www.conf

	#Tweak Nginx settings
	sed -i "s/worker_processes.*/worker_processes auto;/" /etc/nginx/nginx.conf
	sed -i "s/# multi_accept.*/multi_accept on;/" /etc/nginx/nginx.conf
	sed -i "s/# server_names_hash_bucket_size.*/server_names_hash_bucket_size 128;/" /etc/nginx/nginx.conf
	sed -i "s/# server_tokens off/server_tokens off/" /etc/nginx/nginx.conf
}

# initialized the whole installation.
init() {
    update_os
	allow_ufw_port
	
	########## check set_timezone ##########
	while true; do
		read -p "Do you wish to set timezone to UTC [y/n]? " yn
		case $yn in
			[Yy]* ) set_timezone; break;;
			[Nn]* ) break;;
			* ) echo "Please answer yes or no.";;
		esac
	done
	########## check install_composer ##########
	while true; do
		read -p "Do you wish to install composer [y/n]? " yn
		case $yn in
			[Yy]* ) install_composer; break;;
			[Nn]* ) break;;
			* ) echo "Please answer yes or no.";;
		esac
	done
	########## check install_nodeJs ##########
	while true; do
		read -p "Do you wish to install nodeJs [y/n]? " yn
		case $yn in
			[Yy]* ) install_nodeJs; break;;
			[Nn]* ) break;;
			* ) echo "Please answer yes or no.";;
		esac
	done
	
	install_lemp
	########## check config_hostname ##########
	while true; do
		read -p "Do you wish to config hostname, domain [y/n]? " yn
		case $yn in
			[Yy]* ) config_hostname; break;;
			[Nn]* ) break;;
			* ) echo "Please answer yes or no.";;
		esac
	done

	while true; do
		read -p "Do you wish to install project from git [y/n]? " yn
		case $yn in
			[Yy]* ) install_fromgit; break;;
			[Nn]* ) break;;
			* ) echo "Please answer yes or no.";;
		esac
	done

	
	
	########## check nginx_gzip ##########
	while true; do
		read -p "Do you wish to config gzip nginx [y/n]? " yn
		case $yn in
			[Yy]* ) nginx_gzip; break;;
			[Nn]* ) break;;
			* ) echo "Please answer yes or no.";;
		esac
	done
	########## check config_php_cli_fpm ##########
	while true; do
		read -p "Do you wish to config php cli [y/n]? " yn
		case $yn in
			[Yy]* ) config_php_cli_fpm; break;;
			[Nn]* ) break;;
			* ) echo "Please answer yes or no.";;
		esac
	done
}

# primary function check.
main() {
    checkroot
}
main
exit