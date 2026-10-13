"""
IT Infrastructure Event Log Generation Script
Generates 50 million rows of event logs, split across 10 files, that can be correlated with ServiceNow incident data
"""
import csv
import gzip
import random
import uuid
from datetime import datetime, timedelta

TOTAL_ROWS = 50_000_000
NUM_FILES = 10
ROWS_PER_FILE = TOTAL_ROWS // NUM_FILES
OUTPUT_DIR = "."
OUTPUT_PREFIX = "it_event_logs"

CATEGORIES = {
    "inquiry": 0.40,
    "software": 0.25,
    "hardware": 0.15,
    "network": 0.12,
    "database": 0.08,
}

EVENT_TYPES = ["INFO", "WARNING", "ERROR", "CRITICAL"]
EVENT_TYPE_WEIGHTS = [0.50, 0.25, 0.15, 0.10]

SERVERS = [f"srv-{role}-{i:02d}" for role in ["web", "app", "db", "net", "mail", "file", "proxy", "dns", "vpn", "auth"] for i in range(1, 6)]

DESCRIPTIONS = {
    "inquiry": [
        "User login session started",
        "Password reset request received",
        "Account lockout detected",
        "MFA verification completed",
        "Service desk portal accessed",
        "User profile update detected",
        "Session timeout occurred",
        "Access request submitted",
    ],
    "software": [
        "Application deployment completed",
        "Package update available",
        "License validation failed",
        "Memory threshold exceeded",
        "Application crash dump generated",
        "Configuration change detected",
        "Plugin compatibility warning",
        "Patch installation pending",
    ],
    "hardware": [
        "Disk space threshold warning",
        "CPU utilization spike detected",
        "Memory usage above 90%",
        "Fan speed abnormal",
        "Power supply redundancy lost",
        "RAID array degraded",
        "Temperature sensor alert",
        "Hardware health check completed",
    ],
    "network": [
        "Interface flapping detected",
        "Packet loss above threshold",
        "Latency spike on WAN link",
        "Firewall rule updated",
        "VPN tunnel reconnected",
        "DNS resolution failure",
        "BGP peer state change",
        "Bandwidth utilization warning",
    ],
    "database": [
        "Long running query detected",
        "Deadlock resolved automatically",
        "Tablespace usage above 80%",
        "Backup completed successfully",
        "Replication lag detected",
        "Connection pool exhausted",
        "Index fragmentation warning",
        "Transaction log full",
    ],
}

START_DATE = datetime(2015, 1, 1)
END_DATE = datetime(2026, 6, 30)
TOTAL_SECONDS = int((END_DATE - START_DATE).total_seconds())

HEADER = ["event_id", "timestamp", "server_name", "event_type", "severity", "category", "description", "source_ip"]

categories = list(CATEGORIES.keys())
cat_weights = list(CATEGORIES.values())


def generate_row():
    cat = random.choices(categories, weights=cat_weights, k=1)[0]
    evt = random.choices(EVENT_TYPES, weights=EVENT_TYPE_WEIGHTS, k=1)[0]
    severity_map = {"INFO": 1, "WARNING": 2, "ERROR": 3, "CRITICAL": random.choice([4, 5])}
    ts = START_DATE + timedelta(seconds=random.randint(0, TOTAL_SECONDS))

    return [
        str(uuid.uuid4()),
        ts.strftime("%Y-%m-%d %H:%M:%S"),
        random.choice(SERVERS),
        evt,
        severity_map[evt],
        cat,
        random.choice(DESCRIPTIONS[cat]),
        f"10.{random.randint(1, 254)}.{random.randint(1, 254)}.{random.randint(1, 254)}",
    ]


def main():
    import os
    print(f"Generating {TOTAL_ROWS:,} rows across {NUM_FILES} files...")
    for file_idx in range(NUM_FILES):
        filename = os.path.join(OUTPUT_DIR, f"{OUTPUT_PREFIX}_{file_idx:02d}.csv.gz")
        print(f"  File {file_idx + 1}/{NUM_FILES}: {filename}")
        with gzip.open(filename, "wt", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(HEADER)
            for i in range(ROWS_PER_FILE):
                writer.writerow(generate_row())
                if (i + 1) % 1_000_000 == 0:
                    print(f"    {i + 1:,} / {ROWS_PER_FILE:,} rows")
        print(f"    Done: {filename}")
    print(f"All {NUM_FILES} files generated ({TOTAL_ROWS:,} total rows)")


if __name__ == "__main__":
    main()
