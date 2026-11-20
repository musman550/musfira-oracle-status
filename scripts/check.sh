#!/bin/bash
# Musfira AI external watchdog. Pings the Oracle VM (via its public tunnel URL)
# and the Vercel app from GitHub's servers. Writes summary.txt. Exit code:
#   0 = everything fine, 1 = something needs attention.
set +e
ORACLE_URL="$(tr -d '[:space:]' < oracle-url.txt 2>/dev/null)"
VERCEL_URL="${VERCEL_URL:-https://musfira-ai.vercel.app}"
: > summary.txt
rc=0
say() { echo "$*" | tee -a summary.txt; }

# --- Oracle VM (Gemini automation) --------------------------------------
H=""; up=0
for i in 1 2 3; do
  H=$(curl -s --max-time 25 "$ORACLE_URL/api/health")
  if echo "$H" | grep -q '"status": *"ok"'; then up=1; break; fi
  sleep 10
done
if [ "$up" = 1 ]; then
  if echo "$H" | grep -q '"logged_in": *false'; then
    say "ORACLE: reachable, but the Google/Gemini session is EXPIRED (logged_in=false). ACTION NEEDED: run start.bat then push_session.bat on the PC."
    rc=1
  elif echo "$H" | grep -q '"browser_running": *false'; then
    say "ORACLE: reachable but the browser inside the container is not running (VM keepalive should restart it within the hour)."
    rc=1
  else
    say "ORACLE: OK ($ORACLE_URL)"
  fi
else
  say "ORACLE: DOWN - no answer from $ORACLE_URL (VM, container or Cloudflare tunnel is down). Vercel keeps answering through Groq meanwhile."
  rc=1
fi

# --- Vercel app -----------------------------------------------------------
C=$(curl -s --max-time 25 "$VERCEL_URL/api/config")
if echo "$C" | grep -q 'serverRotation'; then
  say "VERCEL config: OK"
else
  say "VERCEL: /api/config did not answer correctly (site may be down or a deploy failed)."
  rc=1
fi
G=$(curl -s --max-time 25 -X POST "$VERCEL_URL/api/chat" -H 'Content-Type: application/json' -d '{"message":"hi"}')
if echo "$G" | grep -q '"type": *"text"'; then
  say "VERCEL chat function: OK"
else
  say "VERCEL: /api/chat did not return a reply (function error?)."
  rc=1
fi
exit $rc
