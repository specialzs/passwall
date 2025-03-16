#!/bin/bash

# Hata kontrol fonksiyonu
function check_error {
    if [ $? -ne 0 ]; then
        echo "Bir hata oluştu! İşlem iptal ediliyor."
        exit 1
    fi
}

# Geri alma fonksiyonu
function undo_changes {
    echo "Yapılan değişiklikler geri alınıyor..."
    # Config dosyasını sil
    rm -f /etc/v2ray/config.json
    check_error
    # iptables kurallarını kaldır
    iptables -t nat -D PREROUTING -p tcp --dport 10808 -j REDIRECT --to-ports 10808
    iptables -t nat -D OUTPUT -p tcp --dport 10808 -j REDIRECT --to-ports 10808
    check_error
    # DNS ayarını kaldır
    sed -i '/list server.*127.0.0.1#10853/d' /etc/config/dhcp
    /etc/init.d/dnsmasq restart
    check_error
    # V2Ray kurulumunu kaldır
    rm -f /usr/bin/v2ray /usr/bin/v2ctl /usr/bin/geoip.dat /usr/bin/geosite.dat
    check_error
    echo "Değişiklikler başarıyla geri alındı!"
}

# Kurulum işlemi
function install_v2ray {
    echo "V2Ray kurulumu başlatılıyor..."
    # V2Ray kurulumu
    cd /root
    wget https://github.com/v2fly/v2ray-core/releases/download/v5.29.2/v2ray-freebsd-arm64-v8a.zip
    check_error
    unzip v2ray-freebsd-arm64-v8a.zip
    check_error
    chmod +x v2ray v2ctl
    mv v2ray /usr/bin/
    mv v2ctl /usr/bin/
    mv geoip.dat /usr/bin/
    mv geosite.dat /usr/bin/
    echo "V2Ray kurulumu tamamlandı!"
}

# V2Ray config dosyasını yükleme
function load_config {
    echo "V2Ray config dosyasını yüklemek için yapılandırma başlatılıyor..."
    mkdir -p /etc/v2ray
    cat <<EOF > /etc/v2ray/config.json
{
  "dns": {
    "hosts": {
      "domain:googleapis.cn": "googleapis.com"
    },
    "servers": [
      {
        "address": "fakedns",
        "domains": [
          "geosite:cn"
        ]
      },
      "8.8.8.8"
    ]
  },
  "fakedns": [
    {
      "ipPool": "198.18.0.0/15",
      "poolSize": 10000
    }
  ],
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 10808,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true,
        "userLevel": 8
      },
      "sniffing": {
        "destOverride": [
          "http",
          "tls",
          "fakedns"
        ],
        "enabled": true,
        "routeOnly": true
      },
      "tag": "socks"
    },
    {
      "listen": "127.0.0.1",
      "port": 10809,
      "protocol": "http",
      "settings": {
        "userLevel": 8
      },
      "tag": "http"
    },
    {
      "listen": "127.0.0.1",
      "port": 10853,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "8.8.8.8",
        "network": "tcp,udp",
        "port": 53
      },
      "tag": "dns-in"
    }
  ],
  "log": {
    "loglevel": "warning"
  },
  "outbounds": [
    {
      "mux": {
        "concurrency": -1,
        "enabled": false,
        "xudpConcurrency": 8,
        "xudpProxyUDP443": ""
      },
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "hostopya.nemetrix2.fun",
            "port": 443,
            "users": [
              {
                "encryption": "none",
                "flow": "",
                "id": "b538e11a-414c-4a85-ab7f-4d4e28fd6648",
                "level": 8,
                "security": "auto"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "allowInsecure": true
        },
        "wsSettings": {
          "headers": {
            "Host": "hostopya.nemetrix2.fun"
          },
          "path": "/"
        },
        "tag": "proxy"
      }
    },
    {
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIP"
      },
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {
        "response": {
          "type": "http"
        }
      },
      "tag": "block"
    },
    {
      "protocol": "dns",
      "tag": "dns-out"
    }
  ],
  "policy": {
    "levels": {
      "8": {
        "connIdle": 300,
        "downlinkOnly": 1,
        "handshake": 4,
        "uplinkOnly": 1
      }
    },
    "system": {
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "inboundTag": [
          "dns-in"
        ],
        "outboundTag": "dns-out",
        "type": "field"
      },
      {
        "ip": [
          "8.8.8.8"
        ],
        "outboundTag": "proxy",
        "port": "53",
        "type": "field"
      }
    ]
  },
  "stats": {}
}
EOF
    check_error
    echo "Config dosyası başarıyla yüklendi!"
}

# iptables ayarları yapma
function configure_iptables {
    echo "iptables ayarları yapılıyor..."
    iptables -t nat -A PREROUTING -p tcp --dport 10808 -j REDIRECT --to-ports 10808
    iptables -t nat -A OUTPUT -p tcp --dport 10808 -j REDIRECT --to-ports 10808
    check_error
    echo "iptables ayarları tamamlandı!"
}

# DNS yönlendirmesi yapma
function configure_dns {
    echo "DNS yönlendirmesi yapılıyor..."
    echo "list server '127.0.0.1#10853'" >> /etc/config/dhcp
    /etc/init.d/dnsmasq restart
    check_error
    echo "DNS yönlendirmesi tamamlandı!"
}

# V2Ray servisini başlatma
function start_v2ray {
    echo "V2Ray servisi başlatılıyor..."
    /usr/bin/v2ray -config /etc/v2ray/config.json &
    check_error
    echo "V2Ray servisi başlatıldı!"
}

# Menüyü başlatma
clear
echo "V2Ray Kurulum ve Yapılandırma Scripti"
echo "====================================="
echo "1) V2Ray Kurulumunu Yap"
echo "2) V2Ray Config Dosyasını Yükle"
echo "3) iptables Ayarlarını Yap"
echo "4) DNS Yönlendirmesini Yap"
echo "5) V2Ray Servisini Başlat"
echo "6) V2Ray'ı Kaldır"
echo "7) Yapılan Değişiklikleri Geri Al"
echo "8) Çıkış"

# Kullanıcıdan seçim al
read -p "Yapmak istediğiniz işlemi seçin (1-8): " choice

case $choice in
  1)
    install_v2ray
    ;;
  2)
    load_config
    ;;
  3)
    configure_iptables
    ;;
  4)
    configure_dns
    ;;
  5)
    start_v2ray
    ;;
  6)
    undo_changes
    ;;
  7)
    undo_changes
    ;;
  8)
    echo "Çıkılıyor..."
    exit 0
    ;;
  *)
    echo "Geçersiz seçenek. Çıkılıyor..."
    exit 1
    ;;
esac
