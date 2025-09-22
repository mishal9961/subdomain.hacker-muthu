#!/bin/bash

# ── Color Codes ───────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ── Tool Name ────────────────────────────────
toolname="Hacker Muthu"

# ── Loading Spinner Function ─────────────────
loading_animation() {
  local message=$1
  local i=0
  local chars="/—\\|"

  trap "printf '\r'; exit" SIGTERM SIGINT

  while true; do
    printf "\r%s %c" "$message" "${chars:i++%${#chars}:1}"
    sleep 0.1
  done
}

# ── Prompt for Domain ────────────────────────
read -p $'\033[0;36mEnter domain name (e.g., example.com): \033[0m' domain

# ── Input Validation ─────────────────────────
if [ -z "$domain" ]; then
  echo -e "${RED}❌ No domain entered. Exiting.${NC}"
  exit 1
fi

# ── Dependency Checks ────────────────────────
if ! command -v jq &>/dev/null; then
  echo -e "${RED}❌ 'jq' is required but not installed. Please install jq and try again.${NC}"
  exit 1
fi

if ! command -v dig &>/dev/null; then
  echo -e "${RED}❌ 'dig' command not found. Please install 'dnsutils' or equivalent.${NC}"
  exit 1
fi

# ── Start ─────────────────────────────────────
echo ""
echo -e "${CYAN}🔍 [$toolname] Gathering subdomains for: $domain from crt.sh${NC}"
echo "==========================================="

# ── Start Spinner for Fetch ──────────────────
loading_animation "Fetching subdomains from crt.sh" &
loader_pid=$!

# ── Make Request to crt.sh ───────────────────
curl -s -A "Mozilla/5.0" "https://crt.sh/?q=%25.$domain&output=json" > crt_response.json

# ── Stop Spinner ─────────────────────────────
kill "$loader_pid" &>/dev/null
wait "$loader_pid" 2>/dev/null
printf "\r%-40s\r" " "  # Clear line
echo -e "${GREEN}✅ Fetch complete!${NC}"

# ── Check for HTML Error Page ────────────────
if grep -qi "<!DOCTYPE html>" crt_response.json; then
  echo -e "${RED}❌ crt.sh returned an HTML error page.${NC}"
  echo -e "${YELLOW}⚠️  This often happens when the domain has too many certificates or the server is overloaded.${NC}"
  echo -e "${YELLOW}💡 Try again later or use a smaller domain (e.g., openai.com, stripe.com).${NC}"
  rm -f crt_response.json
  exit 1
fi

# ── Check for Valid JSON ─────────────────────
if ! jq empty crt_response.json &>/dev/null; then
  echo -e "${RED}❌ Invalid JSON received from crt.sh.${NC}"
  rm -f crt_response.json
  exit 1
fi

# ── Extract Subdomains ───────────────────────
jq -r '.[].name_value' crt_response.json | sed 's/\*\.//g' | sort -u > live_subs.txt
rm -f crt_response.json

# ── Check if any subdomains found ────────────
if [ ! -s live_subs.txt ]; then
  echo -e "${RED}❌ No subdomains found for this domain.${NC}"
  exit 1
fi

# ── Start Live DNS Resolution Check ──────────
echo ""
echo -e "${CYAN}🌐 [$toolname] Checking which subdomains are live...${NC}"
echo "------------------------------------------------------"

> live_only.txt  # Clear previous file

# ── Start Spinner for Live Check ─────────────
loading_animation "Checking subdomains" &
check_loader_pid=$!

# ── Loop Through Subdomains ──────────────────
while read -r sub; do
  ip=$(dig +short "$sub" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
  if [ -n "$ip" ]; then
    echo -e "${GREEN}[+] $sub → $ip${NC}"
    echo "$sub" >> live_only.txt
  fi
done < live_subs.txt

# ── Stop Spinner ─────────────────────────────
kill "$check_loader_pid" &>/dev/null
wait "$check_loader_pid" 2>/dev/null
printf "\r%-40s\r" " "  # Clear line

# ── Final Output ─────────────────────────────
echo ""
if [ -s live_only.txt ]; then
  echo -e "${YELLOW}✅ Done! Live subdomains saved to: live_only.txt${NC}"
  echo -e "${CYAN}🎯 Total live subdomains: $(wc -l < live_only.txt)${NC}"
else
  echo -e "${RED}❌ No live subdomains found.${NC}"
fi
