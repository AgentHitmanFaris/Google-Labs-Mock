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

def get_gist_content(gist_url):
    try:
        raw_url = gist_url.replace("github.com", "githubusercontent.com") + "/raw"
        response = requests.get(raw_url, timeout=15)
        response.raise_for_status()
        return response.text
    except Exception as e:
        print(f"Error fetching Gist: {e}")
        return None

def parse_yaml(yaml_content):
    yaml_content = yaml_content.replace('\t', ' ')
    yaml_content = re.sub(r'[^\x00-\x7F]+', '', yaml_content)
    try:
        return yaml.safe_load(yaml_content)
    except Exception as e:
        print(f"Error parsing YAML: {e}")
        return None

def filter_vless_configs(data):
    filtered_configs = []
    if not data or 'proxies' not in data:
        return filtered_configs

    unique_vless_configs = set()
    for proxy in data['proxies']:
        # Only filtering for VLESS and Port 80
        if (proxy.get('type') == 'vless' and proxy.get('port') == 80):
            uuid = proxy.get('uuid', '')
            host = proxy.get('host', '')
            
            # Format: vless://uuid@IP:80/?...#Remark
            vless_url = (f"vless://{uuid}@104.17.113.188:80/?"
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
    payload = {"chat_id": TELEGRAM_CHAT_ID, "text": message, "parse_mode": "Markdown"}
    requests.post(url, json=payload)

def main():
    print("🚀 Extracting all Port 80 VLESS configs...")
    content = get_gist_content(GIST_URL)
    if not content: return
    
    data = parse_yaml(content)
    configs = filter_vless_configs(data)
    
    if configs:
        header = f"📋 *Found {len(configs)} VLESS Configs (Port 80)*\n\n"
        # Number the configs directly for the list
        body = "\n\n".join([f"`{config}{i+1}`" for i, config in enumerate(configs)])
        
        # Note: Telegram has a message limit of 4096 characters. 
        # If the list is too long, we might need to split it.
        if len(header + body) > 4000:
            send_telegram(header + "List is too long for one message. Sending first batch...")
            send_telegram(body[:4000])
        else:
            send_telegram(header + body)
        print(f"Success! {len(configs)} configs sent to Telegram.")
    else:
        send_telegram("❌ No Port 80 VLESS configs found.")

if __name__ == "__main__":
    main()
