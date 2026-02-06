import requests
import re
import subprocess
import platform
import yaml
import os

# --- CONFIGURATION ---
TELEGRAM_TOKEN = "8181482255:AAEwurAqj4M4S8YMARG1WNggRX6h4HLcT8w"
TELEGRAM_CHAT_ID = "6770953600"
GIST_URL = "https://gist.github.com/Tdison/6b745663fd038e3c63e0880ecc652bcf"
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

def ping_server(host):
    # GitHub Actions runs on Linux, so we use '-c'
    param = '-n' if platform.system().lower() == 'windows' else '-c'
    command = ['ping', param, '1', '-W', '2', host]
    try:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout, _ = process.communicate(timeout=4)
        return process.returncode == 0
    except:
        return False

def filter_vless_configs(data):
    filtered_configs = []
    if not data or 'proxies' not in data:
        return filtered_configs

    unique_vless_configs = set()
    for proxy in data['proxies']:
        host = proxy.get('host')
        # Check 1: Must have a host
        # Check 2: Must be VLESS and Port 80 or 443
        if host and proxy.get('type') == 'vless' and proxy.get('port') in [80, 443]:
            uuid = proxy.get('uuid', '')
            port = proxy.get('port')
            
            vless_url = (f"vless://{uuid}@{TARGET_IP}:{port}/?"
                         f"security=none&encryption=none&headerType=none&"
                         f"type=ws&flow=none&host={host}#YTLC.T ")
            
            if vless_url not in unique_vless_configs:
                filtered_configs.append(vless_url)
                unique_vless_configs.add(vless_url)
    return filtered_configs

def send_telegram(message):
    if not TELEGRAM_TOKEN or not TELEGRAM_CHAT_ID:
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
    print(f"🚀 Starting Scan (IP: {TARGET_IP} | Ports: 80, 443)...")
    content = get_gist_content(GIST_URL)
    if not content: return
    
    data = parse_yaml(content)
    all_configs = filter_vless_configs(data)
    
    working_configs = []
    print(f"Testing {len(all_configs)} potential configs...")

    for config in all_configs:
        # Extract host for the ping test
        match = re.search(r"host=([^#&]*)", config)
        host = match.group(1) if match else None
        
        if host and ping_server(host):
            # Number them based on the current working list size
            numbered_config = f"{config}{len(working_configs) + 1}"
            working_configs.append(numbered_config)

    if working_configs:
        header = (f"✅ *VLESS Scan Complete*\n"
                  f"*Total Found:* {len(all_configs)}\n"
                  f"*Working:* {len(working_configs)}\n"
                  f"*IP:* `{TARGET_IP}`\n\n")
        
        current_message = header
        for item in working_configs:
            if len(current_message) + len(item) > 3900:
                send_telegram(current_message)
                current_message = "" 
            current_message += f"`{item}`\n\n"
        
        if current_message:
            send_telegram(current_message)
        print(f"Done! Sent {len(working_configs)} working configs.")
    else:
        send_telegram(f"❌ Scan complete. No working configs found for IP {TARGET_IP}.")

if __name__ == "__main__":
    main()
