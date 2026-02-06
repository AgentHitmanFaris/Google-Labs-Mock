import requests
import re
import subprocess
import platform
import yaml
import os

# --- CONFIGURATION ---
TELEGRAM_TOKEN = "8181482255:AAEwurAqj4M4S8YMARG1WNggRX6h4HLcT8w"
TELEGRAM_CHAT_ID = "6770953600"
GIST_URL = "https://gist.github.com/yinqf/66e572da39489c1b2306aa42c88ec6cf"

# The specific IP you requested to use for all configs
TARGET_IP = "104.17.148.22"

def get_gist_content(url):
    try:
        raw_url = url.replace("github.com", "githubusercontent.com") + "/raw"
        response = requests.get(raw_url, timeout=15)
        response.raise_for_status()
        return response.text
    except Exception as e:
        print(f"Error fetching Gist: {e}")
        return None

def parse_yaml(content):
    content = content.replace('\t', ' ')
    content = re.sub(r'[^\x00-\x7F]+', '', content)
    try:
        return yaml.safe_load(content)
    except Exception as e:
        print(f"Error parsing YAML: {e}")
        return None

def filter_vless_configs(data):
    filtered_configs = []
    if not data or 'proxies' not in data:
        return filtered_configs

    unique_vless_configs = set()
    for proxy in data['proxies']:
        # Updated to check for both Port 80 and Port 443
        if proxy.get('type') == 'vless' and proxy.get('port') in [80, 443]:
            uuid = proxy.get('uuid', '')
            host = proxy.get('host', '')
            port = proxy.get('port')
            
            # Using your specific IP: 104.17.148.22
            vless_url = (f"vless://{uuid}@{TARGET_IP}:{port}/?"
                         f"security=none&encryption=none&headerType=none&"
                         f"type=ws&flow=none&host={host}#YTLC.T ")
            
            if vless_url not in unique_vless_configs:
                filtered_configs.append(vless_url)
                unique_vless_configs.add(vless_url)
    return filtered_configs

def send_telegram(message):
    if not TELEGRAM_TOKEN or not TELEGRAM_CHAT_ID:
        print("Telegram credentials missing!")
        return
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
    payload = {
        "chat_id": TELEGRAM_CHAT_ID, 
        "text": message, 
        "parse_mode": "Markdown",
        "disable_web_page_preview": True
    }
    requests.post(url, json=payload)

def main():
    print(f"🚀 Extracting VLESS configs for Ports 80/443 with IP {TARGET_IP}...")
    content = get_gist_content(GIST_URL)
    if not content: return
    
    data = parse_yaml(content)
    configs = filter_vless_configs(data)
    
    if configs:
        header = f"📋 *VLESS Configs Found ({len(configs)})*\n*IP:* `{TARGET_IP}`\n*Ports:* 80, 443\n\n"
        
        # Prepare the numbered list
        full_list = [f"`{config}{i+1}`" for i, config in enumerate(configs)]
        
        # Telegram has a 4096 character limit. We split the message if it's too long.
        current_message = header
        for item in full_list:
            # If adding the next item exceeds limit, send current and start new one
            if len(current_message) + len(item) > 3900:
                send_telegram(current_message)
                current_message = "" 
            current_message += item + "\n\n"
        
        # Send any remaining content
        if current_message:
            send_telegram(current_message)
            
        print(f"Success! {len(configs)} configs sent to Telegram.")
    else:
        send_telegram("❌ No matching VLESS configs found.")

if __name__ == "__main__":
    main()
