#!/usr/bin/env bash
# =============================================================================
# Tears down the Azure SRE Agent Demo Lab infrastructure.
#
# Usage:
#   ./scripts/destroy.sh                                          # Interactive
#   ./scripts/destroy.sh --resource-group "rg-srelab-eastus2"     # Specify RG
#   ./scripts/destroy.sh --force                                  # Skip confirmation
#
# Parameters:
#   -g, --resource-group  Resource group to delete. Default: rg-srelab-eastus2
#   -f, --force           Skip confirmation prompt
# =============================================================================

set -euo pipefail

# Defaults
RESOURCE_GROUP="rg-srelab-eastus2"
FORCE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-g resource-group] [-f|--force]"
            echo ""
            echo "Options:"
            echo "  -g, --resource-group  Resource group to delete. Default: rg-srelab-eastus2"
            echo "  -f, --force           Skip confirmation prompt"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

echo -e "${RED}"
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                    Azure SRE Agent Demo Lab - DESTROY                        ║"
echo "║                                                                              ║"
echo "║                         ⚠️  WARNING ⚠️                                        ║"
echo "║                                                                              ║"
echo "║  This will PERMANENTLY DELETE all resources in the resource group!           ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if resource group exists
rg_json=$(az group show --name "$RESOURCE_GROUP" --output json 2>/dev/null) || true

if [[ -z "$rg_json" ]]; then
    echo -e "${YELLOW}❌ Resource group '${RESOURCE_GROUP}' not found.${NC}"
    exit 0
fi

rg_location=$(echo "$rg_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['location'])")

echo -e "${WHITE}📋 Resource Group: ${RESOURCE_GROUP}${NC}"
echo -e "${WHITE}📍 Location: ${rg_location}${NC}"

# List resources
echo -e "\n${YELLOW}📦 Resources to be deleted:${NC}"
resources_json=$(az resource list --resource-group "$RESOURCE_GROUP" --output json)
resource_count=$(echo "$resources_json" | python3 -c "import sys,json; data=json.load(sys.stdin); [print(f'   • {r[\"type\"]} - {r[\"name\"]}') for r in data]; print(f'\n  Total: {len(data)} resources')")
echo -e "${GRAY}${resource_count}${NC}"

# Confirmation
if [[ "$FORCE" != "true" ]]; then
    echo -e "\n${RED}⚠️  This action cannot be undone!${NC}"
    read -rp "Type 'DELETE' to confirm: " confirm

    if [[ "$confirm" != "DELETE" ]]; then
        echo -e "\n${GREEN}Destroy cancelled.${NC}"
        exit 0
    fi
fi

# Delete resource group
echo -e "\n${YELLOW}🗑️  Deleting resource group '${RESOURCE_GROUP}'...${NC}"
echo -e "   ${GRAY}This may take several minutes...${NC}"

if az group delete --name "$RESOURCE_GROUP" --yes --no-wait; then
    echo -e "\n${GREEN}✅ Resource group deletion initiated.${NC}"
    echo -e "   ${GRAY}The deletion is running in the background.${NC}"
    echo -e "   ${GRAY}Check Azure Portal for status.${NC}"
else
    echo -e "\n${RED}❌ Failed to delete resource group.${NC}"
    exit 1
fi

# Clean up local files
echo -e "\n${YELLOW}🧹 Cleaning up local files...${NC}"

OUTPUTS_FILE="${SCRIPT_DIR}/deployment-outputs.json"
if [[ -f "$OUTPUTS_FILE" ]]; then
    rm -f "$OUTPUTS_FILE"
    echo -e "   ${GREEN}✅ Removed deployment-outputs.json${NC}"
fi

# Remove kubectl context
echo -e "\n${YELLOW}🔑 Cleaning up kubectl context...${NC}"
kubectl config delete-context "aks-*" 2>/dev/null || true
echo -e "   ${GREEN}✅ kubectl context cleaned up${NC}"

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                        Cleanup Complete! 🧹                                   ║"
echo "╠══════════════════════════════════════════════════════════════════════════════╣"
echo "║                                                                              ║"
echo "║  The resource group deletion is in progress.                                 ║"
echo "║  Monitor progress in Azure Portal or run:                                    ║"
echo "║                                                                              ║"
printf "║    az group show --name %-39s║\n" "$RESOURCE_GROUP"
echo "║                                                                              ║"
echo "║  Don't forget to also delete your SRE Agent if you created one!              ║"
echo "║                                                                              ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
