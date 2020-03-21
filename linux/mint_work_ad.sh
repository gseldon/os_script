#!/bin/bash
#
d=$(date +%Y-%m-%d)
log=preinstall.log
int=$(ip link show | grep 'state UP' | grep eno | cut -d ' ' -f2 | cut -d ':' -f1)
uuid=$(egrep -E -m1 'UUID=\S' /etc/fstab | awk '{print $1}' | cut -d= -f2)
#===============================================
#Создаем временную папку
mkdir -p /tmp/preinstall-$d
cd /tmp/preinstall-$d
#===============================================
read -p "Введите hostname компьютера: " hostname
read -p "Введите логин доменного админстратора: " login
read -s -p "Введите пароль администратора: " pass
echo "Параметры скрипта" | tee -a ./$log
echo "Логин доменного администратора $login" | tee -a ./$log
echo "hostname компьютера $hostname.corp.npcmr.ru" | tee -a ./$log
echo -e "\e[32m Начинаем выполнять скрипт??" 
read -p "Нажми любую кнопку для продолжения"
#===============================================
echo "Включаем NTP" | tee -a ./$log
sudo timedatectl set-timezone Europe/Moscow
sudo timedatectl set-ntp true
sudo timedatectl status >> ./$log
echo -e "Задаем hostname/" | tee -a ./$log
sudo hostnamectl set-hostname $hostname
hostnamectl status | tee -a ./$log
#===============================================
echo -e "\e[32m Удаляем лишнее"
sudo apt purge -y   compiz* \
                    thunderbird* \
                    xfburn \
                    pidgin \
                    libreoffice-writer libreoffice-math libreoffice-impress libreoffice-draw libreoffice-calc libreoffice-base libreoffice-core \
                    transmission* \
                    rhythmbox \
                    rhythmbox-data \
                    rhythmbox-plugin-tray-icon \
                    rhythmbox-plugins \
                    gnome-orca
#===============================================
echo -e "\e[32m Добавляем репозитории"
sudo add-apt-repository -y ppa:graphics-drivers/ppa
#====
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys CB2DE8E5
echo "deb https://download.onlyoffice.com/repo/debian squeeze main" >> /etc/apt/sources.list
#====
sudo add-apt-repository ppa:alexlarsson/flatpak
sudo sed -i 's/false/true/g' /etc/apt/apt.conf.d/00recommends
#===============================================
echo -e "\e[32m Скачиваем файлы требуемые для установки"
wget --output-document freeoffice-x64-2018.deb https://www.freeoffice.com/download.php?filename=https://www.softmaker.net/down/softmaker-freeoffice-2018_974-01_amd64.deb
wget https://github.com/BeyondTrust/pbis-open/releases/download/9.1.0/pbis-open-9.1.0.551.linux.x86_64.deb.sh
#Установка
dpkg -i ./freeoffice-*
sudo /usr/share/freeoffice2018/add_apt_repo.sh
sudo sh ./pbis-open-*.sh

echo -e "\e[32m Проверка обновлений и обновение"
sudo apt update --fix-missing &&  sudo apt upgrade -y

#Установка дополнительного ПО
sudo apt install -f -y mc \
                    htop \
                    fonts-crosextra-carlito fonts-crosextra-caladea \
                    vlc \
                    git \
                    vim vim-syntax-docker \
                    bash-completion \
                    flatpak \
                    zabbix-agent \
                    evolution \
                    samba \
                    screenfetch \
                    openssh-server
echo -e "\e[32m Настройка пользователя"
#Настройка пользователя
echo "PS1='\[\e[1;31m\][\u@\h \W]\$\[\e[0m\]'" >> /root/.bashrc
#Настройка zabbix
systemctl enable zabbix-agent.service
echo "" > /etc/zabbix/zabbix_agentd.conf
echo "PidFile=/var/run/zabbix/zabbix_agentd.pid" >> /etc/zabbix/zabbix_agentd.conf
echo "LogFileSize=0" >> /etc/zabbix/zabbix_agentd.conf
echo "Server=zabbix.corp.npcmr.ru" >> /etc/zabbix/zabbix_agentd.conf
echo "HostnameItem=system.hostname" >> /etc/zabbix/zabbix_agentd.conf
echo "Include=/etc/zabbix/zabbix_agentd.conf.d/*.conf" >> /etc/zabbix/zabbix_agentd.conf
#Ввод в домен
#Подготовка ввода в домен
sudo /opt/pbis/bin/config UserDomainPrefix corp
sudo /opt/pbis/bin/config AssumeDefaultDomain True
sudo /opt/pbis/bin/config LoginShellTemplate /bin/bash
sudo /opt/pbis/bin/config HomeDirTemplate %H/%D/%U
echo -e "\e[36m Параметры первого входа на компьютер" | tee -a ./$log
sudo /opt/pbis/bin/config --dump | tee -a ./$log
#Добавление SUDO
echo -e "\e[32m Прописываем группы в SUDO"
sudo echo -n '%local_sudoers ALL=(ALL) ALL' > /etc/sudoers.d/01local_sudoers
sudo echo -n '%Администраторы^домена ALL=(ALL) ALL' > /etc/sudoers.d/00domaine_admin
sudo chmod 0600 /etc/sudoers.d/*
#Ввод в домен
echo -e "\e[32m Ввод в домен"
sudo /opt/pbis/bin/domainjoin-cli join corp.npcmr.ru $login $pass
sudo domainjoin-cli query | tee -a ./$log
#Настройка apparmor под новый HOME
echo -n "@{HOMEDIRS}+=/home/CORP/" >> /etc/apparmor.d/tunables/home.d/ubuntu
echo "AllowGroups linux_ssh_ad_access" >> /etc/ssh/sshd_config
# правка /etc/nsswitch.conf
cp /etc/nsswitch.conf /etc/nsswitch.conf.bak
sudo sed -i 's/hosts: .*/hosts:     files dns mdns4_minimal [NOTFOUND=return] myhostname/' /etc/nsswitch.conf
#Прописываем search corp.npcmr.ru
systemd-resolve --interface $int: --set-domain=corp.npcmr.ru
#Настройка SSH на АРМ
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
sudo sed -i 's/#PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config 
sudo sed -i 's/#LoginGraceTime .*/LoginGraceTime 60/' /etc/ssh/sshd_config
sudo sed -i 's/#ClientAliveInterval .*/ClientAliveInterval 300/' /etc/ssh/sshd_config
sudo sed -i 's/#MaxSessions .*/MaxSessions 2/' /etc/ssh/sshd_config
sudo sed -i 's/#MaxAuthTries .*/MaxAuthTries 2/' /etc/ssh/sshd_config
#
echo -e "\e[32m Настройка uwf" 
ufw allow from 172.17.101.0/24 to any app openSSH
ufw allow from 10.2.20.0/22 to any app openSSH
ufw allow from 172.17.101.0/24 to any app Samba
ufw allow from 172.17.101.0/24 to any port 10050
ufw allow from 172.17.101.0/24 to any port 161
ufw enable
ufw status numbered | tee -a ./$log
#Приборка и перезагрузка
sudo apt autoremove -y
clear
screenfetch
echo ""
echo ""
echo ""
echo -e "\e[32m Скрипт закончил свою работу"
echo -e "\e[31m Не забудь!"
echo -e "\e[33m 1) Проверить работу с доменом .local в /etc/nsswitch.conf"
nslookup eris.local | grep -m1 -A1 eris.local
nslookup npc.local | grep -m1 -A1 npc.local
echo -e "\e[33m 2) Выставить язык, по просьбе пользователя." 
echo -e "\e[33m 3) Выставить выбор пользователей при входе"
echo -e "\e[33m 4) Настроить выбор администраторов в GUI" 
echo -e "\e[31m Нажми любую кнопку для перезагрузки компьютер??"
echo ""
echo -e "\e[31m \e[5mВНИМАНИЕ. История будет очищена!" 
read -p "_"
sudo rm -fr /tmp/preinstall-*
history -c
sudo shutdown -r now