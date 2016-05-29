#/bin/bash

mySqlPassword=$1
insertValue=$2
zabbixServer=$3


install_nginx() {
	yum install wget -y
	cd /tmp
	for ((n=1;n<=5;n++))
		do
			wget http://nginx.org/download/nginx-1.9.5.tar.gz 
			if [[ $? -eq 0 ]];then
				break
			else
				continue
			fi
		done
	tar -xvzf nginx-1.9.5.tar.gz 
	cd nginx-1.9.5 
	yum install gcc -y
	yum install pcre pcre-devel zlib zlib-devel -y 
	./configure  
	make 
	make install 
}



nginx_init() {
cat > /etc/init.d/nginx <<EOF
#!/bin/sh
#
# nginx - this script starts and stops the nginx daemon
#
# chkconfig:   - 85 15
# description:  NGINX is an HTTP(S) server, HTTP(S) reverse \
#               proxy and IMAP/POP3 proxy server
# processname: nginx
# baseDir:     /usr/local/nginx
# config:      /usr/local/nginx/conf/nginx
# pidfile:     /usr/local/nginx/logs/nginx.pid

# Source function library.
. /etc/rc.d/init.d/functions

# Source networking configuration.
. /etc/sysconfig/network

# Check that networking is up.
[ "\$NETWORKING" = "no" ] && exit 0

baseDir="/usr/local/nginx"
start() {
    \${baseDir}/sbin/nginx -c \${baseDir}/conf/nginx.conf
}

stop() {
    kill -QUIT \`cat \${baseDir}/logs/nginx.pid\`
}

restart() {
    stop
    sleep 2
    start
}

reload() {
    \${baseDir}/sbin/nginx -s reload
}


case "\$1" in
    start)
        start
        ;;
    stop)
       stop
        ;;
    restart)
        restart
        ;;
    reload)
        reload
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|reload}"
        exit 2
esac
EOF
}


disk_format() {
	cd /tmp
	for ((j=1;j<=3;j++))
	do
		wget http://mirrors.blob.core.chinacloudapi.cn/tools/vm-disk-utils-0.1.sh 
		if [[ -f /tmp/vm-disk-utils-0.1.sh ]]; then
			bash /tmp/vm-disk-utils-0.1.sh -b /var/lib/mysql -s
			if [[ $? -eq 0 ]]; then
				sed -i 's/disk1//' /etc/fstab
				umount /var/lib/mysql/disk1
				mount /dev/md0 /var/lib/mysql
				chown -R mysql:mysql /var/lib/mysql
			fi
			break
		else
			echo "download vm-disk-utils-0.1.sh failed. try again."
			continue
		fi
	done
		
}

post_verify() {
	#start mysql,httpd
	service mysqld start  #for 6.x CentOS
	service mariadb start #for 7.x CentOS
	service httpd start

	#set mysql root password
	mysqladmin -uroot password "$mySqlPassword" 2> /dev/null

	#restart mysql
	service mysqld restart   #for 6.x CentOS
	service mariadb restart  #for 7.x CentOS

	#auto-start 
	chkconfig mysqld on
	chkconfig mariadb on
	chkconfig httpd on
	chkconfig firewalld off
	chkconfig iptables off
	service iptables stop
	service firewalld stop

#create test php page
cat > /var/www/html/info.php <<EOF
<?php
phpinfo();
?>
EOF

#create test php-mysql page
cat > /var/www/html/mysql.php <<EOF
<?php
\$conn = mysql_connect('localhost', 'root', '$mySqlPassword');
if (!\$conn) {
    die('Could not connect:' . mysql_error());
}
echo 'Connected to MySQL sucessfully!';

if(mysql_query("create database testdb")){
    echo "    Created database testdb successfully!";
}else{
    echo "    Database testdb already exists!";
}

\$db_selected = mysql_select_db('testdb',\$conn);

if(mysql_query("create table test01(name varchar(10))")){
    echo "    Created table test01 successfuly!";
}else{
    echo "    Table test01 already exists!";
}

if(mysql_query("insert into test01 values ('$insertValue')")){
    echo "    Inserted value $insertValue into test01 successfully!";
}else{
    echo "    Inserted value $insertValue into test01 failed!";
}

\$result = mysql_query("select * from testdb.test01");
while(\$row = mysql_fetch_array(\$result))
{
echo "    Welcome ";
echo \$row["name"];
echo "!!!";
}

mysql_close(\$conn)
?>
EOF

}


install_zabbix() {
	#install zabbix agent
	cd /tmp
	yum install -y gcc wget > /dev/null
	for((n=1;n<=5;n++))
		do
			wget http://jaist.dl.sourceforge.net/project/zabbix/ZABBIX%20Latest%20Stable/2.2.5/zabbix-2.2.5.tar.gz
			if [[ $? -eq 0 ]];then
				break
			else
				continue
			fi
		done
	tar zxvf zabbix-2.2.5.tar.gz
	cd zabbix-2.2.5
	groupadd zabbix
	useradd zabbix -g zabbix -s /sbin/nologin
	mkdir -p /usr/local/zabbix
	./configure --prefix=/usr/local/zabbix --enable-agent
	make install > /dev/null
	cp misc/init.d/fedora/core/zabbix_agentd /etc/init.d/
	sed -i 's/BASEDIR=\/usr\/local/BASEDIR=\/usr\/local\/zabbix/g' /etc/init.d/zabbix_agentd
	sed -i '$azabbix-agent    10050/tcp\nzabbix-agent    10050/udp' /etc/services
	sed -i '/^LogFile/s/tmp/var\/log/' /usr/local/zabbix/etc/zabbix_agentd.conf
	hostName=`hostname`
	sed -i "s/^Hostname=Zabbix server/Hostname=$hostName/" /usr/local/zabbix/etc/zabbix_agentd.conf
	if [[ $zabbixServer =~ ([0-9]{1,3}.){3}[0-9]{1,3} ]];then
		sed -i "s/^Server=127.0.0.1/Server=$zabbixServer/" /usr/local/zabbix/etc/zabbix_agentd.conf
		sed -i "s/^ServerActive=127.0.0.1/ServerActive=$zabbixServer/" /usr/local/zabbix/etc/zabbix_agentd.conf
		sed -i "s/^Server=127.0.0.1/Server=$zabbixServer/" /usr/local/zabbix/etc/zabbix_agent.conf
	fi
	touch /var/log/zabbix_agentd.log
	chown zabbix:zabbix /var/log/zabbix_agentd.log

	#start zabbix agent
	chkconfig --add zabbix_agentd
	chkconfig zabbix_agentd on
	/etc/init.d/zabbix_agentd start

}



#too slow to get the package from mysql source, hence using mariadb instead
setenforce 0
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/sysconfig/selinux
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config

#nginx related
install_nginx
#make nginx to be the reverse proxy server
sed -i '/^http/a upstream lamp {\n    server 127.0.0.1:8080;\n    }' /usr/local/nginx/conf/nginx.conf
sed -i 's/^upstream/    upstream/' /usr/local/nginx/conf/nginx.conf
sed -i '/[^#]        index/a\\t    proxy_pass http://lamp;' /usr/local/nginx/conf/nginx.conf
/usr/local/nginx/sbin/nginx -c /usr/local/nginx/conf/nginx.conf
nginx_init
chmod +x /etc/init.d/nginx 
chkconfig nginx on


#lamp related
yum install mysql-server -y
yum install mariadb-server -y 
yum install httpd php php-mysql -y
sed -i 's/^Listen 80/Listen 8080/' /etc/httpd/conf/httpd.conf


disk_format
post_verify
install_zabbix



