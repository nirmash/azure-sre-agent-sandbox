#!/usr/bin/env bash
# =============================================================================
# Deploys the Azure SRE Agent Demo Lab infrastructure using Bicep.
#
# This script deploys all Azure infrastructure needed for the SRE Agent demo,
# including AKS, Container Registry, Key Vault, and observability tools.
# It uses device code authentication by default for dev container support.
#
# Usage:
#   ./scripts/deploy.sh                             # Deploy with defaults
#   ./scripts/deploy.sh -l swedencentral            # Specify region
#   ./scripts/deploy.sh -l eastus2 -y               # Skip confirmation
#   ./scripts/deploy.sh --what-if                   # Preview only
#
# Parameters:
#   -l, --location       Azure region (eastus2, swedencentral, australiaeast). Default: eastus2
#   -w, --workload-name  Resource prefix (3-10 chars). Default: srelab
#   --skip-rbac          Skip RBAC role assignments
#   --what-if            Preview deployment without making changes
#   -y, --yes            Skip confirmation prompts
# =============================================================================

set -euo pipefail

# Defaults
LOCATION="eastus2"
WORKLOAD_NAME="srelab"
SKIP_RBAC=false
WHAT_IF=false
YES=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

VALID_LOCATIONS=("eastus2" "swedencentral" "australiaeast")

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -w|--workload-name)
            WORKLOAD_NAME="$2"
            shift 2
            ;;
        --skip-rbac)
            SKIP_RBAC=true
            shift
            ;;
        --what-if)
            WHAT_IF=true
            shift
            ;;
        -y|--yes)
            YES=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-l location] [-w workload-name] [--skip-rbac] [--what-if] [-y]"
            echo ""
            echo "Options:"
            echo "  -l, --location       Azure region (eastus2, swedencentral, australiaeast). Default: eastus2"
            echo "  -w, --workload-name  Resource prefix (3-10 chars). Default: srelab"
            echo "  --skip-rbac          Skip RBAC role assignments"
            echo "  --what-if            Preview deployment without making changes"
            echo "  -y, --yes            Skip confirmation prompts"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Validate location
if [[ ! " ${VALID_LOCATIONS[*]} " =~ " ${LOCATION} " ]]; then
    echo -e "${RED}Invalid location: ${LOCATION}. Must be one of: ${VALID_LOCATIONS[*]}${NC}"
    exit 1
fi

# Validate workload name length
if [[ ${#WORKLOAD_NAME} -lt 3 || ${#WORKLOAD_NAME} -gt 10 ]]; then
    echo -e "${RED}Workload name must be 3-10 characters. Got: ${WORKLOAD_NAME}${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Banner
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                    Azure SRE Agent Demo Lab Deployment                       ║"
echo "╠══════════════════════════════════════════════════════════════════════════════╣"
echo "║  This script deploys:                                                        ║"
echo "║  • Azure Kubernetes Service (AKS) with multi-service demo app               ║"
echo "║  • Azure Container Registry                                                  ║"
echo "║  • Observability stack (Log Analytics, App Insights, Grafana)               ║"
echo "║  • Key Vault for secrets management                                         ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Verify prerequisites
echo -e "${YELLOW}🔍 Checking prerequisites...${NC}"

# Check Azure CLI
if az_version=$(az version --output json 2>/dev/null); then
    cli_ver=$(echo "$az_version" | python3 -c "import sys,json; print(json.load(sys.stdin)['azure-cli'])" 2>/dev/null || echo "unknown")
    echo -e "  ${GREEN}✅ Azure CLI version: ${cli_ver}${NC}"
else
    echo -e "${RED}Azure CLI is not installed. Please install it from https://aka.ms/installazurecli${NC}"
    exit 1
fi

# Check Bicep
if bicep_version=$(az bicep version 2>&1); then
    echo -e "  ${GREEN}✅ Bicep: ${bicep_version}${NC}"
else
    echo -e "  ${YELLOW}⚠️  Bicep not found, installing...${NC}"
    az bicep install
fi

# Check login status
echo -e "\n${YELLOW}🔐 Checking Azure authentication...${NC}"
if account_json=$(az account show --output json 2>/dev/null); then
    user_name=$(echo "$account_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['name'])")
    sub_name=$(echo "$account_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
    sub_id=$(echo "$account_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
else
    echo -e "  ${YELLOW}Not logged in. Initiating device code authentication...${NC}"
    echo -e "  ${GRAY}This method works well in dev containers and codespaces.${NC}"
    az login --use-device-code
    account_json=$(az account show --output json)
    user_name=$(echo "$account_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['name'])")
    sub_name=$(echo "$account_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
    sub_id=$(echo "$account_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
fi

echo -e "  ${GREEN}✅ Logged in as: ${user_name}${NC}"
echo -e "  ${GREEN}📋 Subscription: ${sub_name} (${sub_id})${NC}"

# Confirm subscription
echo -e "\n${YELLOW}⚠️  Resources will be deployed to subscription: ${sub_name}${NC}"
if [[ "$YES" != "true" ]]; then
    read -rp "Continue? (y/N) " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${RED}Deployment cancelled.${NC}"
        exit 0
    fi
else
    echo -e "  ${GRAY}✅ Confirmation skipped (-y)${NC}"
fi

# Set variables
RESOURCE_GROUP="rg-${WORKLOAD_NAME}-${LOCATION}"
DEPLOYMENT_NAME="sre-demo-$(date +%Y%m%d-%H%M%S)"
BICEP_FILE="${SCRIPT_DIR}/../infra/bicep/main.bicep"
PARAMS_FILE="${SCRIPT_DIR}/../infra/bicep/main.bicepparam"

echo -e "\n${CYAN}📦 Deployment Configuration:${NC}"
echo -e "  ${WHITE}• Location:        ${LOCATION}${NC}"
echo -e "  ${WHITE}• Workload Name:   ${WORKLOAD_NAME}${NC}"
echo -e "  ${WHITE}• Resource Group:  ${RESOURCE_GROUP}${NC}"
echo -e "  ${WHITE}• Deployment Name: ${DEPLOYMENT_NAME}${NC}"

# Validate template
echo -e "\n${YELLOW}🔍 Validating Bicep template...${NC}"

if [[ "$WHAT_IF" == "true" ]]; then
    echo -e "  ${GRAY}Running what-if analysis...${NC}"
    az deployment sub what-if \
        --location "$LOCATION" \
        --template-file "$BICEP_FILE" \
        --parameters location="$LOCATION" workloadName="$WORKLOAD_NAME" \
        --name "$DEPLOYMENT_NAME"

    echo -e "\n${GREEN}✅ What-if analysis complete. No changes were made.${NC}"
    exit 0
fi

# Deploy
echo -e "\n${YELLOW}🚀 Starting deployment...${NC}"
echo -e "  ${GRAY}This will take approximately 15-25 minutes.${NC}"

START_TIME=$(date +%s)

deployment_output=$(az deployment sub create \
    --location "$LOCATION" \
    --template-file "$BICEP_FILE" \
    --parameters "$PARAMS_FILE" location="$LOCATION" workloadName="$WORKLOAD_NAME" \
    --name "$DEPLOYMENT_NAME" \
    --only-show-errors \
    --output json 2>&1) || {
    echo -e "\n${RED}Azure CLI deployment command failed.${NC}"
    echo -e "${RED}${deployment_output}${NC}"

    # Best-effort: pull structured error details
    show_output=$(az deployment sub show --name "$DEPLOYMENT_NAME" --output json 2>/dev/null) || true
    if [[ -n "$show_output" ]]; then
        state=$(echo "$show_output" | python3 -c "import sys,json; print(json.load(sys.stdin)['properties']['provisioningState'])" 2>/dev/null || echo "unknown")
        echo -e "\n${YELLOW}Deployment provisioningState: ${state}${NC}"
    fi
    exit 1
}

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

echo -e "\n${GREEN}✅ Deployment completed successfully!${NC}"
echo -e "   ${GRAY}Duration: ${MINUTES} minutes ${SECONDS} seconds${NC}"

# Parse outputs using python3 (available on macOS)
parse_output() {
    echo "$deployment_output" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['properties']['outputs']['$1']['value'])" 2>/dev/null || echo ""
}

RG_NAME=$(parse_output "resourceGroupName")
AKS_NAME=$(parse_output "aksClusterName")
AKS_FQDN=$(parse_output "aksClusterFqdn")
ACR_SERVER=$(parse_output "acrLoginServer")
KV_URI=$(parse_output "keyVaultUri")
LA_ID=$(parse_output "logAnalyticsWorkspaceId")
AI_ID=$(parse_output "appInsightsId")
GRAFANA_URL=$(parse_output "grafanaDashboardUrl")
AMW_ID=$(parse_output "azureMonitorWorkspaceId")
PROM_DCR=$(parse_output "prometheusDataCollectionRuleId")

echo -e "\n${CYAN}📋 Deployment Outputs:${NC}"
echo -e "  ${WHITE}• Resource Group:   ${RG_NAME}${NC}"
echo -e "  ${WHITE}• AKS Cluster:      ${AKS_NAME}${NC}"
echo -e "  ${WHITE}• AKS FQDN:         ${AKS_FQDN}${NC}"
echo -e "  ${WHITE}• ACR Login Server: ${ACR_SERVER}${NC}"
echo -e "  ${WHITE}• Key Vault URI:    ${KV_URI}${NC}"
echo -e "  ${WHITE}• Log Analytics ID: ${LA_ID}${NC}"
echo -e "  ${WHITE}• App Insights ID:  ${AI_ID}${NC}"

if [[ -n "$GRAFANA_URL" ]]; then
    echo -e "  ${WHITE}• Grafana:          ${GRAFANA_URL}${NC}"
    echo -e "  ${WHITE}• AMW ID:           ${AMW_ID}${NC}"
    echo -e "  ${WHITE}• Prometheus DCR:   ${PROM_DCR}${NC}"
fi

# Save outputs to file
OUTPUTS_FILE="${SCRIPT_DIR}/deployment-outputs.json"
echo "$deployment_output" | python3 -c "import sys,json; json.dump(json.load(sys.stdin)['properties']['outputs'], sys.stdout, indent=2)" > "$OUTPUTS_FILE" 2>/dev/null || true
echo -e "\n  ${GRAY}📄 Outputs saved to: ${OUTPUTS_FILE}${NC}"

# Get AKS credentials
echo -e "\n${YELLOW}🔑 Getting AKS credentials...${NC}"
az aks get-credentials \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_NAME" \
    --overwrite-existing

echo -e "  ${GREEN}✅ kubectl configured for cluster: ${AKS_NAME}${NC}"

# Apply RBAC if not skipped
if [[ "$SKIP_RBAC" != "true" ]]; then
    echo -e "\n${YELLOW}🔐 Applying RBAC assignments...${NC}"
    echo -e "  ${GRAY}⚠️  Note: If this fails due to subscription policies, run with --skip-rbac${NC}"

    RBAC_SCRIPT="${SCRIPT_DIR}/configure-rbac.sh"
    if [[ -f "$RBAC_SCRIPT" ]]; then
        bash "$RBAC_SCRIPT" --resource-group "$RESOURCE_GROUP"
    else
        echo -e "  ${YELLOW}⚠️  RBAC script not found, skipping...${NC}"
    fi
fi

# Deploy application
echo -e "\n${YELLOW}📦 Deploying demo application to AKS...${NC}"
K8S_PATH="${SCRIPT_DIR}/../k8s/base/application.yaml"

if [[ -f "$K8S_PATH" ]]; then
    kubectl apply -f "$K8S_PATH"
    echo -e "  ${GREEN}✅ Demo application deployed${NC}"

    # Wait for pods to start
    echo -e "\n${YELLOW}⏳ Waiting for pods to be ready (this may take 2-3 minutes)...${NC}"
    kubectl wait --for=condition=ready pod -l app=store-front -n pets --timeout=180s 2>/dev/null || true

    # Wait for LoadBalancer IP
    echo -e "${YELLOW}⏳ Waiting for store-front external IP...${NC}"
    MAX_WAIT=120
    WAITED=0
    STORE_URL=""
    while [[ $WAITED -lt $MAX_WAIT ]]; do
        EXTERNAL_IP=$(kubectl get svc store-front -n pets -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [[ -n "$EXTERNAL_IP" ]]; then
            STORE_URL="http://${EXTERNAL_IP}"
            break
        fi
        sleep 5
        WAITED=$((WAITED + 5))
    done

    if [[ -n "$STORE_URL" ]]; then
        echo -e "  ${GREEN}✅ Store Front URL: ${STORE_URL}${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠️  Application manifest not found at: ${K8S_PATH}${NC}"
fi

# Run validation
echo -e "\n${YELLOW}🔍 Running deployment validation...${NC}"
VALIDATE_SCRIPT="${SCRIPT_DIR}/validate-deployment.sh"

if [[ -f "$VALIDATE_SCRIPT" ]]; then
    bash "$VALIDATE_SCRIPT" --resource-group "$RESOURCE_GROUP"
else
    echo -e "  ${YELLOW}⚠️  Validation script not found, skipping...${NC}"
fi

# Final instructions
AKS_DISPLAY="${AKS_NAME:-<check Azure Portal>}"
SITE_DISPLAY="${STORE_URL:-kubectl get svc store-front -n pets}"

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                         Deployment Complete! 🎉                              ║"
echo "╠══════════════════════════════════════════════════════════════════════════════╣"
echo "║  Resources Deployed:                                                         ║"
printf "║    • AKS Cluster:    %-44s║\n" "$AKS_DISPLAY"
printf "║    • Store Front:    %-44s║\n" "$SITE_DISPLAY"
echo "║                                                                              ║"
echo "║  ⚠️  SRE Agent Setup Required (Portal Only):                                 ║"
echo "║    Azure SRE Agent does not support programmatic creation yet.               ║"
echo "║    1. Go to: https://aka.ms/sreagent/portal                                  ║"
echo "║    2. Click \"Create\" and select resource group: ${RESOURCE_GROUP}"
echo "║                                                                              ║"
echo "║  Quick Start (after SRE Agent setup):                                        ║"
echo "║    1. Open the store: ${SITE_DISPLAY}"
echo "║    2. Break something: break-oom                                             ║"
echo "║    3. Refresh store to see failure                                           ║"
echo '║    4. Ask SRE Agent: "Why are pods crashing in the pets namespace?"         ║'
echo "║    5. Fix it: fix-all                                                        ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
