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

show_header() {
    clear
    echo -e "${GRAD1}"
    echo "████████╗███████╗██╗  ██╗██████╗  ██████╗ ██████╗ ██████╗ ███████╗"
    echo "╚══██╔══╝██╔════╝██║  ██║██╔══██╗██╔═══██╗██╔══██╗██╔══██╗██╔════╝"
    echo "   ██║   █████╗  ███████║██████╔╝██║   ██║██████╔╝██████╔╝█████╗  "
    echo "   ██║   ██╔══╝  ██╔══██║██╔═══╝ ██║   ██║██╔═══╝ ██╔══██╗██╔══╝  "
    echo "   ██║   ███████╗██║  ██║██║     ╚██████╔╝██║     ██║  ██║███████╗"
    echo "   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝      ╚═════╝ ╚═╝     ╚═╝  ╚═╝╚══════╝"
    echo -e "${GRAD2}                     v5.0 by TEXSER${NC}"
    echo -e "${GRAD3}═══════════════════════════════════════════════${NC}"
    echo -e "Этап: ${GRAD1}$1${NC}"
}

progress_bar() {
    local duration=$1
    local total=$2
    local width=50
    local percent=$((duration*100/total))
    local filled=$((width*percent/100))
    printf "${GRAD2}["
    printf "%${filled}s" | tr ' ' '█'
    printf "%$((width-filled))s" | tr ' ' ' '
    printf "] ${GRAD3}%3d%%${NC}\r" $percent
}

setup_swap() {
    show_header "НАСТРОЙКА SWAP"
    if [ "$SWAP_ENABLED" = true ]; then
        for i in {1..10}; do
            progress_bar $i 10
            sleep 0.1
        done
        echo
        
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
}

system_update() {
    show_header "ОБНОВЛЕНИЕ СИСТЕМЫ"
    apt update -y >/dev/null 2>&1
    for i in {1..20}; do
        progress_bar $i 20
        sleep 0.05
    done
    echo
    apt full-upgrade -y >/dev/null 2>&1 || error_exit "Ошибка обновления"
}

install_dependencies() {
    show_header "УСТАНОВКА ЗАВИСИМОСТЕЙ"
    apt install -y software-properties-common apt-transport-https ca-certificates \
    curl gnupg2 git unzip jq >/dev/null 2>&1 || error_exit "Ошибка установки"
    
    add-apt-repository ppa:ondrej/php -y >/dev/null 2>&1
    apt update >/dev/null 2>&1
    
    for i in {1..30}; do
        progress_bar $i 30
        sleep 0.03
    done
    echo
    
    apt install -y php8.2 php8.2-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} \
    mariadb-server nginx certbot python3-certbot-nginx docker.io >/dev/null 2>&1 || error_exit "Ошибка установки"
}

configure_mysql() {
    show_header "НАСТРОЙКА MARIADB"
    systemctl start mariadb >/dev/null 2>&1
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
    
    for i in {1..15}; do
        progress_bar $i 15
        sleep 0.05
    done
    echo
}

install_panel() {
    show_header "УСТАНОВКА ПАНЕЛИ"
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl || error_exit "Ошибка перехода в директорию"
    
    curl -sLo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz >/dev/null 2>&1
    tar -xzf panel.tar.gz >/dev/null 2>&1
    chmod -R 755 storage/* bootstrap/cache/

    cp .env.example .env
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer >/dev/null 2>&1
    composer install --no-dev --optimize-autoloader --no-interaction >/dev/null 2>&1

    php artisan key:generate --force >/dev/null 2>&1
    php artisan p:environment:setup --author="$FQDN" --url="$PROTOCOL://$FQDN" --timezone=UTC --cache=redis --session=database --queue=redis >/dev/null 2>&1
    php artisan p:environment:database --host=127.0.0.1 --port=3306 --database="$MYSQL_DB" --username="$MYSQL_USER" --password="$MYSQL_PASSWORD" >/dev/null 2>&1
    php artisan migrate --seed --force >/dev/null 2>&1
    php artisan p:user:make --email="admin@$FQDN" --username=admin --name=Admin --admin=1 --password="$ADMIN_PASSWORD" >/dev/null 2>&1
    chown -R www-data:www-data /var/www/pterodactyl/* >/dev/null 2>&1
    
    for i in {1..25}; do
        progress_bar $i 25
        sleep 0.03
    done
    echo
}

configure_web() {
    show_header "НАСТРОЙКА NGINX"
    rm -f /etc/nginx/sites-enabled/default
    curl -sLo /etc/nginx/sites-available/pterodactyl.conf https://raw.githubusercontent.com/pterodactyl/panel/develop/.github/nginx.conf >/dev/null 2>&1
    sed -i "s/<domain>/$FQDN/g" /etc/nginx/sites-available/pterodactyl.conf >/dev/null 2>&1
    
    if [ "$SSL_ENABLED" = true ]; then
        certbot certonly --standalone -d "$FQDN" --non-interactive --agree-tos -m "admin@$FQDN" >/dev/null 2>&1
        sed -i "s/#ssl_certificate/ssl_certificate/g" /etc/nginx/sites-available/pterodactyl.conf >/dev/null 2>&1
    fi
    
    ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/ >/dev/null 2>&1
    systemctl restart nginx >/dev/null 2>&1
    
    for i in {1..20}; do
        progress_bar $i 20
        sleep 0.03
    done
    echo
}

setup_infrastructure() {
    show_header "СОЗДАНИЕ ИНФРАСТРУКТУРЫ"
    COUNTRY=$(curl -s --retry 3 --max-time 5 ipapi.co/country_name || echo "Global")
    CPU_MODEL=$(lscpu | grep "Model name" | cut -d ':' -f2 | xargs | tr ' ' '-' | tr -d '()')
    
    php artisan p:location:make --short="$COUNTRY" --long="Auto Location" >/dev/null 2>&1
    LOCATION_ID=$(mysql -D pterodactyl -se "SELECT id FROM locations LIMIT 1;" 2>/dev/null)
    
    php artisan p:node:make --name="$CPU_MODEL-Node" --locationId=$LOCATION_ID --fqdn="$FQDN" \
        --memory=$(( $(free -g | awk '/Mem:/ {print $2}')-1 )) --disk=$(( $(df -BG / | awk 'NR==2 {print $2}' | tr -d 'G')-10 )) \
        --memoryOverallocate=0 --diskOverallocate=0 --uploadSize=100 \
        --daemonBase=/var/lib/pterodactyl/volumes --ports=$PORT_RANGE_START-$PORT_RANGE_END >/dev/null 2>&1
    
    for i in {1..15}; do
        progress_bar $i 15
        sleep 0.05
    done
    echo
}

install_wings() {
    show_header "УСТАНОВКА WINGS"
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
    
    for i in {1..30}; do
        progress_bar $i 30
        sleep 0.03
    done
    echo
}

finalize() {
    show_header "ЗАВЕРШЕНИЕ УСТАНОВКИ"
    (crontab -l 2>/dev/null; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -
    
    echo -e "${GRAD1}✔ Установка успешно завершена!"
    echo -e "${GRAD2}═══════════════════════════════════════════════"
    echo -e "${GRAD2}Панель: ${GRAD3}$PROTOCOL://$FQDN"
    echo -e "${GRAD2}Логин: ${GRAD3}admin@$FQDN"
    echo -e "${GRAD2}Пароль: ${GRAD3}$ADMIN_PASSWORD"
    echo -e "${GRAD2}═══════════════════════════════════════════════${NC}"
    
    echo -e "${GRAD1}Перезагрузка через 10 секунд...${NC}"
    for i in {10..1}; do
        echo -n -e "${GRAD2}Осталось: ${i} сек. ${NC}\r"
        sleep 1
    done
    shutdown -r now
}

main() {
    clear
    echo -e "${GRAD1}"
    echo "████████╗███████╗██╗  ██╗██████╗  ██████╗ ██████╗ ██████╗ ███████╗"
    echo "╚══██╔══╝██╔════╝██║  ██║██╔══██╗██╔═══██╗██╔══██╗██╔══██╗██╔════╝"
    echo "   ██║   █████╗  ███████║██████╔╝██║   ██║██████╔╝██████╔╝█████╗  "
    echo "   ██║   ██╔══╝  ██╔══██║██╔═══╝ ██║   ██║██╔═══╝ ██╔══██╗██╔══╝  "
    echo "   ██║   ███████╗██║  ██║██║     ╚██████╔╝██║     ██║  ██║███████╗"
    echo "   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝      ╚═════╝ ╚═╝     ╚═╝  ╚═╝╚══════╝"
    echo -e "${GRAD2}                     v5.2 by TEXSER${NC}"
    echo -e "${GRAD3}═══════════════════════════════════════════════${NC}"

    while true; do
        read -p "$(echo -e "${GRAD2}Создать SWAP файл? (y/n): ${NC}")" SWAP_CHOICE
        case "$SWAP_CHOICE" in
            [Yy]* ) SWAP_ENABLED=true; break;;
            [Nn]* ) SWAP_ENABLED=false; break;;
            * ) echo -e "${RED}Пожалуйста, введите Y или N${NC}";;
        esac
    done

    while true; do
        read -p "$(echo -e "${GRAD2}Введите домен или IP: ${NC}")" FQDN
        FQDN=$(echo "$FQDN" | tr -d '[:space:]')
        
        if [[ -z "$FQDN" ]]; then
            echo -e "${RED}Поле не может быть пустым!${NC}"
        elif [[ $FQDN =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            if [[ $(ipcalc -cs "$FQDN" && echo valid || echo invalid) == "valid" ]]; then
                PROTOCOL="http"
                break
            else
                echo -e "${RED}Некорректный IP-адрес!${NC}"
            fi
        elif [[ $FQDN =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9](\.[a-zA-Z]{2,})+$ ]]; then
            if dig +short "$FQDN" | grep -q '^[0-9.]\+$'; then
                PROTOCOL="https"
                SSL_ENABLED=true
                break
            else
                echo -e "${RED}Домен не резолвится!${NC}"
            fi
        else
            echo -e "${RED}Некорректный формат! Примеры:${NC}"
            echo -e "IP: 192.168.1.1"
            echo -e "Домен: panel.example.com"
        fi
    done

    system_update
    setup_swap
    install_dependencies
    configure_mysql
    install_panel
    configure_web
    setup_infrastructure
    install_wings
    finalize
}
