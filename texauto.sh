#!/bin/bash

# ████████╗███████╗██╗  ██╗██████╗  ██████╗ ██████╗ ██████╗ ███████╗
# ╚══██╔══╝██╔════╝██║  ██║██╔══██╗██╔═══██╗██╔══██╗██╔══██╗██╔════╝
#    ██║   █████╗  ███████║██████╔╝██║   ██║██████╔╝██████╔╝█████╗  
#    ██║   ██╔══╝  ██╔══██║██╔═══╝ ██║   ██║██╔═══╝ ██╔══██╗██╔══╝  
#    ██║   ███████╗██║  ██║██║     ╚██████╔╝██║     ██║  ██║███████╗
#    ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝      ╚═════╝ ╚═╝     ╚═╝  ╚═╝╚══════╝

if [[ $EUID -ne 0 ]]; then
    echo -e "\033[38;2;0;191;255m\n✈️ Запустите скрипт с правами sudo!\033[0m\n"
    exit 1
fi

GRAD1='\033[38;2;0;191;255m'
GRAD2='\033[38;2;0;255;255m'
GRAD3='\033[38;2;0;255;191m'
RED='\033[1;38;5;196m'
NC='\033[0m'

TOTAL_STEPS=14
CURRENT_STEP=0
FQDN=""
PROTOCOL="http"
SSL_ENABLED=false
PORT_RANGE_START=30000
PORT_RANGE_END=30099
SWAP_ENABLED=false

error_exit() {
    echo -e "${RED}⛔ [ОШИБКА] $1${NC}"
    exit 1
}

show_progress() {
    local width=50
    local percent=$((CURRENT_STEP*100/TOTAL_STEPS))
    local filled=$((width*CURRENT_STEP/TOTAL_STEPS))
    local empty=$((width-filled))
    
    printf "${GRAD2}["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' ' '
    printf "] ${GRAD3}%3d%%${NC}\r" $percent
    sleep 0.2
}

update_progress() {
    ((CURRENT_STEP++))
    show_progress
}

header() {
    clear
    echo -e "${GRAD1}"
    echo "████████╗███████╗██╗  ██╗██████╗  ██████╗ ██████╗ ██████╗ ███████╗"
    echo "╚══██╔══╝██╔════╝██║  ██║██╔══██╗██╔═══██╗██╔══██╗██╔══██╗██╔════╝"
    echo "   ██║   █████╗  ███████║██████╔╝██║   ██║██████╔╝██████╔╝█████╗  "
    echo "   ██║   ██╔══╝  ██╔══██║██╔═══╝ ██║   ██║██╔═══╝ ██╔══██╗██╔══╝  "
    echo "   ██║   ███████╗██║  ██║██║     ╚██████╔╝██║     ██║  ██║███████╗"
    echo "   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝      ╚═════╝ ╚═╝     ╚═╝  ╚═╝╚══════╝"
    echo -e "${GRAD2}                     v3.0 by TEXSER${NC}"
    echo -e "${GRAD3}═══════════════════════════════════════════════${NC}"
    echo -e "Этап: ${GRAD1}$1${NC}"
    show_progress
}

system_update() {
    header "ОБНОВЛЕНИЕ СИСТЕМЫ"
    apt update -y >/dev/null 2>&1 && apt full-upgrade -y >/dev/null 2>&1 || error_exit "Ошибка обновления"
    update_progress
}

setup_swap() {
    header "НАСТРОЙКА SWAP"
    if [ "$SWAP_ENABLED" = true ]; then
        if ! swapon --show | grep -q "/swapfile"; then
            RAM_MB=$(free -m | awk '/Mem:/ {print $2}')
            SWAP_SIZE=$((RAM_MB/2))M
            
            fallocate -l $SWAP_SIZE /swapfile >/dev/null 2>&1 || error_exit "Ошибка создания swap"
            chmod 600 /swapfile
            mkswap /swapfile >/dev/null 2>&1 || error_exit "Ошибка инициализации swap"
            swapon /swapfile >/dev/null 2>&1 || error_exit "Ошибка активации swap"
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
            
            sysctl vm.swappiness=10 >/dev/null 2>&1
            sysctl vm.vfs_cache_pressure=50 >/dev/null 2>&1
            echo "vm.swappiness=10" >> /etc/sysctl.conf
            echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
        fi
    fi
    update_progress
}

install_core_deps() {
    header "УСТАНОВКА ОСНОВНЫХ ЗАВИСИМОСТЕЙ"
    apt install -y software-properties-common apt-transport-https ca-certificates \
    curl gnupg2 git unzip jq >/dev/null 2>&1 || error_exit "Ошибка установки"
    update_progress
}

add_php_repo() {
    header "ДОБАВЛЕНИЕ РЕПОЗИТОРИЯ PHP"
    add-apt-repository ppa:ondrej/php -y >/dev/null 2>&1 || error_exit "Ошибка добавления PPA"
    apt update >/dev/null 2>&1
    update_progress
}

install_php() {
    header "УСТАНОВКА PHP 8.2"
    apt install -y php8.2 php8.2-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} >/dev/null 2>&1 || error_exit "Ошибка установки PHP"
    update_progress
}

install_mariadb() {
    header "УСТАНОВКА MARIADB"
    apt install -y mariadb-server >/dev/null 2>&1 || error_exit "Ошибка установки MariaDB"
    systemctl start mariadb >/dev/null 2>&1
    systemctl enable mariadb >/dev/null 2>&1
    update_progress
}

install_nginx() {
    header "УСТАНОВКА NGINX"
    apt install -y nginx >/dev/null 2>&1 || error_exit "Ошибка установки Nginx"
    update_progress
}

install_certbot() {
    header "УСТАНОВКА CERTBOT"
    apt install -y certbot python3-certbot-nginx >/dev/null 2>&1 || error_exit "Ошибка установки Certbot"
    update_progress
}

install_composer() {
    header "УСТАНОВКА COMPOSER"
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer >/dev/null 2>&1 || error_exit "Ошибка установки Composer"
    update_progress
}

configure_firewall() {
    header "НАСТРОЙКА ФАЕРВОЛА"
    ufw allow ssh >/dev/null 2>&1
    ufw allow http >/dev/null 2>&1
    ufw allow https >/dev/null 2>&1
    ufw allow ${PORT_RANGE_START}:${PORT_RANGE_END}/tcp >/dev/null 2>&1
    ufw allow ${PORT_RANGE_START}:${PORT_RANGE_END}/udp >/dev/null 2>&1
    ufw --force enable >/dev/null 2>&1
    update_progress
}

setup_mysql() {
    header "НАСТРОЙКА БАЗЫ ДАННЫХ"
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY ''; FLUSH PRIVILEGES;" >/dev/null 2>&1
    
    mysql_secure_installation <<EOF >/dev/null 2>&1
n
y
y
y
y
EOF

    MYSQL_DB="pterodactyl"
    MYSQL_USER="pterodactyl"
    MYSQL_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 24)
    ADMIN_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 24)

    mysql -e "CREATE DATABASE ${MYSQL_DB};" >/dev/null 2>&1
    mysql -e "CREATE USER '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';" >/dev/null 2>&1
    mysql -e "GRANT ALL PRIVILEGES ON ${MYSQL_DB}.* TO '${MYSQL_USER}'@'localhost';" >/dev/null 2>&1
    mysql -e "FLUSH PRIVILEGES;" >/dev/null 2>&1
    update_progress
}

deploy_panel() {
    header "РАЗВЕРТЫВАНИЕ ПАНЕЛИ"
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    curl -sLo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz >/dev/null 2>&1
    tar -xzf panel.tar.gz >/dev/null 2>&1
    chmod -R 755 storage/* bootstrap/cache/

    cp .env.example .env
    composer install --no-dev --optimize-autoloader --no-interaction >/dev/null 2>&1

    php artisan key:generate --force >/dev/null 2>&1
    php artisan p:environment:setup --author=$FQDN --url=$PROTOCOL://$FQDN --timezone=UTC --cache=redis --session=database --queue=redis >/dev/null 2>&1
    php artisan p:environment:database --host=127.0.0.1 --port=3306 --database=$MYSQL_DB --username=$MYSQL_USER --password=$MYSQL_PASSWORD >/dev/null 2>&1
    php artisan migrate --seed --force >/dev/null 2>&1
    php artisan p:user:make --email=admin@$FQDN --username=admin --name=Admin --admin=1 --password=$ADMIN_PASSWORD >/dev/null 2>&1
    chown -R www-data:www-data /var/www/pterodactyl/* >/dev/null 2>&1
    update_progress
}

configure_web_server() {
    header "КОНФИГУРАЦИЯ WEB-СЕРВЕРА"
    rm -f /etc/nginx/sites-enabled/default >/dev/null 2>&1
    curl -sLo /etc/nginx/sites-available/pterodactyl.conf https://raw.githubusercontent.com/pterodactyl/panel/develop/.github/nginx.conf >/dev/null 2>&1
    sed -i "s/<domain>/$FQDN/g" /etc/nginx/sites-available/pterodactyl.conf >/dev/null 2>&1
    
    if [ "$SSL_ENABLED" = true ]; then
        certbot certonly --standalone -d $FQDN --non-interactive --agree-tos -m admin@$FQDN >/dev/null 2>&1
        sed -i "s/#ssl_certificate/ssl_certificate/g" /etc/nginx/sites-available/pterodactyl.conf >/dev/null 2>&1
    fi
    
    ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/ >/dev/null 2>&1
    systemctl restart nginx >/dev/null 2>&1
    update_progress
}

setup_infrastructure() {
    header "СОЗДАНИЕ ИНФРАСТРУКТУРЫ"
    COUNTRY=$(curl -s --retry 3 --max-time 5 ipapi.co/country_name || echo "Global")
    CPU_MODEL=$(lscpu | grep "Model name" | cut -d ':' -f2 | xargs | tr ' ' '-' | tr -d '()')
    
    php artisan p:location:make --short="$COUNTRY" --long="Auto Location" >/dev/null 2>&1
    LOCATION_ID=$(mysql -D pterodactyl -se "SELECT id FROM locations LIMIT 1;" 2>/dev/null)
    
    php artisan p:node:make --name="$CPU_MODEL-Node" --locationId=$LOCATION_ID --fqdn=$FQDN \
        --memory=$(( $(free -g | awk '/Mem:/ {print $2}')-1 )) --disk=$(( $(df -BG / | awk 'NR==2 {print $2}' | tr -d 'G')-10 )) \
        --memoryOverallocate=0 --diskOverallocate=0 --uploadSize=100 \
        --daemonBase=/var/lib/pterodactyl/volumes --ports=$PORT_RANGE_START-$PORT_RANGE_END >/dev/null 2>&1
    update_progress
}

install_wings() {
    header "УСТАНОВКА WINGS"
    curl -sLo /usr/local/bin/wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64 >/dev/null 2>&1
    chmod u+x /usr/local/bin/wings >/dev/null 2>&1

    NODE_TOKEN=$(mysql -D pterodactyl -se "SELECT daemon_token FROM nodes LIMIT 1;" 2>/dev/null)
    UUID=$(cat /proc/sys/kernel/random/uuid)

    mkdir -p /etc/pterodactyl
    cat > /etc/pterodactyl/config.yml <<EOL
debug: false
uuid: $UUID
token: $NODE_TOKEN
api:
  host: 0.0.0.0
  port: 8080
  ssl:
    enabled: $SSL_ENABLED
    certificate: /etc/letsencrypt/live/$FQDN/fullchain.pem
    key: /etc/letsencrypt/live/$FQDN/privkey.pem
system:
  data: /var/lib/pterodactyl/volumes
  sftp:
    port: 2022
container:
  port_range:
    - "$PORT_RANGE_START"
    - "$PORT_RANGE_END"
EOL

    systemctl enable wings >/dev/null 2>&1
    systemctl start wings >/dev/null 2>&1
    update_progress
}

finalize() {
    header "ФИНАЛЬНАЯ НАСТРОЙКА"
    (crontab -l 2>/dev/null; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -
    update_progress
    
    echo -e "\n${GRAD1}Установка успешно завершена!${NC}"
    echo -e "${GRAD2}Панель: ${GRAD3}$PROTOCOL://$FQDN"
    echo -e "${GRAD2}Логин: ${GRAD3}admin@$FQDN"
    echo -e "${GRAD2}Пароль: ${GRAD3}$ADMIN_PASSWORD${NC}"
    
    echo -e "\n${GRAD1}Сервер будет перезагружен через 10 секунд...${NC}"
    for i in {10..1}; do
        printf "${GRAD2}%2d секунд${NC}\r" $i
        sleep 1
    done
    shutdown -r now
}

main() {
    clear
    echo -e "${GRAD1}"
    echo "__                                      __              "
    echo "/\ \__                                  /\ \__           "
    echo "\ \ ,_\     __   __  _     __     __  __\ \ ,_\    ___   "
    echo " \ \ \/   /'__\`\/\ \/'\  /'__\`\  /\ \/\ \\ \ \/   / __\`\ "
    echo "  \ \ \_ /\  __/\/>  </ /\ \L\.\_\ \ \_\ \\ \ \_ /\ \L\ \\"
    echo "   \ \__\\\\ \____\/\_/\_\\\\ \__/.\_\\\\ \____/ \ \__\\\\ \____/"
    echo "    \/__/ \/____/\\//\\/_/ \\/__/\\/_/ \\/___/   \\/__/ \\/___/ "
    echo "                                                         "
    echo "                                                         "
    
    read -p "Создать SWAP файл? (y/n): " SWAP_CHOICE
    [[ "$SWAP_CHOICE" =~ [Yy] ]] && SWAP_ENABLED=true

    read -p "Введите домен или IP: " FQDN
    if [[ $FQDN =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        PROTOCOL="http"
    else
        PROTOCOL="https"
        SSL_ENABLED=true
    fi

    system_update
    setup_swap
    install_core_deps
    add_php_repo
    install_php
    install_mariadb
    install_nginx
    install_certbot
    install_composer
    configure_firewall
    setup_mysql
    deploy_panel
    configure_web_server
    setup_infrastructure
    install_wings
    finalize
}

main
