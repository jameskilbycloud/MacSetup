# MacSetup shared helpers — colour vars and log_* functions.
# Sourced by every script in this repo; not meant to be executed directly.
# shellcheck shell=bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_header()  { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════${NC}"; \
                echo -e "${BOLD}${CYAN}  $1${NC}"; \
                echo -e "${BOLD}${CYAN}══════════════════════════════════════${NC}\n"; }
