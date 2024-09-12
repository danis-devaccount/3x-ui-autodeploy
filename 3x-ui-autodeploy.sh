#!/bin/bash

PANEL_DIR="$HOME/3x-ui"
EXTERNAL_IP=$(curl -s ifconfig.me)

if [ -z "$EXTERNAL_IP" ]; then
    echo "Не удалось получить внешний IP-адрес."
    exit 1
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    echo "Не удалось определить дистрибутив."
    exit 1
fi

case "$DISTRO" in
    ubuntu|debian)
        echo "Установка Docker на $DISTRO..."
        apt-get update
        apt-get install -y \
            ca-certificates \
            curl \
            gnupg \
            lsb-release

        curl -fsSL https://download.docker.com/linux/$DISTRO/gpg | gpg --batch --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$DISTRO \
            $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io
        ;;
    centos)
        echo "Установка Docker на CentOS..."
        yum install -y yum-utils
        yum-config-manager \
            --add-repo \
            https://download.docker.com/linux/centos/docker-ce.repo

        yum install -y docker-ce docker-ce-cli containerd.io
        ;;
    *)
        echo "Ваш дистрибутив не поддерживается этим скриптом."
        exit 1
        ;;
esac

systemctl start docker
systemctl enable docker
docker --version

echo "Docker установлен и запущен."

if [ ! -d "$PANEL_DIR" ]; then
    mkdir -p "$PANEL_DIR"
fi

curl -o "$PANEL_DIR/docker-compose.yml" "https://raw.githubusercontent.com/MHSanaei/3x-ui/main/docker-compose.yml"

if [ ! -f "$PANEL_DIR/docker-compose.yml" ]; then
    echo "Не удалось скачать файл docker-compose.yml для панели."
    exit 1
fi

generate_random_string() {
    tr -dc A-Za-z0-9 </dev/urandom | head -c 16
}

PANEL_PORT=$((10000 + RANDOM % 55536))
PANEL_PASSWORD=$(generate_random_string)
PANEL_PATH="/$(generate_random_string)/"

mkdir -p "$PANEL_DIR/cert"
openssl req -x509 -newkey rsa:4096 -keyout "$PANEL_DIR/cert/key.pem" -out "$PANEL_DIR/cert/cert.pem" -sha256 -days 3650 -nodes -subj "/C=XX/ST=StateName/L=CityName/O=CompanyName/OU=CompanySectionName/CN=CommonNameOrHostname"
sed -i 's|\$PWD|./|g' "$PANEL_DIR/docker-compose.yml"

docker compose -f "$PANEL_DIR/docker-compose.yml" pull
docker compose -f "$PANEL_DIR/docker-compose.yml" up -d
docker exec 3x-ui sh -c "
    apk update &&
    apk upgrade &&
    apk add sqlite &&
    sqlite3 /etc/x-ui/x-ui.db <<EOF
INSERT INTO settings(key, value) VALUES ('webCertFile', '/root/cert/cert.pem');
INSERT INTO settings(key, value) VALUES ('webKeyFile', '/root/cert/key.pem');
INSERT INTO settings(key, value) VALUES ('webBasePath', '$PANEL_PATH');
INSERT INTO settings(key, value) VALUES ('webPort', '$PANEL_PORT');
UPDATE users SET password='$PANEL_PASSWORD' WHERE username='admin';
EOF
"

docker compose -f "$PANEL_DIR/docker-compose.yml" down
docker compose -f "$PANEL_DIR/docker-compose.yml" up -d

if ! docker compose -f "$PANEL_DIR/docker-compose.yml" ps | grep -q "Up"; then
    echo "Ошибка: панель не запустилась!"
    exit 1
fi

BLUE='\033[0;34m'
NC='\033[0m'
printf "%b%*s%b\n" "$BLUE" 91 | tr ' ' '*'
printf "Добро пожаловать в свободный интернет!
Используйте адрес$NC https://$EXTERNAL_IP:$PANEL_PORT$PANEL_PATH $BLUEдля входа в админ-панель.
Логин:$NC admin $BLUE
Пароль:$NC $PANEL_PASSWORD $BLUE
Обязательно запишите эти данные!"
printf "\n%*s" 91 | tr ' ' '*'
printf "%b\n" "$NC"
