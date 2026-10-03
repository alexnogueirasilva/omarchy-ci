#!/usr/bin/env python3
"""GitHub Actions snapshot for the alex.ci bar widget.

`poll` prints the latest run of each workflow on each branch, keeping a run
only while that line of work is still active and still failing or in progress.
`log <repo> <run-id>` prints one JSON object with the cleaned failed log.
"""

import glob
import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone

REPOS = [
    "devaction-labs/signetum",
    "devaction-labs/fiscal-gateway",
    "devaction-labs/app-nexus",
    "devaction-labs/nexus_pro",
    "devaction-labs/lighthouse-api",
    "devaction-labs/mesh.api.br",
]

# The panel only lists a run that is still going or that failed.
# A success, a cancel, or a skip stays off the bar.
VISIBLE = {
    "in_progress",
    "queued",
    "waiting",
    "failure",
    "timed_out",
    "startup_failure",
}

RANK = {
    "in_progress": 0,
    "queued": 1,
    "waiting": 1,
    "failure": 2,
    "timed_out": 2,
    "startup_failure": 2,
}


def find_gh():
    patterns = [
        os.path.expanduser("~/.local/share/mise/installs/gh/latest/*/bin/gh"),
        os.path.expanduser("~/.local/share/mise/installs/gh/*/bin/gh"),
    ]
    found = []
    for pattern in patterns:
        found.extend(glob.glob(pattern))
    found.sort(reverse=True)
    for path in found:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    return "gh"


GH = find_gh()


def run(args, timeout):
    return subprocess.run(
        [GH, *args],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def latest_per_line(runs):
    """Newest run of one workflow on one branch. A later pass replaces a failure."""
    grouped = {}
    for item in runs:
        key = (item["repo"], item["name"], item["branch"])
        current = grouped.get(key)
        if current is None or item["updatedAt"] > current["updatedAt"]:
            grouped[key] = item
    return list(grouped.values())


def branch_pr(repo, branch, cache):
    """Open, merged, or closed PR for this head, if GitHub has one."""
    key = (repo, branch)
    if key in cache:
        return cache[key]
    result = run(
        [
            "pr", "list", "--repo", repo, "--head", branch, "--state", "all",
            "--limit", "5", "--json", "number,state,updatedAt",
        ],
        20,
    )
    chosen = None
    if result.returncode == 0:
        try:
            pulls = json.loads(result.stdout or "[]")
        except json.JSONDecodeError:
            pulls = []
        opens = [pull for pull in pulls if str(pull.get("state", "")).upper() == "OPEN"]
        pool = opens or pulls
        if pool:
            pool.sort(key=lambda pull: pull.get("updatedAt") or "", reverse=True)
            chosen = pool[0]
    cache[key] = chosen
    return chosen


def still_active(item, pull):
    """A merged or closed PR is finished. A Dependabot job on a trunk branch is not a live check."""
    state = str(pull.get("state", "")).upper() if pull else ""
    if pull is not None and state != "OPEN":
        return False
    if item.get("event") == "dynamic" and state != "OPEN":
        return False
    return True


def poll():
    runs = []
    errors = []
    for repo in REPOS:
        result = run(["api", f"repos/{repo}/actions/runs?per_page=30"], 25)
        if result.returncode != 0:
            message = (result.stderr or result.stdout or "falhou").strip().splitlines()
            errors.append(f"{repo}: {message[-1][:180] if message else 'falhou'}")
            continue
        try:
            payload = json.loads(result.stdout)
        except json.JSONDecodeError:
            errors.append(f"{repo}: resposta inválida")
            continue
        for item in payload.get("workflow_runs") or []:
            runs.append({
                "repo": repo,
                "id": item.get("id"),
                "name": item.get("name") or "",
                "title": item.get("display_title") or "",
                "branch": item.get("head_branch") or "",
                "event": item.get("event") or "",
                "status": item.get("status") or "",
                "conclusion": item.get("conclusion") or "",
                "url": item.get("html_url") or "",
                "updatedAt": item.get("updated_at") or "",
            })
    cutoff = datetime.now(timezone.utc) - timedelta(days=7)
    fresh = []
    for item in runs:
        try:
            when = datetime.fromisoformat(item["updatedAt"].replace("Z", "+00:00"))
        except ValueError:
            when = None
        if when is not None and when >= cutoff:
            fresh.append(item)
    runs = [
        item for item in latest_per_line(fresh)
        if (item["conclusion"] or item["status"]) in VISIBLE
    ]
    pulls = {}
    active = []
    for item in runs:
        pull = branch_pr(item["repo"], item["branch"], pulls)
        if still_active(item, pull):
            item.pop("event", None)
            active.append(item)
    runs = active
    runs.sort(key=lambda item: item["updatedAt"], reverse=True)
    runs.sort(key=lambda item: RANK.get(item["conclusion"] or item["status"], 6))
    json.dump({"runs": runs, "errors": errors}, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


def clean_line(line):
    body = line.split("\t")[-1]
    marker = body.find("Z ")
    if 20 <= marker <= 36 and body[4:5] == "-" and "T" in body[:marker]:
        body = body[marker + 2 :]
    return body.rstrip()


def failed_log(repo, run_id):
    result = run(
        ["run", "view", str(run_id), "--repo", repo, "--log-failed"],
        90,
    )
    raw = result.stdout or ""
    if not raw.strip():
        note = (result.stderr or "").strip() or "Essa run não tem log de falha."
        json.dump({"text": note}, sys.stdout, ensure_ascii=False)
        sys.stdout.write("\n")
        return
    lines = [clean_line(line) for line in raw.splitlines()]
    lines = [line for line in lines if line and not line.startswith("##[group") and line != "##[endgroup]"]
    interesting = [
        line for line in lines
        if line.startswith("##[error]") or line.startswith("** (") or " error:" in line.lower() or line.lower().startswith("error")
    ]
    specific = [line for line in interesting if not line.startswith("##[error]Process completed")]
    chosen = specific[-40:] if specific else interesting[-20:] or lines[-40:]
    text = "\n".join(chosen)
    if len(text) > 14000:
        text = text[-14000:]
    json.dump({"text": text}, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "poll"
    if command == "poll":
        poll()
        return
    if command == "log" and len(sys.argv) == 4:
        failed_log(sys.argv[2], sys.argv[3])
        return
    json.dump({"error": "uso: ci.py poll | ci.py log owner/repo run-id"}, sys.stdout)
    sys.stdout.write("\n")
    sys.exit(2)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        json.dump({"error": str(exc)}, sys.stdout, ensure_ascii=False)
        sys.stdout.write("\n")
        sys.exit(1)
