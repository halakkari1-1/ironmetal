#!/usr/bin/env bash
# Waits for a GitHub Actions run to finish, then prints its result and the failing step (if any).
# Usage: tools/watch-build.sh <run_id>
set -u
RUN="$1"; REPO="halakkari1-1/ironmetal"; API="https://api.github.com/repos/$REPO/actions"
until [ "$(curl -sS "$API/runs/$RUN" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("status"))')" = "completed" ]; do sleep 20; done
curl -sS "$API/runs/$RUN" | python3 -c 'import json,sys;r=json.load(sys.stdin);print("RUN", r["id"], r["conclusion"], r["html_url"])'
curl -sS "$API/runs/$RUN/jobs" | python3 -c '
import json,sys
for j in json.load(sys.stdin).get("jobs",[]):
  print("JOB", j["name"], j["conclusion"])
  for s in j.get("steps",[]):
    print("  STEP", s["number"], s["name"], s["conclusion"])'
