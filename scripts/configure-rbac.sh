#!/usr/bin/env bash
# =============================================================================
# Configures RBAC permissions for Azure SRE Agent and related services.
#
# This script assigns necessary RBAC roles that cannot be reliably assigned
# through Bicep due to subscription policy restrictions.
#
# Usage:
#   ./scripts/configure-rbac.sh --resource-group "rg-srelab-eastus2"
#   ./scripts/configure-rbac.sh --resource-group "rg-srelab-eastus2" \
#       --sre-agent-principal-id "<object-id>"
#
# Parameters:
#   -g, --resource-group           Resource group (required)
#   --sre-agent-principal-id       Object ID of SRE Agent managed identity
#   --current-user-principal-id    Object ID of current user (auto-detected)
#
# This script is idempotent - safe to run multiple times.
# =============================================================================

set -euo pipefail

# Defaults
RESOURCE_GROUP=""
SRE_AGENT_PRINCIPAL_ID=""
CURRENT_USER_PRINCIPAL_ID=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --sre-agent-principal-id)
            SRE_AGENT_PRINCIPAL_ID="$2"
            shift 2
            ;;
        --current-user-principal-id)
            CURRENT_USER_PRINCIPAL_ID="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 -g <resource-group> [--sre-agent-principal-id <id>] [--current-user-principal-id <id>]"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

if [[ -z "$RESOURCE_GROUP" ]]; then
    echo -e "${RED}Error: --resource-group is required${NC}"
    exit 1
fi

# Helper: assign a role (idempotent)
set_role_assignment() {
    local scope="$1"
    local role="$2"
    local principal_id="$3"
    local principal_type="${4:-ServicePrincipal}"
    local description="$5"

    if [[ -z "$principal_id" ]]; then
        echo -e "    ${GRAY}⏭️  Skipping: No principal ID provided${NC}"
        return
    fi

    echo -e "    ${WHITE}📋 ${description}${NC}"

    # Check if already assigned
    existing=$(az role assignment list \
        --scope "$scope" \
        --role "$role" \
        --assignee "$principal_id" \
        --output json 2>/dev/null || echo "[]")

    count=$(echo "$existing" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

    if [[ "$count" -gt 0 ]]; then
        echo -e "       ${GREEN}✅ Already assigned${NC}"
        return
    fi

    if az role assignment create \
        --scope "$scope" \
        --role "$role" \
        --assignee-object-id "$principal_id" \
        --assignee-principal-type "$principal_type" \
        --output none 2>/dev/null; then
        echo -e "       ${GREEN}✅ Assigned successfully${NC}"
    else
        echo -e "       ${YELLOW}⚠️  Failed to assign (may be due to subscription policies)${NC}"
    fi
}

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                    Azure RBAC Configuration Script                            ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Get current user if not provided
if [[ -z "$CURRENT_USER_PRINCIPAL_ID" ]]; then
    echo -e "${YELLOW}🔍 Getting current user principal ID...${NC}"
    if user_json=$(az ad signed-in-user show --output json 2>/dev/null); then
        CURRENT_USER_PRINCIPAL_ID=$(echo "$user_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
        display_name=$(echo "$user_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['displayName'])")
        echo -e "  ${GREEN}✅ Current user: ${display_name} (${CURRENT_USER_PRINCIPAL_ID})${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Could not determine current user. Some role assignments may be skipped.${NC}"
    fi
fi

# Get resource group info
echo -e "\n${YELLOW}🔍 Getting resource group information...${NC}"
rg_json=$(az group show --name "$RESOURCE_GROUP" --output json 2>/dev/null) || {
    echo -e "${RED}Resource group '${RESOURCE_GROUP}' not found${NC}"
    exit 1
}

rg_location=$(echo "$rg_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['location'])")
echo -e "  ${GREEN}✅ Resource Group: ${RESOURCE_GROUP}${NC}"
echo -e "  ${GRAY}📍 Location: ${rg_location}${NC}"

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --output json | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

# Get AKS cluster info
echo -e "\n${YELLOW}🔍 Getting AKS cluster information...${NC}"
aks_json=$(az aks list --resource-group "$RESOURCE_GROUP" --output json 2>/dev/null || echo "[]")
aks_name=$(echo "$aks_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['name'] if d else '')" 2>/dev/null || echo "")
aks_id=$(echo "$aks_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')" 2>/dev/null || echo "")

if [[ -n "$aks_name" ]]; then
    echo -e "  ${GREEN}✅ AKS Cluster: ${aks_name}${NC}"
fi

# Assign roles
echo -e "\n${YELLOW}🔐 Assigning RBAC roles...${NC}"

# 1. AKS Cluster Admin for current user
if [[ -n "$CURRENT_USER_PRINCIPAL_ID" ]]; then
    echo -e "\n  ${CYAN}📌 AKS Cluster Access:${NC}"
    set_role_assignment \
        "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
        "Azure Kubernetes Service Cluster Admin Role" \
        "$CURRENT_USER_PRINCIPAL_ID" \
        "User" \
        "AKS Cluster Admin Role for current user"

    set_role_assignment \
        "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
        "Azure Kubernetes Service RBAC Cluster Admin" \
        "$CURRENT_USER_PRINCIPAL_ID" \
        "User" \
        "AKS RBAC Cluster Admin for current user"
fi

# 2. Key Vault roles
kv_id=$(az keyvault list --resource-group "$RESOURCE_GROUP" --output json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')" 2>/dev/null || echo "")

if [[ -n "$kv_id" && -n "$CURRENT_USER_PRINCIPAL_ID" ]]; then
    echo -e "\n  ${CYAN}📌 Key Vault Access:${NC}"
    set_role_assignment \
        "$kv_id" \
        "Key Vault Administrator" \
        "$CURRENT_USER_PRINCIPAL_ID" \
        "User" \
        "Key Vault Administrator for current user"
fi

# 3. SRE Agent roles (if SRE Agent is already created)
if [[ -n "$SRE_AGENT_PRINCIPAL_ID" ]]; then
    echo -e "\n  ${CYAN}📌 SRE Agent Access:${NC}"

    set_role_assignment \
        "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
        "Contributor" \
        "$SRE_AGENT_PRINCIPAL_ID" \
        "ServicePrincipal" \
        "Contributor for SRE Agent (read/write access to resources)"

    set_role_assignment \
        "/subscriptions/${SUBSCRIPTION_ID}" \
        "Reader" \
        "$SRE_AGENT_PRINCIPAL_ID" \
        "ServicePrincipal" \
        "Reader for SRE Agent at subscription level"

    if [[ -n "$aks_id" ]]; then
        echo -e "\n  ${CYAN}📌 SRE Agent AKS Access:${NC}"

        set_role_assignment "$aks_id" \
            "Azure Kubernetes Service Cluster Admin Role" \
            "$SRE_AGENT_PRINCIPAL_ID" \
            "ServicePrincipal" \
            "AKS Cluster Admin for SRE Agent (kubectl access)"

        set_role_assignment "$aks_id" \
            "Azure Kubernetes Service RBAC Cluster Admin" \
            "$SRE_AGENT_PRINCIPAL_ID" \
            "ServicePrincipal" \
            "AKS RBAC Cluster Admin for SRE Agent (full K8s permissions)"

        set_role_assignment "$aks_id" \
            "Azure Kubernetes Service Contributor Role" \
            "$SRE_AGENT_PRINCIPAL_ID" \
            "ServicePrincipal" \
            "AKS Contributor for SRE Agent (scale nodes, update config)"
    fi

    # Log Analytics
    la_id=$(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" --output json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')" 2>/dev/null || echo "")
    if [[ -n "$la_id" ]]; then
        set_role_assignment "$la_id" \
            "Log Analytics Contributor" \
            "$SRE_AGENT_PRINCIPAL_ID" \
            "ServicePrincipal" \
            "Log Analytics Contributor for SRE Agent (query and manage logs)"
    fi

    # Application Insights
    ai_id=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Insights/components" --output json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')" 2>/dev/null || echo "")
    if [[ -n "$ai_id" ]]; then
        set_role_assignment "$ai_id" \
            "Monitoring Reader" \
            "$SRE_AGENT_PRINCIPAL_ID" \
            "ServicePrincipal" \
            "Monitoring Reader for SRE Agent on Application Insights"
    fi

    # Azure Monitor Workspace
    amw_id=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Monitor/accounts" --output json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')" 2>/dev/null || echo "")
    if [[ -n "$amw_id" ]]; then
        set_role_assignment "$amw_id" \
            "Monitoring Reader" \
            "$SRE_AGENT_PRINCIPAL_ID" \
            "ServicePrincipal" \
            "Monitoring Reader for SRE Agent on Azure Monitor Workspace"
    fi

    # Key Vault
    if [[ -n "$kv_id" ]]; then
        set_role_assignment "$kv_id" \
            "Key Vault Secrets Officer" \
            "$SRE_AGENT_PRINCIPAL_ID" \
            "ServicePrincipal" \
            "Key Vault Secrets Officer for SRE Agent (manage secrets)"
    fi

    # Container Registry
    acr_id=$(az acr list --resource-group "$RESOURCE_GROUP" --output json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')" 2>/dev/null || echo "")
    if [[ -n "$acr_id" ]]; then
        set_role_assignment "$acr_id" \
            "AcrPush" \
            "$SRE_AGENT_PRINCIPAL_ID" \
            "ServicePrincipal" \
            "ACR Push for SRE Agent (push/pull images)"
    fi
fi

# 4. Grafana roles
grafana_json=$(az grafana list --resource-group "$RESOURCE_GROUP" --output json 2>/dev/null || echo "[]")
grafana_id=$(echo "$grafana_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')" 2>/dev/null || echo "")
grafana_principal=$(echo "$grafana_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['identity']['principalId'] if d else '')" 2>/dev/null || echo "")

if [[ -n "$grafana_id" ]]; then
    echo -e "\n  ${CYAN}📌 Grafana Access:${NC}"

    set_role_assignment \
        "/subscriptions/${SUBSCRIPTION_ID}" \
        "Monitoring Reader" \
        "$grafana_principal" \
        "ServicePrincipal" \
        "Monitoring Reader for Grafana"

    if [[ -n "$CURRENT_USER_PRINCIPAL_ID" ]]; then
        set_role_assignment \
            "$grafana_id" \
            "Grafana Admin" \
            "$CURRENT_USER_PRINCIPAL_ID" \
            "User" \
            "Grafana Admin for current user"
    fi
fi

# Final summary
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                      RBAC Configuration Complete ✅                           ║"
echo "╠══════════════════════════════════════════════════════════════════════════════╣"
echo "║                                                                              ║"
echo "║  Note: When you create an Azure SRE Agent, you'll need to:                   ║"
echo "║                                                                              ║"
echo "║  1. Get the SRE Agent's managed identity Object ID from Azure Portal         ║"
echo "║  2. Run this script again with --sre-agent-principal-id:                      ║"
echo "║                                                                              ║"
echo "║     ./scripts/configure-rbac.sh -g \"${RESOURCE_GROUP}\" \\"
echo "║         --sre-agent-principal-id \"<object-id>\"                               ║"
echo "║                                                                              ║"
echo "║  SRE Agent RBAC Roles (assigned via Azure Portal):                           ║"
echo "║  • SRE Agent Admin - Full access to create/manage agent                     ║"
echo "║  • SRE Agent Standard User - Chat and diagnose capabilities                 ║"
echo "║  • SRE Agent Reader - View-only access                                      ║"
echo "║                                                                              ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
