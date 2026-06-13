#!/usr/bin/env python3
import requests
import time
import sys
import re
import json
import os
import subprocess
from datetime import datetime
import tempfile
import shutil
import stat

# ---- CONFIG ----
TIMEOUT = 60
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


def jq_append_safe(file_path, obj):
    obj_json = json.dumps(obj)

    # Ensure directory exists
    os.makedirs(os.path.dirname(file_path), exist_ok=True)

    # If file doesn't exist, create empty JSON array
    if not os.path.exists(file_path):
        with open(file_path, "w") as f:
            f.write("[]")

    # Preserve original permissions
    orig_mode = stat.S_IMODE(os.stat(file_path).st_mode)

    # Create temp file in same directory (important for atomic mv)
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(file_path))
    os.close(tmp_fd)

    try:
        cmd = [
            "jq",
            "--argjson",
            "new",
            obj_json,
            ". + [$new]",
            file_path
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0:
            raise RuntimeError(result.stderr)

        # Write jq output to temp file
        with open(tmp_path, "w") as f:
            f.write(result.stdout)

        # Restore permissions explicitly
        os.chmod(tmp_path, orig_mode)

        # Atomic replace (does NOT change permissions of target inode)
        shutil.move(tmp_path, file_path)

    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <Roundcube_URL> <username> <password>")
        sys.exit(1)

    roundcube_url = sys.argv[1].rstrip('/')
    username = sys.argv[2]
    password = sys.argv[3]

    hostname = os.uname().nodename

    LOGFILE = f"/var/www/html/newperformance/webmail/roundcube_results_{hostname}.json"

    login_path = "/?_task=login"
    ajax_inbox_path = "/?_task=mail&_action=list&_mbox=INBOX&_remote=1"

    timestamp = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

    try:
        start_time = time.time()

        login_page = session.get(roundcube_url, timeout=TIMEOUT)
        token = re.search(r'name="_token" value="([^"]+)"', login_page.text)

        if not token:
            jq_append_safe(LOGFILE, {
                "timestamp": timestamp,
                "hostname": hostname,
                "status": "failed",
                "step": "csrf_token",
                "url": roundcube_url
            })
            sys.exit(2)

        token_value = token.group(1)

        payload = {
            "_token": token_value,
            "_task": "login",
            "_action": "login",
            "_user": username,
            "_pass": password
        }

        login_response = session.post(
            roundcube_url + login_path,
            data=payload,
            timeout=TIMEOUT
        )

        if "login failed" in login_response.text.lower():
            jq_append_safe(LOGFILE, {
                "timestamp": timestamp,
                "hostname": hostname,
                "status": "failed",
                "step": "login",
                "url": roundcube_url,
                "user": username
            })
            sys.exit(2)

        headers = {
            "X-Requested-With": "XMLHttpRequest",
            "Referer": roundcube_url + "/?_task=mail&_mbox=INBOX"
        }

        inbox_response = session.get(
            roundcube_url + ajax_inbox_path,
            headers=headers,
            timeout=TIMEOUT
        )

        total_count = 0
        pos = inbox_response.text.find('"env":')

        if pos != -1:
            start = inbox_response.text.find('{', pos)
            if start != -1:
                env_json_str = extract_json_object(inbox_response.text, start)
                try:
                    env = json.loads(env_json_str)
                    total_count = int(env.get("messagecount", 0))
                except Exception:
                    total_count = 0

        elapsed = time.time() - start_time

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

        jq_append_safe(LOGFILE, result)

        print(json.dumps(result))

    except Exception as e:
        jq_append_safe(LOGFILE, {
            "timestamp": timestamp,
            "hostname": hostname,
            "status": "error",
            "error": str(e),
            "url": roundcube_url
        })

        print(json.dumps({
            "timestamp": timestamp,
            "hostname": hostname,
            "status": "error",
            "error": str(e)
        }))

        sys.exit(2)


if __name__ == "__main__":
    main()
