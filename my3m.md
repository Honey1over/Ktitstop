1) импорт пользователей BR_SRV
mount /dev/cdrom /mnt если не делал
cat /mnt/Users.csv проверка
nano import.sh
#!/bin/bash
tail -n +2 /mnt/Users.csv | while IFS=';' read -r firstName lastName _ _ ou _ _ _ _ password
do
  if ! samba-tool ou list | grep -q "OU=$ou"; then
  samba-tool ou create "OU=$ou"
  fi
  samba-tool user create "${firstName}${lastName}" "$password" \
  --userou="OU=$ou"
done

chmod +x import.sh
./import.sh

2) сертификации на HQ_SRV:
dnf install openssl-gost-engine
openssl-switch-config gost активируем
update-crypto-policies --set GOST-ONLY:GOST
update-crypto-policies --show проверяем политики шифрования
openssl genpkey -algorithm gost2012_256 -pkeyopt paramset:A -out CA.key закрытый ключ
самоподписный сертификат
#openssl req -new -x509 -md_gost12_256 -days 365 -key CA.key -out CA.crt -subj "/C=RU/ST=Russia/L=Kazan/O=MCK-KTITS/OU=MCK-KTITS CA/CN=MCK-KTITS CA Root"
openssl req -new -x509 -md_gost12_256 -days 365 -key CA.key -out CA.crt -subj /C=RU/ST=Russia/L=Kazan/O=MCK-KTITS/OU=MCK-KTITS CA/CN=MCK-KTITS CA Root
закрытый ключ для веб-серверов:
openssl genpkey -algorithm gost2012_256 -pkeyopt paramset:A -out au-team.irpo.key
файл расширений:
nano au-team.irpo.ext
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment,
dataEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = au-team.irpo
DNS.2 = docker.au-team.irpo
DNS.3 = web.au-team.irpo
IP.1 = 172.16.1.2
IP.2 = 172.16.2.2

запрос на сертификат:
#openssl req -new -md_gost12_256 -key au-team.irpo.key -out au-team.irpo.csr -subj "/C=RU/L=Kazan/O=AU-TEAM Site GOST/CN=*.au-team.irpo"
openssl req -new -md_gost12_256 -key au-team.irpo.key -out au-team.irpo.csr -subj /C=RU/L=Kazan/O=AU-TEAM Site GOST/CN=*.au-team.irpo
сертификат для веб серверов:
penssl x509 -req -in au-team.irpo.csr -CA CA.crt -CAkey CA.key - CAcreateserial -out au-team.irpo.crt -days 30 -extfile au-team.irpo.ext
cat au-team.irpo.crt CA.crt > fullchain.crt цепочка сертификатов

openssl-switch-config default обратно 
update-crypto-policies --set DEFAULT
mkdir -p /home/sshuser/certs для хранения сертификтов

cp fullchain.crt au-team.irpo.key  CA.crt /home/sshuser/certs
chmod 755 -R /home/sshuser/certs

ISP:
dnf install openssl-gost-engine
openssl-switch-config gost
update-crypto-policies --set GOST-ONLY:GOST
update-crypto-policies –show
mkdir -p /etc/ssl/site
scp -P 2026 sshuser@172.16.1.2:/home/sshuser/certs/* /etc/ssl/site

server {
listen 443 ssl;
server_name docker.au-team.irpo;
ssl_certificate /etc/ssl/site/fullchain.crt;
ssl_certificate_key /etc/ssl/site/au-team.irpo.key;
ssl_ciphers GOST2012-GOST8912-GOST8912:HIGH:MEDIUM;
ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
ssl_prefer_server_ciphers on;
location / {
proxy_pass http://172.16.2.2:8080;
}
}
server {
listen 443 ssl;
server_name web.au-team.irpo;
ssl_certificate /etc/ssl/site/fullchain.crt;
ssl_certificate_key /etc/ssl/site/au-team.irpo.key;
ssl_ciphers GOST2012-GOST8912-GOST8912:HIGH:MEDIUM;
ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
ssl_prefer_server_ciphers on;
location / {
auth_basic "Restricted Content";
auth_basic_user_file /etc/nginx/.htpasswd;
proxy_pass http://172.16.1.2:8080;

nginx -t
systemctl restart nginx

HQ-CLI:
mkdir /add
mount /dev/cdrom /add
cp -r /add/cryptopro/linux-amd64/ .
scp -P 2026 sshuser@192.168.100.2:/home/sshuser/certs/CA.crt /home/username       ip checkni
chmod +x linux-amd64/*.sh
/linux-amd64/install_gui.sh
Далее -- выбрать все пакеты пробелом
 -- установить -- подтвердить -- лицензю ключ позже -- выход --
--найти интрументыкриптопро и открыть -- двигать мышь --
--Сертификаты -- выбрать доверенные корневые центры и установить -- добавить CA.crt -- ok
проверка на яндекс браузере

3) шифрования трафика на ip-туннеле:
dnf install strongswan -y
systemctl enable --now strongswan

на HQ-RTR: 
nano /etc/strongswan/swanctl/conf.d/swanctl.conf 
Добавляем конфигурацию IPSec:
nano /etc/strongswan/swanctl/conf.d/swanctl.conf
connections {
  my-tunnel {
   local_addrs = 172.16.1.2
   remote_addrs = 172.16.2.2
   local {
     auth = psk
   }
   remote {
     auth = psk
   }
   children {
    net {
     mode = transport
     esp_proposals = aes256-sha256
   }
  }
 }
}
secrets {
 ike-1 {
   secret = "P@ssw0rd"
 }
}

systemctl restart strongswan

BR-RTR:
nano /etc/strongswan/swanctl/conf.d/swanctl.conf
connections {
  my-tunnel {
  local_addrs = 172.16.2.2
  remote_addrs = 172.16.1.2
  local {
    auth = psk
  }
  remote {
    auth = psk
  }
  children {
   net {
    mode = transport
    esp_proposals = aes256-sha256
   }
  }
 }
}
secrets {
  ike-1 {
    secret = "P@ssw0rd"
  }
}

systemctl restart strongswan

swanctl --initiate -connections { 
 my-tunnel { 
  local_addrs  = 172.16.1.2 
  remote_addrs = 172.16.2.2 
  local { 
    auth = psk 
  } 
  remote { 
    auth = psk 
  } 
  children { 
   net { 
    mode = transport 
    esp_proposals = aes256-sha256 
   } 
  } 
 } 
} 
secrets { 
 ike-1 { 
   secret = "P@ssw0rd" 
 } 
}

systemctl restart strongswan 

на BR-RTR
nano /etc/strongswan/swanctl/conf.d/swanctl.conf 
Добавляем конфигурацию IPSec: 

connections { 
 my-tunnel { 
  local_addrs  = 172.16.2.2 
  remote_addrs = 172.16.1.2 
  local { 
    auth = psk 
  } 
  remote { 
    auth = psk 
  } 
  children { 
   net { 
    mode = transport 
    esp_proposals = aes256-sha256 
   } 
  } 
 } 
} 
secrets { 
 ike-1 { 
   secret = "P@ssw0rd" 
 } 
}

systemctl restart strongswan

Принудительно инициируем соединение (BR-RTR или HQ-RTR):
swanctl --initiate --child net 
swanctl --list-conns

с HQ-RTR:
tcpdump -i ens33 -n host 172.16.2.2 

4) межсетевой экран
HQ-RTR:
firewall-cmd --permanent --zone=external --change-interface=ens33
firewall-cmd --permanent --zone=internal --change-interface=ens34
firewall-cmd --permanent --zone=internal --change-interface=ens34.100
firewall-cmd --permanent --zone=internal --change-interface=ens34.200
firewall-cmd --permanent --zone=internal --add-interface=tun0
firewall-cmd --permanent --new-policy int-to-ext
firewall-cmd --permanent --policy int-to-ext --add-ingress-zone=internal
firewall-cmd --permanent --policy int-to-ext --add-egress-zone=external
firewall-cmd --permanent --policy int-to-ext --set-target=ACCEPT
firewall-cmd --permanent --zone=external --add-service=http
firewall-cmd --permanent --zone=external --add-service=https
firewall-cmd --permanent --zone=external --add-service=dns
firewall-cmd --permanent --zone=external --add-service=ntp
firewall-cmd --permanent --zone=external --add-port=2026/tcp
firewall-cmd --permanent --zone=external --add-port=8080/tcp
firewall-cmd --permanent --zone=external --add-protocol=gre
firewall-cmd --permanent --zone=external --add-port=500/udp
firewall-cmd --permanent --zone=external --add-port=4500/udp
firewall-cmd --permanent --zone=external --add-protocol=esp
firewall-cmd --permanent --zone=external --add-protocol=ah
firewall-cmd --permanent --zone=internal --add-protocol=ospf
firewall-cmd --permanent --zone=external --add-forward-port=port=2026:proto=tcp:toport=2026:toaddr=192.168.100.2
firewall-cmd --permanent --zone=external --add-forward-port=port=8080:proto=tcp:toport=80:toaddr=192.168.100.2
firewall-cmd --permanent --direct --add-passthrough ipv4 -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
firewall-cmd --reload

На BR-RTR:
firewall-cmd --permanent --zone=external --change-interface=ens33
firewall-cmd --permanent --zone=internal --change-interface=ens34
firewall-cmd --permanent --zone=internal --add-interface=tun0
firewall-cmd --permanent --new-policy int-to-ext
firewall-cmd --permanent --policy int-to-ext --add-ingress-zone=internal
firewall-cmd --permanent --policy int-to-ext --add-egress-zone=external
firewall-cmd --permanent --policy int-to-ext --set-target=ACCEPT
firewall-cmd --permanent --zone=external --add-service=http
firewall-cmd --permanent --zone=external --add-service=https
firewall-cmd --permanent --zone=external --add-service=dns
firewall-cmd --permanent --zone=external --add-service=ntp
firewall-cmd --permanent --zone=external --add-port=2026/tcp
firewall-cmd --permanent --zone=external --add-port=8080/tcp
firewall-cmd --permanent --zone=external --add-protocol=gre
firewall-cmd --permanent --zone=external --add-port=500/udp
firewall-cmd --permanent --zone=external --add-port=4500/udp
firewall-cmd --permanent --zone=external --add-protocol=esp
firewall-cmd --permanent --zone=external --add-protocol=ah
firewall-cmd --permanent --zone=internal --add-protocol=ospf
firewall-cmd --permanent --zone=external --add-forward-port=port=2026:proto=tcp:toport=2026:toaddr=172.30.100.2
firewall-cmd --permanent --zone=external --add-forward-port=port=8080:proto=tcp:toport=8080:toaddr=172.30.100.2
firewall-cmd --permanent --direct --add-passthrough ipv4 -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
firewall-cmd --reload

5) принт сервер HQ_SRV:
dnf install cups cups-pdf -y --nogpgcheck
systemctl enable --now cups
nano /etc/cups/cupsd.conf
В строке Listen localhost:631 меняем localhost на *:
В строках с доступом на сервер и с доступом на страницу админа
добавляем строки Allow all

systemctl restart cups
#lpadmin -p Cups-PDF -E -v cups-pdf:/ -m "CUPS-PDF_noopt.ppd"
lpadmin -p Cups-PDF -E -v cups-pdf:/ -m CUPS-PDF_noopt.ppd

HQ-CLI:
настройки -- принтеры -- добавить -- ввести ip HQ-SRV -- использовать по умолчанию

:) 6) логи rsyslog
сервер сбора логов на HQ-SRV:
nano -l /etc/rsyslog.conf
расскоментировать строки связанные с udp (module и  input): 29str
шаблон записи логов в opt и исключения hq-srv из записи в папку /opt: в конец
$template RemoteLogs,"/opt/%HOSTNAME%/%HOSTNAME%.log"
if $hostname != 'hq-srv' then {
    *.warning ?RemoteLogs
    & stop
}

на HQ-RTR, BR-RTR, BR-SRV: в конец
nano /etc/rsyslog.conf
*.warning						@192.168.100.2:514

На HQ-RTR, BR-RTR, BR-SRV, HQ-SRV:
systemctl restart rsyslog

HQ-SRV:
nano /etc/logrotate.d/remote_logs
/opt/*/*.log {
  weekly
  rotate 4
  compress
  minsize 10M
  missingok
  notifempty
  sharedscripts
  postrotate
    /usr/bin/systemctl kill -s HUP rsyslog.service >/dev/null 2>&1 || true
  endscript
}

На HQ-RTR, BR-RTR, BR-SRV, HQ-SRV перезапускаем службу logrotate:
systemctl restart logrotate

7) monitoring on HQ_SRV:
dnf install -y grafana prometheus prometheus-node_exporter --nogpgcheck
nano /etc/prometheus/prometheus.yml
- targets: ['localhost:9090','192.168.100.2:9100','172.30.100.2:9100']

systemctl enable --now grafana-server prometheus node_exporter

на BR-SRV
dnf install -y prometheus-node_exporter 
systemctl enable --now node_exporter

на HQ-CLI настройка grafana:
переходим по адресу http://192.168.100.2:3000 
admin:admin
новый пароль P@ssw0rd

Connections -- DataSource -- пишем Prometheus
В Connection http://localhost:9090 и добавить

Dashboard -- Dashboards -- «Create Dashboard» -- Import Dashbords -- 11074
-- выбрать Prometheus -- Import

домен мониторинга на HQ_SRV:
nano /opt/dns/au-team.irpo
mon A 192.168.100.2

systemctl restart named

HQ-CLI:
http://mon.au-team.irpo:3000 
 
8)
на BR-SRV
cp /mnt/playbook/get_hostname_address.yml /etc/ansible 
nano /etc/ansible/demo.ini 
[inventory]
hq-cli ansible_host=192.168.200.2 ansible_user=username
hq-srv ansible_host=192.168.100.2 ansible_port=2026 ansible_user=sshuser

nano /etc/ansible/get_hostname_address.yml
- name: Inventory of HQ-SRV and HQ-CLI
  hosts: inventory
  gather_facts: yes
  tasks: 
   - name: recieve data from host
     copy:
      dest: /etc/ansible/PC-INFO/{{ ansible_hostname }}.yml
      content: |
       Hostname: {{ ansible_hostname }}
       IP_Address: {{ ansible_default_ipv4.address }}
     delegate_to: localhost

mkdir -p /etc/ansible/PC-INFO 
cd /etc/ansible
ansible-playbook get_hostname_address.yml -i demo.ini 
ls PC-INFO/
cat PC-INFO/hq-cli.yml
cat PC-INFO/hq-srv.yml

9) HQ_SRV fail2ban:

dnf install fail2ban -y --nogpgcheck 
nano /etc/fail2ban/jail.local

[sshd] 
enabled = true 
port = 2026 
filter = sshd 
maxretry = 3 
bantime = 60 
findtime = 120

systemctl restart fail2ban
systemctl enable --now  fail2ban
fail2ban-client status sshd 
