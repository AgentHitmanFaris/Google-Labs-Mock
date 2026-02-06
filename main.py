import requests
import re
import subprocess
import platform
import yaml
import os

# --- CONFIGURATION ---
TELEGRAM_TOKEN = "YOUR_BOT_TOKEN_HERE"
TELEGRAM_CHAT_ID = "YOUR_CHAT_ID_HERE"
GIST_URL = "https://gist.github.com/yinqf/66e572da39489c1b2306aa42c88ec6cf"

def get_gist_content(url):
    try:
        raw_url = url.replace("github.com", "githubusercontent.com") + "/raw"
        response = requests.get(raw_url, timeout=10)
        response.raise_for_status()
        return response.text
    except Exception as e:
        print(f"Error fetching Gist: {e}")
        return None

def parse_yaml(content):
    content = content.replace('\t', ' ')
    content = re.sub(r'[^\x00-\x7F]+', '', content)
    return yaml.safe_load(content)

def filter_vless(data):
    filtered = []
    unique = set()
    if not data or 'proxies' not in data:
        return filtered
    for proxy in data['proxies']:
        if proxy.get('type') == 'vless' and proxy.get('port') == 80:
            uuid = proxy.get('uuid', '')
            host = proxy.get('host', '')
            url = f"vless://{uuid}@104.17.113.188:80/?security=none&encryption=none&headerType=none&type=ws&host={host}#YTLC.T "
            if url not in unique:
                filtered.append(url)
                unique.add(url)
    return filtered

def ping_server(host):
    param = '-n' if platform.system().lower() == 'windows' else '-c'
    try:
        process = subprocess.Popen(['ping', param, '1', '-W', '2', host], 
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout, _ = process.communicate(timeout=3)
        return True if process.returncode == 0 else False
    except:
        return False

def send_to_telegram(message):
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
    payload = {"chat_id": TELEGRAM_CHAT_ID, "text": message, "parse_mode": "Markdown"}
    requests.post(url, json=payload)

def main():
    content = get_gist_content(GIST_URL)
    if not content: return
    
    data = parse_yaml(content)
    configs = filter_vless(data)
    
    working_list = []
    print(f"Testing {len(configs)} configs...")
    
    for i, config in enumerate(configs):
        match = re.search(r"host=([^&]*)", config)
        host = match.group(1) if match else "8.8.8.8"
        
        if ping_server(host):
            final_link = f"{config}{i+1}"
            working_list.append(final_link)
    
    if working_list:
        header = f"✅ *Found {len(working_list)} Working Configs*\n\n"
        # Join links with backticks for easy copy-paste in Telegram
        body = "\n\n".join([f"`{link}`" for link in working_list])
        send_to_telegram(header + body)
        print("Sent to Telegram!")
    else:
        send_to_telegram("❌ No working configs found in this run.")

if __name__ == "__main__":
    main()
