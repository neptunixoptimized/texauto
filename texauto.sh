#!/bin/bash

# __                                      __              
# /\ \__                                  /\ \__           
# \ \ ,_\     __   __  _     __     __  __\ \ ,_\    ___   
#  \ \ \/   /'__\`\/\ \/'\  /'__\`\  /\ \/\ \\ \ \/   / __\`\ 
#   \ \ \_ /\  __/\/>  </ /\ \L\.\_\ \ \_\ \\ \ \_ /\ \L\ \\
#    \ \__\\\\ \____\/\_/\_\\\\ \__/.\_\\\\ \____/ \ \__\\\\ \____/
#     \/__/ \/____/\\//\\/_/ \\/__/\\/_/ \\/___/   \\/__/ \\/___/ 
#                                                         
#                                                         

if [[ $EUID -ne 0 ]]; then
    echo -e "\033[38;2;0;191;255m\n✈️ Запустите скрипт с правами sudo!\033[0m\n"
    exit 1
fi

GRAD1='\033[38;2;0;191;255m'
GRAD2='\033[38;2;0;255;255m'
GRAD3='\033[38;2;0;255;191m'
RED='\033[1;38;5;196m'
NC='\033[0m'

FQDN=""
PROTOCOL="http"
SSL_ENABLED=false
PORT_RANGE_START=30000
PORT_RANGE_END=30099
SWAP_ENABLED=false

header() {
    echo -e "${GRAD1}\n╔════════════════════════════════════════════════════════╗\n║ $1\n╚════════════════════════════════════════════════════════╝${NC}"
}

progress_bar() {
    local duration=$1
    local chars=('▏' '▎' '▍' '▌' '▋' '▊' '▉' '█')
    for ((i=0; i<=duration; i++)); do
        printf "${GRAD2}["
        for ((j=0; j<i; j++)); do printf "█"; done
        printf "${chars[$RANDOM%8]}"
        for ((j=i; j<duration-1; j++)); do printf " "; done
        printf "] ${GRAD3}%3d%%${NC}\r" $((i*100/duration))
        sleep 0.1
    done
    printf "\n"
}

setup_swap() {
    header "НАСТРОЙКА SWAP"
    if [ "$SWAP_ENABLED" = true ]; then
        if ! swapon --show | grep -q "/swapfile"; then
            progress_bar 15
            RAM_MB=$(free -m | awk '/Mem:/ {print $2}')
            SWAP_SIZE=$((RAM_MB/2))M
            fallocate -l $SWAP_SIZE /swapfile || error_exit "Ошибка создания swap"
            chmod 600 /swapfile
            mkswap /swapfile >/dev/null || error_exit "Ошибка инициализации swap"
            swapon /swapfile || error_exit "Ошибка активации swap"
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
            sysctl vm.swappiness=10
            sysctl vm.vfs_cache_pressure=50
            echo "vm.swappiness=10" >> /etc/sysctl.conf
            echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
        fi
    fi
}

configure_resources() {
    RAM_GB=$(free -g | awk '/Mem:/ {print $2-1}')
    DISK_GB=$(df -BG / | awk 'NR==2 {print $2-10}' | tr -d 'G')
    CORES=$(nproc)
}

install_dependencies() {
    header "УСТАНОВКА ЗАВИСИМОСТЕЙ"
    progress_bar 20
    apt update >/dev/null && apt -y full-upgrade >/dev/null
    apt -y install curl mariadb-server nginx php8.1 php8.1-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} jq docker.io certbot >/dev/null
    
    ufw allow ssh >/dev/null
    ufw allow http >/dev/null
    ufw allow https >/dev/null
    ufw allow ${PORT_RANGE_START}:${PORT_RANGE_END}/tcp >/dev/null
    ufw allow ${PORT_RANGE_START}:${PORT_RANGE_END}/udp >/dev/null
    ufw --force enable >/dev/null
}

configure_mysql() {
    header "НАСТРОЙКА MARIADB"
    progress_bar 15
    systemctl start mariadb
    mysql_secure_installation <<EOF
n
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

    mysql -e "CREATE DATABASE ${MYSQL_DB};"
    mysql -e "CREATE USER '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mysql -e "GRANT ALL PRIVILEGES ON ${MYSQL_DB}.* TO '${MYSQL_USER}'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
}

install_panel() {
    header "УСТАНОВКА ПАНЕЛИ"
    progress_bar 25
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    curl -sLo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/

    cp .env.example .env
    composer install --no-dev --optimize-autoloader >/dev/null

    php artisan key:generate --force >/dev/null
    php artisan p:environment:setup --author=$FQDN --url=$PROTOCOL://$FQDN --timezone=UTC --cache=redis --session=database --queue=redis
    php artisan p:environment:database --host=127.0.0.1 --port=3306 --database=$MYSQL_DB --username=$MYSQL_USER --password=$MYSQL_PASSWORD
    php artisan migrate --seed --force >/dev/null
    php artisan p:user:make --email=admin@$FQDN --username=admin --name=Admin --admin=1 --password=$ADMIN_PASSWORD >/dev/null
    chown -R www-data:www-data /var/www/pterodactyl/*
}

configure_web() {
    header "НАСТРОЙКА NGINX"
    progress_bar 20
    rm -f /etc/nginx/sites-enabled/default
    curl -sLo /etc/nginx/sites-available/pterodactyl.conf https://raw.githubusercontent.com/pterodactyl/panel/develop/.github/nginx.conf
    sed -i "s/<domain>/$FQDN/g" /etc/nginx/sites-available/pterodactyl.conf
    
    if [ "$SSL_ENABLED" = true ]; then
        certbot certonly --standalone -d $FQDN --non-interactive --agree-tos -m admin@$FQDN >/dev/null
        sed -i "s/#ssl_certificate/ssl_certificate/g" /etc/nginx/sites-available/pterodactyl.conf
    fi
    
    ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/
    systemctl restart nginx
}

setup_infrastructure() {
    header "СОЗДАНИЕ ИНФРАСТРУКТУРЫ"
    COUNTRY=$(curl -s --retry 3 --max-time 5 ipapi.co/country_name || echo "Global")
    CPU_MODEL=$(lscpu | grep "Model name" | cut -d ':' -f2 | xargs | tr ' ' '-' | tr -d '()')
    
    php artisan p:location:make --short="$COUNTRY" --long="Auto Location" >/dev/null
    LOCATION_ID=$(mysql -D pterodactyl -se "SELECT id FROM locations LIMIT 1;")
    
    php artisan p:node:make --name="$CPU_MODEL-Node" --locationId=$LOCATION_ID --fqdn=$FQDN \
        --memory=$RAM_GB --disk=$DISK_GB --memoryOverallocate=0 --diskOverallocate=0 \
        --uploadSize=100 --daemonBase=/var/lib/pterodactyl/volumes --ports=$PORT_RANGE_START-$PORT_RANGE_END >/dev/null
}

install_wings() {
    header "УСТАНОВКА WINGS"
    progress_bar 30
    curl -sLo /usr/local/bin/wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
    chmod u+x /usr/local/bin/wings

    NODE_TOKEN=$(mysql -D pterodactyl -se "SELECT daemon_token FROM nodes LIMIT 1;")
    UUID=$(cat /proc/sys/kernel/random/uuid)

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

    systemctl enable wings
    systemctl start wings
}

final_reboot() {
    header "ПЕРЕЗАГРУЗКА СЕРВЕРА"
    echo -e "${GRAD2}Сервер будет перезагружен через 5 секунд...${NC}"
    progress_bar 25
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
    echo -e "${GRAD2}                     v1.0 by TEXSER${NC}"
    echo -e "${GRAD3}═══════════════════════════════════════════════${NC}"
    read -p "Создать SWAP файл? (y/n): " SWAP_CHOICE
    [[ "$SWAP_CHOICE" =~ [Yy] ]] && SWAP_ENABLED=true

    read -p "Введите домен или IP: " FQDN
    if [[ $FQDN =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        PROTOCOL="http"
    else
        PROTOCOL="https"
        SSL_ENABLED=true
    fi

    configure_resources
    setup_swap
    install_dependencies
    configure_mysql
    install_panel
    configure_web
    setup_infrastructure
    install_wings
    final_reboot
}

main