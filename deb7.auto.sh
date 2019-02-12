#!/bin/sh

# Пишем логи установки
LOG_PIPE=/tmp/log.pipe.$$
mkfifo ${LOG_PIPE}
LOG_FILE=/tmp/log.file.$$
tee < ${LOG_PIPE} ${LOG_FILE} &
exec  > ${LOG_PIPE}
exec  2> ${LOG_PIPE}
LogClean() {
	rm -f ${LOG_PIPE}
	rm -f ${LOG_FILE}
}

# Переменные среды
MIRROR="http://mirror.enginegp.ru"
IPv4=$(echo "${SSH_CONNECTION}" | awk '{print $3}')
MYPASS=$(openssl rand -base64 10 | cut -c -10)
MYPASS2=$(openssl rand -base64 10 | cut -c -10)
OS=$(lsb_release -s -i -c -r | xargs echo |sed 's; ;-;g' | grep Ubuntu)
FILE='/etc/apache2/conf.d/enginegp'
SAVE='/root/enginegp.txt'
SWAP='/etc/fstab'

# Создаём файл подкачки
dd if=/dev/zero of=/swap.file bs=1M count=2048
chmod 600 /swap.file
mkswap /swap.file
echo "/swap.file      swap            swap    defaults        0       0">>$SWAP

# Обновляем пакеты
apt-get update

# Устанавливаем пакеты
apt-get install -y apt-utils
apt-get install -y pwgen
apt-get install -y dialog

# Добавляем репозиторий
if [ "$OS" = "" ]; then
	echo "deb http://mirror.yandex.ru/debian/ wheezy main" > /etc/apt/sources.list
	echo "deb-src http://mirror.yandex.ru/debian/ wheezy main" >> /etc/apt/sources.list
	echo "deb http://security.debian.org/ wheezy/updates main" >> /etc/apt/sources.list
	echo "deb-src http://security.debian.org/ wheezy/updates main" >> /etc/apt/sources.list
	echo "deb http://mirror.yandex.ru/debian/ wheezy-updates main" >> /etc/apt/sources.list
	echo "deb-src http://mirror.yandex.ru/debian/ wheezy-updates main" >> /etc/apt/sources.list
	echo "deb http://packages.dotdeb.org wheezy-php55 all">"/etc/apt/sources.list.d/dotdeb.list"
	echo "deb-src http://packages.dotdeb.org wheezy-php55 all">>"/etc/apt/sources.list.d/dotdeb.list"
fi

# Устанавливаем ключ
wget http://www.dotdeb.org/dotdeb.gpg
apt-key add dotdeb.gpg
rm dotdeb.gpg

# Обновляем пакеты
apt-get update
apt-get upgrade -y

# Задаём пароль MySQL
echo mysql-server mysql-server/root_password select "$MYPASS" | debconf-set-selections
echo mysql-server mysql-server/root_password_again select "$MYPASS" | debconf-set-selections

# Устанавливаем пакеты
apt-get install -y apache2 php5 php5-dev cron unzip sudo nano php5-curl php5-memcache php5-json memcached mysql-server php5-mysql libapache2-mod-php5 php-pear

# Включаем модуль Apache2
a2enmod php5
service apache2 restart

# Устанавливаем phpMyAdmin
echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/admin-user string root" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/admin-pass password $MYPASS" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/app-pass password $MYPASS" |debconf-set-selections
echo "phpmyadmin phpmyadmin/app-password-confirm password $MYPASS" | debconf-set-selections
echo 'phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2' | debconf-set-selections
apt-get install -y phpmyadmin

# Устанавливаем mysql-server 5.6
echo mysql-apt-config mysql-apt-config/select-server select mysql-5.6 | debconf-set-selections
echo mysql-apt-config mysql-apt-config/select-product select Ok | debconf-set-selections
wget https://dev.mysql.com/get/mysql-apt-config_0.8.7-1_all.deb
export DEBIAN_FRONTEND=noninteractive
dpkg -i mysql-apt-config_0.8.7-1_all.deb
apt-get update
apt-get --yes --force-yes install mysql-server
sudo mysql_upgrade -u root -p$MYPASS --force --upgrade-system-tables
service mysql restart
rm mysql-apt-config_0.8.7-1_all.deb

# Устанавливаем библиотеку SSH2
if [ "$OS" = "" ]; then
	apt-get install -y curl php5-ssh2
else
	apt-get install -y libssh2-php
fi

# Создаем хост в Apache2 - создание файлов виртуальных хостов
echo "<VirtualHost *:80>">$FILE
echo "	ServerName $IPv4">>$FILE
echo "	DocumentRoot /var/www">>$FILE
echo "	<Directory /var/www/>">>$FILE
echo "	Options Indexes FollowSymLinks MultiViews">>$FILE
echo "	AllowOverride All">>$FILE
echo "	Order allow,deny">>$FILE
echo "	allow from all">>$FILE
echo "	</Directory>">>$FILE
echo "	ErrorLog \${APACHE_LOG_DIR}/error.log">>$FILE
echo "	LogLevel warn">>$FILE
echo "	CustomLog \${APACHE_LOG_DIR}/access.log combined">>$FILE
echo "</VirtualHost>">>$FILE

# Перезагружаем Apache2
service apache2 restart

# Включаем модуль mod_rewrite для Apache2
a2enmod rewrite

# Перезагружаем Apache2
service apache2 restart
	
# Добавляем Cron задания
(crontab -l ; echo "*/2 * * * * screen -dmS scan_servers bash -c 'cd /var/www && php cron.php key123 threads scan_servers'
*/2 * * * * screen -dmS scan_servers bash -c 'cd /var/www && php cron.php key123 threads scan_servers'
*/5 * * * * screen -dmS scan_servers_load bash -c 'cd /var/www && php cron.php key123 threads scan_servers_load'
*/5 * * * * screen -dmS scan_servers_route bash -c 'cd /var/www && php cron.php key123 threads scan_servers_route'
*/1 * * * * screen -dmS scan_servers_down bash -c 'cd /var/www && php cron.php key123 threads scan_servers_down'
*/10 * * * * screen -dmS notice_help bash -c 'cd /var/www && php cron.php key123 notice_help'
*/15 * * * * screen -dmS scan_servers_stop bash -c 'cd /var/www && php cron.php key123 threads scan_servers_stop'
*/15 * * * * screen -dmS scan_servers_copy bash -c 'cd /var/www && php cron.php key123 threads scan_servers_copy'
*/30 * * * * screen -dmS notice_server_overdue bash -c 'cd /var/www && php cron.php key123 notice_server_overdue'
*/30 * * * * screen -dmS preparing_web_delete bash -c 'cd /var/www && php cron.php key123 preparing_web_delete'
*/60 * * * * screen -dmS scan_servers_admins bash -c 'cd /var/www && php cron.php key123 threads scan_servers_admins'
*/1 * * * * screen -dmS control_delete bash -c 'cd /var/www && php cron.php key123 control_delete'
*/1 * * * * screen -dmS control_install bash -c 'cd /var/www && php cron.php key123 control_install'
*/2 * * * * screen -dmS scan_control bash -c 'cd /var/www && php cron.php key123 scan_control'
*/2 * * * * screen -dmS control_scan_servers bash -c 'cd /var/www && php cron.php key123 control_threads control_scan_servers'
*/5 * * * * screen -dmS control_scan_servers_route bash -c 'cd /var/www && php cron.php key123 control_threads control_scan_servers_route'
*/1 * * * * screen -dmS control_scan_servers_down bash -c 'cd /var/www && php cron.php key123 control_threads control_scan_servers_down'
*/60 * * * * screen -dmS control_scan_servers_admins bash -c 'cd /var/www && php cron.php key123 control_threads control_scan_servers_admins'
*/15 * * * * screen -dmS control_scan_servers_copy bash -c 'cd /var/www && php cron.php key123 control_threads control_scan_servers_copy'
*/5 * * * * screen -dmS graph_servers_day bash -c 'cd /var/www && php cron.php key123 threads graph_servers_day' 
*/5 * * * * screen -dmS graph_servers_hour bash -c 'cd /var/www && php cron.php key123 threads graph_servers_hour'
") 2>&1 | grep -v "no crontab" | sort | uniq | crontab -
chown root:crontab /var/spool/cron/crontabs/root

# Перезагружаем ${red}крон!${green} •"
service cron restart

# Перезагружаем ${red}Apache2${green} •"
service apache2 restart

# Устанавливаем EngineGP в каталог /var/www
cd ~
cd /var/www/
rm index.html
wget $MIRROR/files/debian/enginegamespanel.zip
unzip enginegamespanel.zip
rm enginegamespanel.zip
cd ~

# Выдаем права на файлы
chown -R www-data:www-data /var/www/
chmod -R 775 /var/www/

# Настраиваем время на сервере
echo "Europe/Moscow" > /etc/timezone
dpkg-reconfigure tzdata -f noninteractive
sudo sed -i -r 's~^;date\.timezone =$~date.timezone = "Europe/Moscow"~' /etc/php5/cli/php.ini
sudo sed -i -r 's~^;date\.timezone =$~date.timezone = "Europe/Moscow"~' /etc/php5/apache2/php.ini

# Создаем базу данных и загружаем дамп базы данных от EngineGP
wget $MIRROR/files/debian/enginegamespanel.sql
sed -i "s/mysqlp/${MYPASS}/g" /var/www/system/data/mysql.php
sed -i "s/enginegamespanel.ru/${IPv4}/g" /var/www/system/data/config.php
sed -i "s/enginegamespanel.ru/${IPv4}/g" /var/www/system/data/config.php
sed -i "s/enginegamespanel.ru/${IPv4}/g" /var/www/system/data/config.php
sed -i "s/127.0.0.1/${IPv4}/g" /var/www/system/data/web.php
sed -i "s/kgdfgjksad/${VP}/g" /var/www/system/data/web.php
sed -i "s/3cjXeqXSgy/${MYPASS}/g" /root/enginegamespanel.sql
sed -i "s/6xn2hKRQMG/${VP}/g" /root/enginegamespanel.sql
sed -i "s/domain.enginegamespanel.ru/${IPv4}/g" /root/enginegamespanel.sql
sed -i "s/194.67.204.131/${IPv41}/g" /root/enginegamespanel.sql
sed -i "s/passwords/${VP}/g" /root/enginegamespanel.sql
mysql -uroot -p$MYPASS -e "CREATE DATABASE panel CHARACTER SET utf8 COLLATE utf8_general_ci;"
mysql -u root -p$MYPASS panel < enginegamespanel.sql
rm enginegamespanel.sql

# Устанавливаем необходимые пакеты для серверной части​
apt-get install -y lsb-release
apt-get install -y lib32stdc++6
apt-get install -y libreadline5
if [ "$OS" = "" ]; then
	sudo dpkg --add-architecture i386
	sudo apt-get update 
	sudo apt-get install -y ia32-libs
	sudo apt-get install -y gcc-multilib
else
	cd /etc/apt/sources.list.d
	echo "deb http://old-releases.ubuntu.com/ubuntu/ raring main restricted universe multiverse" >ia32-libs-raring.list
	apt-get update
	apt-get install -y ia32-libs
	sudo apt-get install -y gcc-multilib
fi
apt-get install -y sudo screen htop nano tcpdump ethstatus ssh zip unzip mc qstat gdb lib32gcc1 nload ntpdate lsof
apt-get install -y lib32z1

# Подготавливаемся к установке Java 8
echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu precise main" >> /etc/apt/sources.list 
echo "deb-src http://ppa.launchpad.net/webupd8team/java/ubuntu precise main" >> /etc/apt/sources.list
echo debconf shared/accepted-oracle-license-v1-1 select true | debconf-set-selections
echo debconf shared/accepted-oracle-license-v1-1 seen true | debconf-set-selections	
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys EEA14886

# Обновляем пакеты
apt-get update	

# Устанавливаем Java 8
sudo apt-get -y install oracle-java8-installer

# Устанавливаем и настраиваем rclocal
rm rclocal; wget -O rclocal $MIRROR/files/debian/rclocal/rclocal.txt
sed -i '14d' /etc/rc.local
cat rclocal >> /etc/rc.local
touch /root/iptables_block
echo "UseDNS no" >> /etc/ssh/sshd_config
echo "UTC=no" >> /etc/default/rcS
rm -rf rclocal

# Устанавливаем и настраиваем iptables + geoip
sudo apt-get --yes --force-yes install xtables-addons-common
sudo apt-get --yes --force-yes install libtext-csv-xs-perl libxml-csv-perl libtext-csv-perl unzip
sudo mkdir -p /usr/share/xt_geoip/
mkdir geoiptmp
cd geoiptmp
/usr/lib/xtables-addons/xt_geoip_dl
sudo /usr/lib/xtables-addons/xt_geoip_build GeoIPv6.csv GeoIPCountryWhois.csv -D /usr/share/xt_geoip
cd ~
rm -rf geoiptmp

# Включаем Nginx для модуля FastDL
rm nginx; wget -O nginx $MIRROR/files/debian/nginx/nginx.txt
service apache2 stop
apt-get install -y nginx
mkdir -p /var/nginx/ 
rm -rf /etc/nginx/nginx.conf
mv nginx /etc/nginx/nginx.conf
service nginx restart
service apache2 start
rm -rf nginx

# Устанавливаем и настраиваем ProFTPd
rm proftpd; wget -O proftpd $MIRROR/files/debian/proftpd/proftpd.txt
rm proftpd_modules; wget -O proftpd_modules $MIRROR/files/debian/proftpd/proftpd_modules.txt
rm proftpd_sql; wget -O proftpd_sql $MIRROR/files/debian/proftpd/proftpd_sql.txt
echo PURGE | debconf-communicate proftpd-basic
echo proftpd-basic shared/proftpd/inetd_or_standalone select standalone | debconf-set-selections
apt-get install -y proftpd-basic proftpd-mod-mysql
rm -rf /etc/proftpd/proftpd.conf
rm -rf /etc/proftpd/modules.conf
rm -rf /etc/proftpd/sql.conf
mv proftpd /etc/proftpd/proftpd.conf
mv proftpd_modules /etc/proftpd/modules.conf
mv proftpd_sql /etc/proftpd/sql.conf
rm -rf proftpd
rm -rf proftpd_modules
rm -rf proftpd_sql
mkdir -p /copy /servers /servers/cs /servers/cssold /servers/css /servers/csgo /servers/samp /servers/crmp /servers/mta /servers/mc /path/steam /var/nginx
cd /path/steam && wget http://media.steampowered.com/client/steamcmd_linux.tar.gz && tar xvfz steamcmd_linux.tar.gz && rm steamcmd_linux.tar.gz
cd ~
groupmod -g 998 `cat /etc/group | grep :1000 | awk -F":" '{print $1}'`
groupadd -g 1000 servers;
chmod 711 /servers /servers/cs /servers/cssold /servers/css /servers/csgo /servers/samp /servers/crmp /servers/mta /servers/mc
chmod -R 755 /path
chmod -R 750 /copy /etc/proftpd
chmod -R 750 /etc/proftpd
chown root:servers /servers /servers/cs /servers/cssold /servers/css /servers/csgo /servers/samp /servers/crmp /servers/mta /servers/mc /path
chown root:root /copy
rm proftpd_sqldump; wget -O proftpd_sqldump $MIRROR/files/debian/proftpd/proftpd_sqldump.txt
mysql -uroot -p$MYPASS -e "CREATE DATABASE ftp;";
mysql -uroot -p$MYPASS -e "CREATE USER 'ftp'@'localhost' IDENTIFIED BY '$MYPASS2';";#
mysql -uroot -p$MYPASS -e "GRANT ALL PRIVILEGES ON ftp . * TO 'ftp'@'localhost';";
mysql -uroot -p$MYPASS ftp < proftpd_sqldump;
rm -rf proftpd_sqldump
sed -i 's/passwdfor/'$MYPASS'/g' /etc/proftpd/sql.conf

# Перезагружаем FTP MySQL
service proftpd restart

# Обновляем пакеты и веб-сервисы
apt-get update
service restart apache2
service mysql restart
ln -s /usr/share/phpmyadmin /var/www/pma

# Сохраняем данные
echo "Данные для входа в панель:">>$SAVE
echo "Адрес: http://$IPv4/">>$SAVE
echo "Логин: admin">>$SAVE
echo "Пароль: admin1">>$SAVE
echo "">>$SAVE
echo "Данные от MySQL:">>$SAVE
echo "Логин: root">>$SAVE
echo "Пароль: $MYPASS">>$SAVE
echo "">>$SAVE
echo "Данные от FTP">>$SAVE
echo "Название БД: ftp">>$SAVE
echo "Логин: root">>$SAVE
echo "Пароль: $MYPASS2">>$SAVE

# Выводим пользователю информацию
echo "Данные для входа, можно посмотреть в файле: /root/enginegp.txt"