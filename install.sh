#!/bin/bash

# ==========================
#   BotStore Manager Script
# ==========================

CORE_VERSION="v1.0.0"
TELEGRAM_CHANNEL="@BotStoreInfo"
MANAGER_DIR="/opt/botstore"
CORE_FILE="ManagerCore.jar"
SERVICE_NAME="botstore"
LOG_DIR="/var/log/botstore"
LOG_FILE="$LOG_DIR/botstore.log"

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
RESET="\e[0m"

APT_UPDATED=false

install_pkg() {
    local PKG=$1
    if ! dpkg -s "$PKG" >/dev/null 2>&1; then
        if [[ "$APT_UPDATED" = false ]]; then
            echo ">> Running apt update..."
            sudo apt update -y
            APT_UPDATED=true
        fi
        echo -e "${YELLOW}Installing missing package: $PKG ...${RESET}"
        sudo apt install -y "$PKG"
    fi
}

check_java_version() {
    if ! command -v java >/dev/null 2>&1; then
        if [[ "$APT_UPDATED" = false ]]; then
            echo ">> Running apt update..."
            sudo apt update -y
            APT_UPDATED=true
        fi
        echo -e "${YELLOW}Java not found. Installing OpenJDK 17...${RESET}"
        sudo apt install -y openjdk-17-jre
    else
        JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
        JAVA_MAJOR=$(echo "$JAVA_VERSION" | cut -d. -f1)

        if [[ "$JAVA_MAJOR" -lt 17 ]]; then
            if [[ "$APT_UPDATED" = false ]]; then
                echo ">> Running apt update..."
                sudo apt update -y
                APT_UPDATED=true
            fi
            echo -e "${YELLOW}Java version $JAVA_VERSION detected (needs 17+). Installing OpenJDK 17...${RESET}"
            sudo apt install -y openjdk-17-jre
        else
            echo -e "${GREEN}Java version $JAVA_VERSION is OK.${RESET}"
        fi
    fi
}

check_dependencies() {
    echo -e "${GREEN}>> Checking dependencies...${RESET}"
    install_pkg curl
    install_pkg unzip
    install_pkg jq
    install_pkg systemd
    check_java_version
}

show_header() {
    clear
    cat << "EOF"
                                                                                  
    ,---,.               ___      .--.--.       ___                               
  ,'  .'  \            ,--.'|_   /  /    '.   ,--.'|_                             
,---.' .' |   ,---.    |  | :,' |  :  /`. /   |  | :,'   ,---.    __  ,-.         
|   |  |: |  '   ,'\   :  : ' : ;  |  |--`    :  : ' :  '   ,'\ ,' ,'/ /|         
:   :  :  / /   /   |.;__,'  /  |  :  ;_    .;__,'  /  /   /   |'  | |' | ,---.   
:   |    ; .   ; ,. :|  |   |    \  \    `. |  |   |  .   ; ,. :|  |   ,'/     \  
|   :     \'   | |: ::__,'| :     `----.   \:__,'| :  '   | |: :'  :  / /    /  | 
|   |   . |'   | .; :  '  : |__   __ \  \  |  '  : |__'   | .; :|  | ' .    ' / | 
'   :  '; ||   :    |  |  | '.'| /  /`--'  /  |  | '.'|   :    |;  : | '   ;   /| 
|   |  | ;  \   \  /   ;  :    ;'--'.     /   ;  :    ;\   \  / |  , ; '   |  / | 
|   :   /    `----'    |  ,   /   `--'---'    |  ,   /  `----'   ---'  |   :    | 
|   | ,'                ---`-'                 ---`-'                   \   \  /  
`----'                                                                   `----'   
                                                                                  
EOF

    echo -e "Core Version: $CORE_VERSION"
    echo -e "Telegram Channel: $TELEGRAM_CHANNEL"
    echo "═══════════════════════════════════════════"

    IP=$(curl -4 -s ifconfig.me || echo "N/A")
    LOCATION=$(curl -4 -s "http://ip-api.com/json/$IP" | jq -r '.country' 2>/dev/null || echo "Unknown")
    ISP=$(curl -4 -s "http://ip-api.com/json/$IP" | jq -r '.isp' 2>/dev/null || echo "Unknown")

    echo "IP Address: $IP"
    echo "Location: $LOCATION"
    echo "Datacenter: $ISP"
    echo "═══════════════════════════════════════════"
}

install_manager() {
    echo ">> Enter your API token:"
    read -r TOKEN
    if [[ -z "$TOKEN" ]]; then
        echo -e "${RED}Error:${RESET} Token cannot be empty."
        read -p "Press Enter to continue..."
        return
    fi

    sudo mkdir -p "$MANAGER_DIR"
    cd "$MANAGER_DIR" || {
        echo -e "${RED}Error:${RESET} Could not access directory $MANAGER_DIR"
        read -p "Press Enter to continue..."
        return
    }

    echo ">> Downloading libraries..."
    if ! curl -4 -fsSL -o lib.zip -H "Authorization: Bearer $TOKEN" \
        "https://api.botstore.top/api/downloadFile?name=lib.zip"; then
        echo -e "${RED}Error:${RESET} Failed to download lib.zip"
        echo "Please check your token and internet connection."
        read -p "Press Enter to continue..."
        return
    fi

    if ! unzip -o lib.zip >/dev/null 2>&1; then
        echo -e "${RED}Error:${RESET} Failed to unzip lib.zip"
        echo "The downloaded file might be corrupted."
        rm -f lib.zip
        read -p "Press Enter to continue..."
        return
    fi
    rm lib.zip

    echo ">> Downloading core..."
    if ! curl -4 -fsSL -o "$CORE_FILE" -H "Authorization: Bearer $TOKEN" \
        "https://api.botstore.top/api/downloadFile?name=manager.jar"; then
        echo -e "${RED}Error:${RESET} Failed to download manager.jar"
        echo "Please check your token and internet connection."
        read -p "Press Enter to continue..."
        return
    fi

    echo ">> Running core once to generate config..."
    if ! java -jar "$CORE_FILE"; then
        echo -e "${RED}Error:${RESET} Failed to run $CORE_FILE"
        echo "Please check if Java is properly installed."
        read -p "Press Enter to continue..."
        return
    fi

    sudo mkdir -p "$LOG_DIR"
    sudo touch "$LOG_FILE"
    sudo chown "$(whoami)":"$(whoami)" "$LOG_FILE"

    echo ">> Creating systemd service..."
    sudo tee /etc/systemd/system/$SERVICE_NAME.service > /dev/null <<EOL
[Unit]
Description=BotStore Manager Service
After=network.target

[Service]
Type=simple
WorkingDirectory=$MANAGER_DIR
ExecStart=/usr/bin/java -jar $CORE_FILE
Restart=always
RestartSec=5
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

[Install]
WantedBy=multi-user.target
EOL

    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE_NAME" >/dev/null 2>&1

    echo -e "${GREEN}>> Install completed successfully.${RESET}"
    cd - >/dev/null
    read -p "Press Enter to continue..."
}

uninstall_manager() {
    echo -e "${YELLOW}>> Uninstalling BotStore Manager...${RESET}"
    read -p "Are you sure you want to uninstall? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo ">> Uninstall cancelled."
        read -p "Press Enter to continue..."
        return
    fi

    sudo systemctl stop "$SERVICE_NAME" 2>/dev/null
    sudo systemctl disable "$SERVICE_NAME" 2>/dev/null
    sudo rm -f /etc/systemd/system/$SERVICE_NAME.service
    sudo rm -rf "$MANAGER_DIR"
    sudo rm -rf "$LOG_DIR"
    sudo systemctl daemon-reload
    echo -e "${GREEN}>> Manager uninstalled successfully.${RESET}"
    read -p "Press Enter to continue..."
}

update_manager() {
    echo -e "${YELLOW}>> Updating manager core and libraries...${RESET}"
    read -p "Are you sure you want to update? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo ">> Update cancelled."
        read -p "Press Enter to continue..."
        return
    fi

    cd "$MANAGER_DIR" || {
        echo -e "${RED}Error:${RESET} BotStore directory not found. Please install first."
        read -p "Press Enter to continue..."
        return
    fi

    echo ">> Stopping service..."
    sudo systemctl stop "$SERVICE_NAME" 2>/dev/null

    echo ">> Backing up config..."
    if [[ -f "config.yml" ]]; then
        cp config.yml config.yml.backup
        echo ">> Config backed up to config.yml.backup"
    fi

    echo ">> Enter your API token:"
    read -r TOKEN
    if [[ -z "$TOKEN" ]]; then
        echo -e "${RED}Error:${RESET} Token cannot be empty."
        echo ">> Restoring service..."
        sudo systemctl start "$SERVICE_NAME" 2>/dev/null
        read -p "Press Enter to continue..."
        return
    fi

    echo ">> Removing old core and libraries..."
    rm -f "$CORE_FILE"
    rm -rf Libraries
    rm -f config.yml

    echo ">> Downloading libraries..."
    if ! curl -4 -fsSL -o lib.zip -H "Authorization: Bearer $TOKEN" \
        "https://api.botstore.top/api/downloadFile?name=lib.zip"; then
        echo -e "${RED}Error:${RESET} Failed to download lib.zip"
        echo "Please check your token and internet connection."
        echo ">> Restoring service..."
        sudo systemctl start "$SERVICE_NAME" 2>/dev/null
        read -p "Press Enter to continue..."
        return
    fi

    if ! unzip -o lib.zip >/dev/null 2>&1; then
        echo -e "${RED}Error:${RESET} Failed to unzip lib.zip"
        echo "The downloaded file might be corrupted."
        rm -f lib.zip
        echo ">> Restoring service..."
        sudo systemctl start "$SERVICE_NAME" 2>/dev/null
        read -p "Press Enter to continue..."
        return
    fi
    rm -f lib.zip

    echo ">> Downloading new core..."
    if ! curl -4 -fsSL -o "$CORE_FILE" -H "Authorization: Bearer $TOKEN" \
        "https://api.botstore.top/api/downloadFile?name=manager.jar"; then
        echo -e "${RED}Error:${RESET} Failed to download manager.jar"
        echo "Please check your token and internet connection."
        echo ">> Restoring service..."
        sudo systemctl start "$SERVICE_NAME" 2>/dev/null
        read -p "Press Enter to continue..."
        return
    fi

    echo ">> Starting service..."
    if sudo systemctl start "$SERVICE_NAME"; then
        echo -e "${GREEN}>> Update completed successfully.${RESET}"
    else
        echo -e "${RED}Error:${RESET} Failed to start service after update."
        echo "Please check the logs for more information."
    fi
    read -p "Press Enter to continue..."
}

start_manager() {
    if ! sudo systemctl start "$SERVICE_NAME"; then
        echo -e "${RED}Error:${RESET} Failed to start service."
        echo "Service might not be installed or there could be a configuration issue."
    else
        echo -e "${GREEN}>> Manager started successfully.${RESET}"
    fi
    read -p "Press Enter to continue..."
}

stop_manager() {
    if ! sudo systemctl stop "$SERVICE_NAME"; then
        echo -e "${RED}Error:${RESET} Failed to stop service."
        echo "Service might not be running or installed."
    else
        echo -e "${YELLOW}>> Manager stopped successfully.${RESET}"
    fi
    read -p "Press Enter to continue..."
}

restart_manager() {
    echo ">> Restarting BotStore Manager..."
    if ! sudo systemctl restart "$SERVICE_NAME"; then
        echo -e "${RED}Error:${RESET} Failed to restart service."
        echo "Service might not be installed or there could be a configuration issue."
    else
        echo -e "${GREEN}>> Manager restarted successfully.${RESET}"
    fi
    read -p "Press Enter to continue..."
}

view_logs() {
    if [[ ! -f "$LOG_FILE" ]]; then
        echo -e "${RED}Error:${RESET} Log file not found at $LOG_FILE"
        echo "Manager might not be installed or hasn't run yet."
        read -p "Press Enter to continue..."
        return
    fi

    echo ""
    echo "Select log viewing option:"
    echo " 1. View last 50 lines"
    echo " 2. View last 100 lines" 
    echo " 3. View full log (scrollable)"
    echo " 4. Follow log in real-time"
    echo " 0. Back to menu"
    echo ""
    read -p "Enter your choice [0-4]: " log_choice

    case $log_choice in
        1)
            echo ">> Last 50 log lines:"
            echo "═══════════════════════════════════════════"
            sudo tail -n 50 "$LOG_FILE"
            echo "═══════════════════════════════════════════"
            ;;
        2)
            echo ">> Last 100 log lines:"
            echo "═══════════════════════════════════════════"
            sudo tail -n 100 "$LOG_FILE"
            echo "═══════════════════════════════════════════"
            ;;
        3)
            echo ">> Full log (Use Arrow keys to scroll, 'q' to quit):"
            echo "═══════════════════════════════════════════"
            sudo less "$LOG_FILE"
            ;;
        4)
            echo ">> Following log in real-time (Press Ctrl+C to stop):"
            echo "═══════════════════════════════════════════"
            sudo tail -f "$LOG_FILE"
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}Invalid choice!${RESET}"
            sleep 1
            view_logs
            return
            ;;
    esac
    
    if [[ "$log_choice" != "0" ]]; then
        read -p "Press Enter to continue..."
    fi
}

edit_config() {
    CONFIG_FILE="$MANAGER_DIR/config.yml"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}Error:${RESET} Config file not found at $CONFIG_FILE"
        echo "Manager might not be installed or config file hasn't been generated yet."
        echo "Please install the manager first or run it once to generate the config file."
    else
        if command -v nano >/dev/null 2>&1; then
            nano "$CONFIG_FILE"
        elif command -v vim >/dev/null 2>&1; then
            vim "$CONFIG_FILE"
        else
            echo -e "${RED}Error:${RESET} No text editor found (nano/vim)"
            echo "Please install nano or vim to edit the config file."
        fi
    fi
    read -p "Press Enter to continue..."
}

show_status() {
    echo -e "${GREEN}>> BotStore Manager Status${RESET}"
    echo "═══════════════════════════════════════════"
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "Service Status: ${GREEN}RUNNING${RESET}"
    else
        echo -e "Service Status: ${RED}STOPPED${RESET}"
    fi
    
    if systemctl is-enabled --quiet "$SERVICE_NAME"; then
        echo -e "Auto-start: ${GREEN}ENABLED${RESET}"
    else
        echo -e "Auto-start: ${RED}DISABLED${RESET}"
    fi
    
    if [[ -d "$MANAGER_DIR" ]]; then
        echo -e "Installation: ${GREEN}FOUND${RESET} ($MANAGER_DIR)"
    else
        echo -e "Installation: ${RED}NOT FOUND${RESET}"
    fi
    
    if [[ -f "$LOG_FILE" ]]; then
        LOG_SIZE=$(du -h "$LOG_FILE" 2>/dev/null | cut -f1)
        echo -e "Log File: ${GREEN}EXISTS${RESET} (Size: $LOG_SIZE)"
    else
        echo -e "Log File: ${RED}NOT FOUND${RESET}"
    fi
    
    echo "═══════════════════════════════════════════"
    read -p "Press Enter to continue..."
}

menu() {
    check_dependencies
    while true; do
        show_header
        echo ""
        echo " 1. Install"
        echo " 2. Uninstall"
        echo " 3. Start"
        echo " 4. Stop"
        echo " 5. Restart"
        echo " 6. View Logs"
        echo " 7. Update"
        echo " 8. Edit Config"
        echo " 9. Show Status"
        echo " 0. Exit"
        echo ""
        echo "-------------------------------"
        read -p "Enter your choice [0-9]: " choice

        case $choice in
            1) install_manager ;;
            2) uninstall_manager ;;
            3) start_manager ;;
            4) stop_manager ;;
            5) restart_manager ;;
            6) view_logs ;;
            7) update_manager ;;
            8) edit_config ;;
            9) show_status ;;
            0) echo "Goodbye!"; exit 0 ;;
            *) echo -e "${RED}Invalid choice! Please select 0-9.${RESET}"; sleep 2 ;;
        esac
    done
}

menu