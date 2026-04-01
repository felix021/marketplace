#!/usr/bin/env python3
"""DNSPod (Tencent Cloud DNS) CLI tool using TC3-HMAC-SHA256 signing."""

import hashlib
import hmac
import json
import os
import sys
import time
from datetime import datetime, timezone
from urllib.parse import urlencode

import urllib.request
import urllib.error

SERVICE = "dnspod"
HOST = "dnspod.tencentcloudapi.com"
ENDPOINT = f"https://{HOST}"
REGION = ""
ACTION_MAP = {
    "list-domains": "DescribeDomainList",
    "list-records": "DescribeRecordList",
    "create-record": "CreateRecord",
    "modify-record": "ModifyRecord",
    "delete-record": "DeleteRecord",
    "toggle-record": "ModifyRecordStatus",
}


def get_credentials():
    secret_id = os.environ.get("DNSPOD_ID", "")
    secret_key = os.environ.get("DNSPOD_KEY", "")
    if not secret_id or not secret_key:
        print("Error: DNSPOD_ID and DNSPOD_KEY environment variables must be set.", file=sys.stderr)
        sys.exit(1)
    return secret_id, secret_key


def sign(key, msg):
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def make_request(action, payload):
    secret_id, secret_key = get_credentials()
    timestamp = int(time.time())
    date = datetime.fromtimestamp(timestamp, tz=timezone.utc).strftime("%Y-%m-%d")

    http_method = "POST"
    canonical_uri = "/"
    canonical_querystring = ""
    ct = "application/json; charset=utf-8"
    payload_str = json.dumps(payload)
    hashed_payload = hashlib.sha256(payload_str.encode("utf-8")).hexdigest()

    headers = {
        "content-type": ct,
        "host": HOST,
        "x-tc-action": action.lower(),
    }
    canonical_headers = f"content-type:{ct}\nhost:{HOST}\nx-tc-action:{action.lower()}\n"
    signed_headers = "content-type;host;x-tc-action"

    canonical_request = "\n".join([
        http_method, canonical_uri, canonical_querystring,
        canonical_headers, signed_headers, hashed_payload,
    ])

    algorithm = "TC3-HMAC-SHA256"
    credential_scope = f"{date}/{SERVICE}/tc3_request"
    hashed_canonical = hashlib.sha256(canonical_request.encode("utf-8")).hexdigest()
    string_to_sign = "\n".join([algorithm, str(timestamp), credential_scope, hashed_canonical])

    secret_date = sign(("TC3" + secret_key).encode("utf-8"), date)
    secret_service = sign(secret_date, SERVICE)
    secret_signing = sign(secret_service, "tc3_request")
    signature = hmac.new(secret_signing, string_to_sign.encode("utf-8"), hashlib.sha256).hexdigest()

    authorization = (
        f"{algorithm} Credential={secret_id}/{credential_scope}, "
        f"SignedHeaders={signed_headers}, Signature={signature}"
    )

    req = urllib.request.Request(ENDPOINT, data=payload_str.encode("utf-8"), method="POST")
    req.add_header("Content-Type", ct)
    req.add_header("Host", HOST)
    req.add_header("X-TC-Action", action)
    req.add_header("X-TC-Timestamp", str(timestamp))
    req.add_header("X-TC-Version", "2021-03-23")
    req.add_header("Authorization", authorization)

    try:
        with urllib.request.urlopen(req) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            return result
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8")
        print(f"HTTP Error {e.code}: {body}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Request failed: {e}", file=sys.stderr)
        sys.exit(1)


def print_json(data):
    print(json.dumps(data, indent=2, ensure_ascii=False))


def list_domains(args):
    offset = int(args[0]) if args else 0
    limit = int(args[1]) if len(args) > 1 else 100
    result = make_request("DescribeDomainList", {"Offset": offset, "Limit": limit})
    if "Response" in result:
        resp = result["Response"]
        domains = resp.get("DomainList", [])
        if not domains:
            print("No domains found.")
            return
        print(f"{'Domain':<40} {'Status':<10} {'Grade':<10}")
        print("-" * 60)
        for d in domains:
            status = "ENABLE" if d.get("Status") == "ENABLE" else d.get("Status", "?")
            print(f"{d.get('Name', '?'):<40} {status:<10} {d.get('Grade', '?'):<10}")
        total = resp.get("DomainCountInfo", {}).get("DomainTotal", len(domains))
        print(f"\nTotal: {total}, Shown: {len(domains)}")
    else:
        print_json(result)


def list_records(args):
    if not args:
        print("Usage: dnspod.py list-records <domain> [sub_domain] [record_type]", file=sys.stderr)
        sys.exit(1)
    domain = args[0]
    payload = {"Domain": domain, "Offset": 0, "Limit": 300}
    if len(args) > 1:
        payload["SubDomain"] = args[1]
    if len(args) > 2:
        payload["RecordType"] = args[2].upper()
    result = make_request("DescribeRecordList", payload)
    if "Response" in result:
        resp = result["Response"]
        records = resp.get("RecordList", [])
        if not records:
            print(f"No records found for {domain}.")
            return
        print(f"{'ID':<12} {'SubDomain':<25} {'Type':<6} {'Value':<40} {'TTL':<6} {'Status'}")
        print("-" * 110)
        for r in records:
            status = "ON" if r.get("Status") == "ENABLE" else "OFF"
            sub = r.get("Name", "@")
            line = r.get("Line", "默认")
            val = r.get("Value", "?")
            if len(val) > 38:
                val = val[:35] + "..."
            print(f"{r.get('RecordId', '?'):<12} {sub:<25} {r.get('Type', '?'):<6} {val:<40} {r.get('TTL', '?'):<6} {status}")
        print(f"\nTotal: {resp.get('TotalCount', '?')}, Shown: {len(records)}")
    else:
        print_json(result)


def create_record(args):
    if len(args) < 4:
        print("Usage: dnspod.py create-record <domain> <sub_domain> <type> <value> [line] [ttl]", file=sys.stderr)
        sys.exit(1)
    domain, sub, rtype, value = args[0], args[1], args[2].upper(), args[3]
    line = args[4] if len(args) > 4 else "默认"
    ttl = int(args[5]) if len(args) > 5 else 600
    payload = {
        "Domain": domain,
        "SubDomain": sub,
        "RecordType": rtype,
        "RecordLine": line,
        "Value": value,
        "TTL": ttl,
    }
    result = make_request("CreateRecord", payload)
    if "Response" in result:
        resp = result["Response"]
        rid = resp.get("RecordId", "?")
        print(f"Record created: ID={rid}, {sub}.{domain} -> {value} ({rtype})")
    else:
        print_json(result)


def modify_record(args):
    if len(args) < 5:
        print("Usage: dnspod.py modify-record <domain> <record_id> <sub_domain> <type> <value> [line] [ttl]", file=sys.stderr)
        sys.exit(1)
    domain, rid, sub, rtype, value = args[0], int(args[1]), args[2], args[3].upper(), args[4]
    line = args[5] if len(args) > 5 else "默认"
    ttl = int(args[6]) if len(args) > 6 else 600
    payload = {
        "Domain": domain,
        "RecordId": rid,
        "SubDomain": sub,
        "RecordType": rtype,
        "RecordLine": line,
        "Value": value,
        "TTL": ttl,
    }
    result = make_request("ModifyRecord", payload)
    if "Response" in result:
        print(f"Record {rid} modified: {sub}.{domain} -> {value} ({rtype})")
    else:
        print_json(result)


def delete_record(args):
    if len(args) < 2:
        print("Usage: dnspod.py delete-record <domain> <record_id>", file=sys.stderr)
        sys.exit(1)
    domain, rid = args[0], int(args[1])
    result = make_request("DeleteRecord", {"Domain": domain, "RecordId": rid})
    if "Response" in result:
        print(f"Record {rid} deleted from {domain}.")
    else:
        print_json(result)


def toggle_record(args):
    if len(args) < 3:
        print("Usage: dnspod.py toggle-record <domain> <record_id> <enable|disable>", file=sys.stderr)
        sys.exit(1)
    domain, rid = args[0], int(args[1])
    status_map = {"enable": "ENABLE", "disable": "DISABLE", "on": "ENABLE", "off": "DISABLE"}
    status = status_map.get(args[2].lower())
    if not status:
        print("Status must be enable/disable or on/off", file=sys.stderr)
        sys.exit(1)
    result = make_request("ModifyRecordStatus", {"Domain": domain, "RecordId": rid, "Status": status})
    if "Response" in result:
        print(f"Record {rid} status changed to {status}.")
    else:
        print_json(result)


def show_help():
    print("Usage: dnspod.py <command> [args...]")
    print("\nCommands:")
    print("  list-domains [offset] [limit]")
    print("    List all domains in your DNSPod account.")
    print()
    print("  list-records <domain> [sub_domain] [type]")
    print("    List DNS records for a domain, optionally filtered by subdomain and/or type.")
    print()
    print("  create-record <domain> <sub_domain> <type> <value> [line] [ttl]")
    print("    Create a new DNS record. Default line: 默认, default TTL: 600.")
    print()
    print("  modify-record <domain> <record_id> <sub_domain> <type> <value> [line] [ttl]")
    print("    Modify an existing DNS record. Get record_id from list-records first.")
    print()
    print("  delete-record <domain> <record_id>")
    print("    Delete a DNS record. This action is irreversible!")
    print()
    print("  toggle-record <domain> <record_id> <enable|disable>")
    print("    Enable or disable a DNS record.")
    print()
    print("  help")
    print("    Show this help message.")
    print("\nEnvironment variables:")
    print("  DNSPOD_ID   Tencent Cloud SecretId (starts with AKID)")
    print("  DNSPOD_KEY  Tencent Cloud SecretKey")
    print("\nExamples:")
    print("  python3 dnspod.py list-domains")
    print("  python3 dnspod.py list-records example.com")
    print("  python3 dnspod.py list-records example.com www A")
    print("  python3 dnspod.py create-record example.com www A 1.2.3.4")
    print("  python3 dnspod.py create-record example.com blog CNAME cdn.example.com")
    print("  python3 dnspod.py modify-record example.com 12345 www A 9.8.7.6")
    print("  python3 dnspod.py toggle-record example.com 12345 disable")
    print("  python3 dnspod.py delete-record example.com 12345")


COMMANDS = {
    "list-domains": list_domains,
    "list-records": list_records,
    "create-record": create_record,
    "modify-record": modify_record,
    "delete-record": delete_record,
    "toggle-record": toggle_record,
    "help": lambda args: show_help(),
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help", "help"):
        show_help()
        sys.exit(0)

    cmd = sys.argv[1]
    if cmd not in COMMANDS:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        print(f"Available: {', '.join(COMMANDS.keys())}", file=sys.stderr)
        sys.exit(1)

    COMMANDS[cmd](sys.argv[2:])


if __name__ == "__main__":
    main()
