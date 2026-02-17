#!/bin/bash

# IP Pool Configuration
IP_POOL_IR=("10.10.10.1" "10.20.20.1" "172.16.10.1" "172.16.20.1" "192.168.10.1" "100.64.10.1" "10.0.5.1" "172.31.0.1" "192.168.100.1" "10.50.50.1")
IP_POOL_FR=("10.10.10.2" "10.20.20.2" "172.16.10.2" "172.16.20.2" "192.168.10.2" "100.64.10.2" "10.0.5.2" "172.31.0.2" "192.168.100.2" "10.50.50.2")

CONFIG_FILE="/tmp/lightnet_config"
PORT_LIST="/tmp/forwarded_ports.list"
HAPROXY_CONF="/etc/haproxy/haproxy.cfg"

# Colors
RED='\033[0;31m' ; GREEN='\033[0;32m' ; BLUE='\033[0;34m' ; YELLOW='\033[1;33m' ; CYAN='\033[0;36m' ; NC='\033[0m'
BOLD='\033[1m'

get_public_ip() { curl -s --connect-timeout 5 https://api.ipify.org || hostname -I | awk '{print $1}'; }

# --- SYSTEM CORE: Monitoring & Failover ---
if [[ $1 == "internal-run" ]]; then
    while true; do
        if [ -f $CONFIG_FILE ]; then
            source $CONFIG_FILE
            if [[ $s_type -eq 1 ]]; then
                if ! ping -c 1 -W 3 $target_ping > /dev/null; then
                    idx=$(( (idx + 1) % 10 ))
                    new_ir_tun=${IP_POOL_IR[$idx]}
                    new_fr_tun=${IP_POOL_FR[$idx]}
                    my_ip=$(get_public_ip)
                    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$remote_pub "ip tunnel del gre1; ip tunnel add gre1 mode gre remote $my_ip local $remote_pub ttl 255; ip link set gre1 mtu 1450 up; ip addr add $new_fr_tun/30 dev gre1"
                    sudo ip tunnel del gre1 2>/dev/null
                    sudo ip tunnel add gre1 mode gre remote $remote_pub local $my_ip ttl 255
                    sudo ip link set gre1 mtu 1450 up
                    sudo ip addr add $new_ir_tun/30 dev gre1
                    $0 internal-update-haproxy $new_fr_tun
                    echo -e "idx=$idx\nremote_pub=$remote_pub\ns_type=1\ntarget_ping=$new_fr_tun\nlocal_tun=$new_ir_tun" > $CONFIG_FILE
                    target_ping=$new_fr_tun
                fi
            fi
        fi
        sleep 10
    done
    exit 0
fi

# Helper: Update HAProxy Configuration
if [[ $1 == "internal-update-haproxy" ]]; then
    target_ip=$2
    [ ! -f "$HAPROXY_CONF" ] && exit 1
    if ! grep -q "# --- LIGHTNET START ---" "$HAPROXY_CONF"; then
        echo -e "\n# --- LIGHTNET START ---\n# --- LIGHTNET END ---" | sudo tee -a "$HAPROXY_CONF" > /dev/null
    fi
    {
        echo "# --- LIGHTNET START ---"
        if [ -f "$PORT_LIST" ]; then
            while read -r line; do
                proto=$(echo "$line" | cut -d: -f1) ; lport=$(echo "$line" | cut -d: -f2) ; rport=$(echo "$line" | cut -d: -f3)
                echo -e "listen forward_${proto}_${lport}\n  bind *:${lport}\n  mode ${proto}\n  server s1 ${target_ip}:${rport} check"
            done < "$PORT_LIST"
        fi
        echo "# --- LIGHTNET END ---"
    } > /tmp/lightnet_block
    sudo sed -i '/# --- LIGHTNET START ---/,/# --- LIGHTNET END ---/d' "$HAPROXY_CONF"
    cat /tmp/lightnet_block | sudo tee -a "$HAPROXY_CONF" > /dev/null
    rm /tmp/lightnet_block
    sudo systemctl restart haproxy 2>/dev/null
    exit 0
fi

# --- UI Interface ---
mesg n 2>/dev/null # <--- این خط را اینجا اضافه کنید تا پیام‌های سیستم روی منو چاپ نشوند

while true; do
    clear
    echo -e "${CYAN}${BOLD}
while true; do
    clear
    echo -e "${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}${BOLD}│         🚀 LIGHTNET TUNNEL MANAGER PRO V1.4            │${NC}"
    echo -e "${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
    echo -e "  ${BOLD}1)${NC} ${WHITE}Initialize Tunnel (Auto IP Detection)${NC}"
    echo -e "  ${BOLD}2)${NC} ${WHITE}Install HAProxy & Prerequisites${NC}"
    echo -e "  ${BOLD}3)${NC} ${YELLOW}Add Port Forwarding (TCP/UDP/HTTP)${NC}"
    echo -e "  ${BOLD}4)${NC} ${GREEN}Service: Enable Auto-Monitor Failover${NC}"
    echo -e "  ${BOLD}5)${NC} ${BLUE}Status: Real-time Monitor & Connections${NC}"
    echo -e "  ${BOLD}6)${NC} ${RED}Uninstall: Wipe All Configurations${NC}"
    echo -e "  ${BOLD}7)${NC} ${WHITE}Exit${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
    read -p " Selection [1-7]: " opt

    case $opt in
        1)
            echo -e "\n${BOLD}Server Location:${NC} 1) Iran (Master)  2) Foreign (Slave)"
            read -p " Choice: " s_type
            my_ip=$(get_public_ip)
            echo -e "Local Public IP: ${GREEN}$my_ip${NC}"
            read -p "Remote Public IP: " r_pub
            [[ $s_type -eq 1 ]] && { [ ! -f ~/.ssh/id_rsa ] && ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa; ssh-copy-id -o StrictHostKeyChecking=no root@$r_pub; }
            l_tun=${IP_POOL_IR[0]}; r_tun=${IP_POOL_FR[0]}
            [[ $s_type -eq 2 ]] && { l_tun=${IP_POOL_FR[0]}; r_tun=${IP_POOL_IR[0]}; }
            sudo ip tunnel del gre1 2>/dev/null
            sudo ip tunnel add gre1 mode gre remote $r_pub local $my_ip ttl 255
            sudo ip link set gre1 mtu 1450 up
            sudo ip addr add $l_tun/30 dev gre1
            echo -e "idx=0\nremote_pub=$r_pub\ns_type=$s_type\ntarget_ping=$r_tun\nlocal_tun=$l_tun" > $CONFIG_FILE
            [[ $s_type -eq 1 && -f "$HAPROXY_CONF" ]] && $0 internal-update-haproxy $r_tun
            echo -e "\n${GREEN}✔ Tunnel established successfully!${NC}"; sleep 2 ;;

        3)
            echo -e "\n${BOLD}Select Protocol:${NC}"
            echo -e "1) TCP  2) UDP  3) HTTP" ; read -p " Choice: " p_choice
            case $p_choice in 1) pr="tcp";; 2) pr="udp";; 3) pr="http";; *) pr="tcp";; esac
            read -p "Enter Ports (comma separated, e.g. 80,443,8443): " pts
            IFS=',' read -ra ADDR <<< "$pts"
            for p in "${ADDR[@]}"; do echo "$pr:$p:$p" >> "$PORT_LIST"; done
            if [ -f $CONFIG_FILE ]; then
                source $CONFIG_FILE && $0 internal-update-haproxy $target_ping
                echo -e "${GREEN}✔ Ports applied to HAProxy.${NC}"
            else
                echo -e "${RED}✘ Configure tunnel first!${NC}"
            fi
            sleep 2 ;;

        5)
            echo -e "\n${CYAN}${BOLD}📊 SYSTEM STATUS & MONITORING${NC}"
            echo -e "──────────────────────────────────────────────────────────"
            if [ -f $CONFIG_FILE ]; then
                source $CONFIG_FILE
                # Check Auto-Monitor Service Status
                if systemctl is-active --quiet lightnet; then
                    echo -e "Auto-Monitor: ${GREEN}● ACTIVE${NC}"
                else
                    echo -e "Auto-Monitor: ${RED}○ INACTIVE${NC}"
                fi
                
                echo -e "Role: $([[ $s_type -eq 1 ]] && echo "Iran (Master)" || echo "Foreign (Slave)")"
                echo -e "Remote Server: ${CYAN}$remote_pub${NC}"
                echo -e "Tunnel Link: ${YELLOW}$local_tun${NC} <───> ${YELLOW}$target_ping${NC}"
                
                ping -c 1 -W 2 $target_ping > /dev/null && \
                echo -e "Link State: ${GREEN}CONNECTED (Stable)${NC}" || \
                echo -e "Link State: ${RED}DISCONNECTED (Failover needed)${NC}"
                
                echo -e "\n${BOLD}Forwarded Ports:${NC}"
                [ -f "$PORT_LIST" ] && column -t -s ":" "$PORT_LIST" || echo "None"
            else
                echo -e "${RED}✘ System not initialized.${NC}"
            fi
            echo -e "──────────────────────────────────────────────────────────"
            read -p "Press Enter to return..." dummy ;;

        2) echo -e "\n${YELLOW}Installing...${NC}"; sudo apt update && sudo apt install -y haproxy sshpass curl ; sudo systemctl enable haproxy ; echo -e "${GREEN}✔ Done.${NC}" ; sleep 2 ;;
        4) sudo bash -c "cat <<EOT > /etc/systemd/system/lightnet.service
[Unit]
Description=Lightnet Monitor
After=network.target
[Service]
ExecStart=$(readlink -f "$0") internal-run
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOT"
           sudo systemctl daemon-reload && sudo systemctl enable lightnet && sudo systemctl start lightnet ; echo -e "${GREEN}✔ Auto-Monitor Service Started.${NC}" ; sleep 2 ;;
        6) echo -e "${RED}Wiping system...${NC}"; sudo systemctl stop lightnet 2>/dev/null ; sudo systemctl disable lightnet 2>/dev/null ; sudo rm -f /etc/systemd/system/lightnet.service ; sudo ip tunnel del gre1 2>/dev/null ; [ -f "$HAPROXY_CONF" ] && sudo sed -i '/# --- LIGHTNET START ---/,/# --- LIGHTNET END ---/d' $HAPROXY_CONF ; rm -f $CONFIG_FILE $PORT_LIST ; echo -e "${GREEN}✔ All settings flushed.${NC}" ; sleep 2 ;;
        7) exit 0 ;;
    esac
done