#!/usr/bin/env python3
import requests
import time
import sys
import re
import json
import os
from datetime import datetime

# ---- CONFIG ----
TIMEOUT = 60
LOGFILE = "/var/www/html/newperformance/webmail/roundcube_results.json"

session = requests.Session()


def extract_json_object(text, start_pos):
    brace_count = 0
    for i in range(start_pos, len(text)):
        if text[i] == '{':
            brace_count += 1
        elif text[i] == '}':
            brace_count -= 1
            if brace_count == 0:
                return text[start_pos:i+1]
    return None


def append_json_line(filepath, obj):
    """
    Append JSON safely without breaking permissions or overwriting file.
    """
    os.makedirs(os.path.dirname(filepath), exist_ok=True)

    with open(filepath, "a") as f:
        f.write(json.dumps(obj) + "\n")


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <Roundcube_URL> <username> <password>")
        sys.exit(1)

    roundcube_url = sys.argv[1].rstrip('/')
    username = sys.argv[2]
    password = sys.argv[3]

    login_path = "/?_task=login"
    ajax_inbox_path = "/?_task=mail&_action=list&_mbox=INBOX&_remote=1"

    hostname = os.uname().nodename
    timestamp = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

    try:
        start_time = time.time()

        # 1. Load login page
        login_page = session.get(roundcube_url, timeout=TIMEOUT)
        token = re.search(r'name="_token" value="([^"]+)"', login_page.text)

        if not token:
            result = {
                "timestamp": timestamp,
                "hostname": hostname,
                "status": "failed",
                "step": "csrf_token",
                "url": roundcube_url,
                "error": "unable to extract csrf token"
            }
            append_json_line(LOGFILE, result)
            sys.exit(2)

        token_value = token.group(1)

        # 2. Login
        payload = {
            "_token": token_value,
            "_task": "login",
            "_action": "login",
            "_user": username,
            "_pass": password
        }

        login_response = session.post(roundcube_url + login_path, data=payload, timeout=TIMEOUT)

        if "login failed" in login_response.text.lower():
            result = {
                "timestamp": timestamp,
                "hostname": hostname,
                "status": "failed",
                "step": "login",
                "url": roundcube_url,
                "user": username
            }
            append_json_line(LOGFILE, result)
            sys.exit(2)

        # 3. Inbox request
        headers = {
            "X-Requested-With": "XMLHttpRequest",
            "Referer": roundcube_url + "/?_task=mail&_mbox=INBOX"
        }

        inbox_response = session.get(roundcube_url + ajax_inbox_path, headers=headers, timeout=TIMEOUT)

        response_text = inbox_response.text

        # 4. Extract email count
        total_count = 0
        env_key = '"env":'

        pos = response_text.find(env_key)
        if pos != -1:
            start = response_text.find('{', pos)
            if start != -1:
                env_json_str = extract_json_object(response_text, start)
                try:
                    env = json.loads(env_json_str)
                    total_count = int(env.get("messagecount", 0))
                except Exception:
                    total_count = 0

        elapsed = time.time() - start_time

        # 5. FINAL JSON OUTPUT
        result = {
            "timestamp": timestamp,
            "hostname": hostname,
            "status": "success",
            "url": roundcube_url,
            "user": username,
            "response_time_s": round(elapsed, 3),
            "response_time_ms": round(elapsed * 1000, 2),
            "total_emails": total_count
        }

        append_json_line(LOGFILE, result)

        print(json.dumps(result))

    except Exception as e:
        result = {
            "timestamp": timestamp,
            "hostname": hostname,
            "status": "error",
            "error": str(e),
            "url": roundcube_url
        }

        append_json_line(LOGFILE, result)
        print(json.dumps(result))
        sys.exit(2)


if __name__ == "__main__":
    main()
