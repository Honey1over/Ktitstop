--- Перезагружаем днс на HQ-SRV - systemctl restart named



1) Установка Samba на BR-SRV:

 

- dnf install samba* krb5* -y

- sudo mv /etc/samba/smb.conf /etc/samba/smb.conf.bak

- sudo mv /etc/krb5.conf /etc/krb5.conf.bak

- nano /etc/krb5.conf.d/crypto-policies



--- Для этого ставим курсор на существующую строчку permitted_enctypes,

нажимаем CTRL+K и три раза CTRL+U. После этого изменяем начало первых

двух строчек:



--- default_tgs_enctypes = ...

--- default_tkt_enctypes = ...

--- permitted_enctypes = ...



- samba-tool domain provision --use-rfc2307 --interactive

Далее на моменте DNS backend пишем “NONE”. Затем указываем

пароль администратора: P@ssw0rd



- cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

- nano /etc/krb5.conf

В realms добавляем kdc:

[realms]

... 

	...

	kdc = br-srv.au-team.irpo



- systemctl enable --now samba

Если запустить службы smbnmb winbind krb5kdc, то присоединить HQ-CLI к домену не получится. Решение – перезапуск BR-SRV.



- kinit administrator@AU-TEAM.IRPO (P@ssw0rd)



Переходим на HQ-CLI, переходим в root (sudo -i) и пишем:

### echo “<ip-адрес br-srv> au-team.irpo” >> /etc/hosts 

- echo “172.30.100.10 au-team.irpo” >> /etc/hosts

### echo 172.30.100.10 au-team.irpo >> /etc/hosts 

- realm join -U -v Administrator@AU-TEAM.IRPO (P@ssw0rd)



Возвращаемся на BR-SRV. Далее создаем группу hq и добавляем в нее

всех созданных пользователей.



- samba-tool group add hq

- for i in {1..5}; do samba-tool user add hquser$i P@ssw0rd; samba-tool group addmembers hq hquser$i; done

Проверяем: Должен отобразиться список пользователей

- samba-tool group listmembers hq



Переходим на HQ-CLI

- nano /etc/sssd/sssd.conf

Меняем значение ad_server на br-srv.au-team.irpo



- systemctl restart sssd 

- nano /etc/krb5.conf

--- Приводим файл к следующему виду, добавив строки:



[realms]

AU-TEAM.IRPO = {  

     kdc = br-srv.au-team.irpo

     admin_server = br-srv.au-team.irpo

}



[domain realm]

.au-team.irpo = AU-TEAM.IRPO

au-team.irpo = AU-TEAM.IRPO



Далее переходим в «Настройки» - «Сетевые учетные записи».

Выбираем Kerberos, вводим administrator@AU-TEAM.IRPO и P@ssw0rd.



- sss_cache -E

- visudo

Пишем в файл следующую строку:

- %hq@au-team.irpo ALL=(ALL) /bin/cat, /bin/grep, /bin/id

Проверяем:

- id hquser1@AU-TEAM.IRPO

- su - hquser1@AU-TEAM.IRPO

- sudo cat /etc/hosts | grep au-team

- id

- exit



2) Конфигурация файлового хранилища на HQ-SRV:

В VMWare нажимаем сверху ПКМ на HQ-SRV, выбираем последний пункт Settings и нажимаем кнопку add. Выбираем Hard Drive.

Типдиска -SATA, “Create anew virtualdisk”, Maximumdisk size -1.В имени диска меняем цифру на конце на 10,11 соответственно для 2 дисков.

Нажимаем Finish.



Проверяем наличие дисков командой. Должны быть sdb, sdc.

- lsblk



- fdisk /dev/sdb

g

n

Жмем Enter 3 раза

W

Далее проделываем тоже самое для диска sdc.



- lsblk

- mdadm --create /dev/md0 --level=0 --raid-device=2 /dev/sdb /dev/sdc

- lsblk



- mdadm --detail --scan --verbose >> /etc/mdadm.conf

- mkfs.ext4 /dev/md0

- mkdir /raid

- nano /etc/fstab

В конец добавляем следующую строчку:

- /dev/md0	/raid	ext4	defaults	0 0



- systemctl daemon-reload 

- mount -a

Проверяем:

- df -h



3) Настройка сервера сетевой файловой системы (nfs) на HQ-SRV:

- dnf install nfs4-acl-tools -y

- mkdir /raid/nfs

- chown nobody:nobody /raid/nfs

- chmod 777 /raid/nfs

- nano /etc/exports



Добавляем в него следующую строчку:

- /raid/nfs	192.168.200.0/28 (rw)



- exportfs -a

- systemctl enable --now nfs-server



Переходим на HQ-CLI:

- mkdir /mnt/nfs

- nano /etc/fstab

Добавляем следующую строчку:

### [ip.address.hq-srv.100]:/raid/nfs /mnt/nfs nfs auto 0 0

- 192.168.100.10:/raid/nfs /mnt/nfs nfs auto0 0

- mount -a

Проверяем:

- df -h



4) Служба сетевого времени (chrony)

На ISP:

- nano /etc/chrony.conf



комментируем первые 3 сервера (ntp1-3) и пишем:

local stratum 5

allow 0/0

hwtimestamp *



- systemctl restart chronyd

Проверяем:

- chronyc sources



На HQ-SRV,HQ-CLI,BR-RTR,BR-SRV:

- nano /etc/chrony.conf

Комментируем все сервера и добавляем созданный:

###[ip.address.isp_ens34] iburst prefer

- server 172.16.4.1 iburst prefer



Далее перезапускаем сервис:

- systemctl restart chronyd

Проверяем:

- chronyc sources



Отключаем SELINUX на всех устройствах кроме HQ-CLI.

- nano /etc/selinux/config

Меняем параметр SELINUX на disabled > reboot

HQ-SRV:

- systemctl restart named

HQ-SRV, BR-SRV:

- nano /etc/ssh/sshd_config

Поменять порт 2024 на 2026

- semanage port -a -t ssh_port_t -p 2026

- semanage port -m -t ssh_port_t -p 2026

- systemctl restart sshd



5) Установка ansible на сервере BR-SRV

- nano /etc/ansible/demo.ini



### [HQ-SRV]

### <ip-адрес hq-srv.100> ansible_user=sshuser ansible_port=2026

### [HQ-CLI]

### <ip-адрес hq-cli> ansible_user=username

### [HQ-RTR]

### <ip-адрес hq-rtr_ens34.100> ansible_user=net_admin

### [BR-RTR]

### <ip-адрес br-rtr_ens34> ansible_user=net_admin



[HQ-SRV]

192.168.100.10 ansible_user=sshuser ansible_port=2026

[HQ-CLI]

192.168.200.2 ansible_user=username

[HQ-RTR]

192.168.100.1 ansible_user=net_admin

[BR-RTR]

172.30.100.1 ansible_user=net_admin



- ssh-keygen -t rsa (пароль от sshuser, username - P@ssw0rd, net_admin - P@$$w0rd)

- ssh-copy-id -p 2026 sshuser@192.168.100.10

- ssh-copy-id username@192.168.200.2

- ssh-copy-id net_admin@192.168.100.1

- ssh-copy-id net_admin@172.30.100.1



- nano /etc/ansible/ansible.cfg



[defaults]

Inventory = /etc/ansible/demo.ini

ask_pass = False

host_key_checking = False

interpreter_python=/usr/bin/python



Проверяем настройку:

- ansible -m ping all



6) Развертывание приложений в Docker на сервере BR-SRV:

Перед развертыванием выполняем монтирование ISO образа с необходимыми Docker-образами. Для этого переходим через VMWare WorkStation в настройки виртуальной машины. Там выбираем CD/DVD driver 1 > Use ISO image file > Browse > [DATA] > Additional.iso > Open < OK.

- CD/DVD driver 1 > Location > Local Client > Use ISO image file > Browse > Additional.iso > Open < OK.

- скачать образ: https://disk.yandex.ru/d/0MGlkrp2B9nXDw

- Установить Additional.iso > в Браузере вводим IP стенда > Storage > Datastore browser > Upload > загружаем образ.



- mount /dev/cdrom /mnt

- dnf install docker-ce docker-compose -y

- systemctl enable --now docker

- docker --version

- docker load < /mnt/docker/site_latest.tar

- docker load < /mnt/docker/mariadb_latest.tar

Проверка:

- docker images

- nano site.yml



services:

  db:

    image: mariadb:10.11

    container_name: db

    environment:

      MARIADB_DATABASE: testdb

      MARIADB_USER: test

      MARIADB_PASSWORD: Passw0rd

      MARIADB_ROOT_PASSWORD: Passw0rd

    volumes:

      - db_data:/var/lib/mysql

    restart: unless-stopped

  testapp:

    image: site

    container_name: testapp

    environment:

      DB_TYPE: maria

      DB_HOST: db

      DB_NAME: testdb

      DB_USER: test

      DB_PASS: Passw0rd

      DB_PORT: 3306

    ports:

      - "8080:8000"

    depends_on:

      - db

    restart: unless-stopped

volumes:

  db_data:



- docker-compose -f site.yml up -d



Далее переходим на HQ-CLI, заходим в браузер и вводим в адресную строку: 

### <ip-адрес br-srv_ens33>:8080.

- 172.30.100.10:8080.



7) Развертывание веб приложения на сервере HQ-SRV:

Перед развертыванием выполняем монтирование ISO образа с необходимыми Docker-образами. Для этого переходим через VMWare WorkStation в настройки виртуальной машины. Там выбираем CD/DVD driver 1 > Use ISO image file > Browse > [DATA] > Additional.iso > Open < OK.

- CD/DVD driver 1 > Location > Local Client > Use ISO image file > Browse > Additional.iso > Open < OK.

- скачать образ: https://disk.yandex.ru/d/0MGlkrp2B9nXDw

- Установить Additional.iso > в Браузере вводим IP стенда > Storage > Datastore brpwser > Upload > загружаем образ.



- mount /dev/cdrom /mnt

- dnf install mariadb-server httpd php php-mysqlnd php-cli -y

- systemctl enable --now mariadb httpd



HQ-CLI:

- вводим в Браузере - 192.168.100.10

HQ-SRV:

- mysql_secure_installation

- P@ssw0rd (n,n,y,y,y,y)

- mysql -u root -p (P@ssw0rd)

- CREATE USER 'web'@'localhost' IDENTIFIED BY 'P@ssw0rd';

- CREATE DATABASE webdb DEFAULT CHARACTER SET utf8mb4 DEFAULT COLLATE utf8mb4_unicode_ci;

- GRANT ALL PRIVILEGES ON webdb.* TO 'web'@'localhost';

- flush privileges;

- \q

- mysql -u root -p webdb < /mnt/web/dump.sql

- cp /mnt/web/index.php /var/www/html

- cp /mnt/web/logo.png /var/www/html

- nano /var/www/html/index.php



$servername = 'localhost'

$username = 'web'

$password = 'P@ssw0rd'

$dbname = 'webdb'



- systemctl restart httpd

На HQ-CLI снова открываем в браузере:

### <ip-адрес hq-srv_ens33.100>

192.168.100.10.



HQ-SRV:

- nano /opt/dns/au-team.irpo

web    A       172.16.4.1

docker A       172.16.5.1  



- chmod -R 777 /opt/dns

ПРОВЕРЯЕМ КОНФИГУРАЦИЮ И ИСПРАВЛЯЕМ ОШИБКИ ЕСЛИ ЕСТЬ

- named-checkconf -z

- systemctl restart named



8) Статическая трансляция портов:

BR-RTR:

### iptables -t nat -A PREROUTING -p tcp -m tcp -d <ip-адрес br-rtr ens33>/28 --dport 8080 -j DNAT --to-destination <ip-адрес br-srv>:8080

- iptables -t nat -A PREROUTING -p tcp -m tcp -d 172.16.5.2/28 --dport 8080 -j DNAT --to-destination 172.30.100.10:8080

### iptables -t nat -A PREROUTING -p tcp -m tcp -d <ip-адрес br-rtr ens33>/28 --dport 2026 -j DNAT --to-destination <ip-адрес br-srv>:2026

- iptables -t nat -A PREROUTING -p tcp -m tcp -d 172.16.5.2/28 --dport 2026 -j DNAT --to-destination 172.30.100.10:2026

- iptables-save > /etc/sysconfig/iptables

### На hq-cli в браузере открываем <ip-адрес br-rtr ens33>:8080, должен открыться сайт как в задании 6.

### На hq-cli в браузере открываем 172.16.5.2:8080, должен открыться сайт как в задании 6.

HQ-SRV:

### ssh sshuser@<ip-адрес br-rtr ens33> -p 2026

- ssh sshuser@172.16.5.2 -p 2026, должно подключить к br-srv.



HQ-RTR:

### iptables -t nat -A PREROUTING -p tcp -m tcp -d <ip-адрес hq-rtr ens33>/28 --dport 8080 -j DNAT --to-destination <ip-адрес hq-srv.100>:80

- iptables -t nat -A PREROUTING -p tcp -m tcp -d 172.16.4.2/28 --dport 8080 -j DNAT --to-destination 192.168.100.10:80

### iptables -t nat -A PREROUTING -p tcp -m tcp -d <ip-адрес hq-rtr ens33>/28 --dport 2026 -j DNAT --to-destination <ip-адрес hq-srv.100>:2026

- iptables -t nat -A PREROUTING -p tcp -m tcp -d 172.16.4.2/28 --dport 2026 -j DNAT --to-destination 192.168.100.10:2026

- iptables-save > /etc/sysconfig/iptables

### На hq-cli в браузере открываем <ip-адрес hq-rtr ens33>:8080, должен открыться сайт как в задании 7.

### На hq-cli в браузере открываем 172.16.4.2:8080, должен открыться сайт как в задании 7.

BR-RTR:

### ssh sshuser@<ip-адрес hq-rtr ens33> -p 2026

- ssh sshuser@172.16.4.2 -p 2026, должно подключить к hq-srv.



9) Настройка веб-сервера nginx как обратный прокси-сервер на ISP:

- dnf install nginx -y 

- systemctl enable --now nginx 

- nano /etc/nginx/nginx.conf 

В файле комментируем созданный по умолчанию сервер и добавляем 

в него 2 других сервера:

server {

	listen 80;

	server_name docker.au-team.irpo;

 	location / {

		### proxy_pass http://<ip-адрес br-rtr_ens33>:8080;

		proxy_pass http://172.16.5.2:8080;

	}

}

server {

	listen 80;

	server_name web.au-team.irpo;

 	location / {

		### proxy_pass http://<ip-адрес hq-rtr_ens33>:8080;

		proxy_pass http://172.16.4.2:8080;

	}

}



- systemctl restart nginx

- nano /etc/selinux/config

Меняем параметр SELINUX на disabled > reboot

На hq-cli в браузере открываем docker.au-team.irpo, должен открыться сайт из задания 6.

Открываем web.au-team.irpo, там сайт из задания 7.



10) Настройка web-based аутентификации на ISP:

- dnf install httpd-tools -y

- htpasswd -c /etc/nginx/.htpasswd WEB (P@ssw0rd)

- nano /etc/nginx/nginx.conf

Добавляем строчки auth_basic на 2 сервере:

		auth_basic “Restricted Content”;

		### auth_basic Restricted Content;

		auth_basic_user_file /etc/nginx/.htpasswd;

Проверяем:

- nginx -t

- systemctl restart nginx

На hq-cli в браузере открываем web.au-team.irpo

логин - WEB, пароль - P@ssw0rd. Должен открыться сайт из задания 7.



11) Установка Яндекс Браузера:

Заходим в «Окно настройки РЕДОС», переходим во вкладку «Партнерские приложения» и нажимаем на Яндекс браузер. После загрузки нажимаем на клавишу WIN и выбираем «Другие приложения».

Переходим на вторую страницу и запускаем браузер.



















