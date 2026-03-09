#!/usr/bin/env bash
# =============================================================================
# Validates that the Azure SRE Agent Demo Lab deployment is healthy.
#
# Usage:
#   ./scripts/validate-deployment.sh --resource-group "rg-srelab-eastus2"
#   ./scripts/validate-deployment.sh --resource-group "rg-srelab-eastus2" --detailed
#
# Parameters:
#   -g, --resource-group  Resource group name (required)
#   -d, --detailed        Show detailed output for each check
# =============================================================================

set -uo pipefail  # no -e: we want to continue on individual check failures

# Defaults
RESOURCE_GROUP=""
DETAILED=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

TOTAL_CHECKS=0
PASSED_CHECKS=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -d|--detailed)
            DETAILED=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 -g <resource-group> [-d|--detailed]"
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

# Helper: write check result
write_check() {
    local name="$1"
    local passed="$2"
    local message="${3:-}"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if [[ "$passed" == "true" ]]; then
        echo -e "  ${GREEN}✅ ${name}${NC}"
        if [[ -n "$message" && "$DETAILED" == "true" ]]; then
            echo -e "     ${GRAY}${message}${NC}"
        fi
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo -e "  ${RED}❌ ${name}${NC}"
        if [[ -n "$message" ]]; then
            echo -e "     ${YELLOW}${message}${NC}"
        fi
    fi
}

write_section() {
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Banner
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                   Azure SRE Agent Demo Lab - Validation                      ║"
echo "╠══════════════════════════════════════════════════════════════════════════════╣"
echo "║  Checking deployment health and readiness...                                 ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# =============================================================================
# AZURE RESOURCE CHECKS
# =============================================================================
write_section "Azure Resources"

# Check resource group exists
rg_json=$(az group show --name "$RESOURCE_GROUP" --output json 2>/dev/null) || true
if [[ -n "$rg_json" ]]; then
    rg_location=$(echo "$rg_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['location'])" 2>/dev/null || echo "unknown")
    write_check "Resource Group exists" "true" "Location: ${rg_location}"
else
    write_check "Resource Group exists" "false" "Not found: ${RESOURCE_GROUP}"
fi

# Get all resources in RG
resources_json=$(az resource list --resource-group "$RESOURCE_GROUP" --output json 2>/dev/null || echo "[]")

# Check AKS
aks_name=$(echo "$resources_json" | python3 -c "import sys,json; d=[r for r in json.load(sys.stdin) if r['type']=='Microsoft.ContainerService/managedClusters']; print(d[0]['name'] if d else '')" 2>/dev/null || echo "")
if [[ -n "$aks_name" ]]; then
    write_check "AKS Cluster exists" "true" "$aks_name"

    aks_details=$(az aks show --resource-group "$RESOURCE_GROUP" --name "$aks_name" --output json 2>/dev/null || echo "{}")
    prov_state=$(echo "$aks_details" | python3 -c "import sys,json; print(json.load(sys.stdin).get('provisioningState',''))" 2>/dev/null || echo "")
    power_state=$(echo "$aks_details" | python3 -c "import sys,json; print(json.load(sys.stdin).get('powerState',{}).get('code',''))" 2>/dev/null || echo "")
    is_running=$([[ "$prov_state" == "Succeeded" && "$power_state" == "Running" ]] && echo "true" || echo "false")
    write_check "AKS Cluster is running" "$is_running" "State: ${power_state}"

    is_private=$(echo "$aks_details" | python3 -c "import sys,json; print(json.load(sys.stdin).get('apiServerAccessProfile',{}).get('enablePrivateCluster',False))" 2>/dev/null || echo "False")
    is_public=$([[ "$is_private" == "False" || "$is_private" == "false" ]] && echo "true" || echo "false")
    write_check "AKS API is public (required for SRE Agent)" "$is_public"
else
    write_check "AKS Cluster exists" "false"
fi

# Check Container Registry
acr_exists=$(echo "$resources_json" | python3 -c "import sys,json; d=[r for r in json.load(sys.stdin) if r['type']=='Microsoft.ContainerRegistry/registries']; print(d[0]['name'] if d else '')" 2>/dev/null || echo "")
write_check "Container Registry exists" "$([[ -n "$acr_exists" ]] && echo true || echo false)" "$acr_exists"

# Check Log Analytics
la_exists=$(echo "$resources_json" | python3 -c "import sys,json; d=[r for r in json.load(sys.stdin) if r['type']=='Microsoft.OperationalInsights/workspaces']; print(d[0]['name'] if d else '')" 2>/dev/null || echo "")
write_check "Log Analytics Workspace exists" "$([[ -n "$la_exists" ]] && echo true || echo false)" "$la_exists"

# Check App Insights
ai_exists=$(echo "$resources_json" | python3 -c "import sys,json; d=[r for r in json.load(sys.stdin) if r['type']=='Microsoft.Insights/components']; print(d[0]['name'] if d else '')" 2>/dev/null || echo "")
write_check "Application Insights exists" "$([[ -n "$ai_exists" ]] && echo true || echo false)" "$ai_exists"

# Check Key Vault
kv_exists=$(echo "$resources_json" | python3 -c "import sys,json; d=[r for r in json.load(sys.stdin) if r['type']=='Microsoft.KeyVault/vaults']; print(d[0]['name'] if d else '')" 2>/dev/null || echo "")
write_check "Key Vault exists" "$([[ -n "$kv_exists" ]] && echo true || echo false)" "$kv_exists"

# Check Grafana (optional)
grafana_exists=$(echo "$resources_json" | python3 -c "import sys,json; d=[r for r in json.load(sys.stdin) if r['type']=='Microsoft.Dashboard/grafana']; print(d[0]['name'] if d else '')" 2>/dev/null || echo "")
if [[ -n "$grafana_exists" ]]; then
    write_check "Managed Grafana exists" "true" "$grafana_exists"
fi

# =============================================================================
# KUBERNETES CONNECTIVITY
# =============================================================================
write_section "Kubernetes Connectivity"

if [[ -n "$aks_name" ]]; then
    echo -e "  ${GRAY}Connecting to AKS cluster...${NC}"
    az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$aks_name" --overwrite-existing 2>/dev/null || true
fi

# Test kubectl connectivity
if kubectl cluster-info &>/dev/null; then
    write_check "kubectl can connect to cluster" "true"
else
    write_check "kubectl can connect to cluster" "false"
fi

# Check node status
nodes_json=$(kubectl get nodes -o json 2>/dev/null || echo '{"items":[]}')
total_nodes=$(echo "$nodes_json" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['items']))" 2>/dev/null || echo "0")
healthy_nodes=$(echo "$nodes_json" | python3 -c "
import sys,json
items = json.load(sys.stdin)['items']
count = sum(1 for n in items if any(c['type']=='Ready' and c['status']=='True' for c in n['status']['conditions']))
print(count)
" 2>/dev/null || echo "0")

write_check "All nodes are Ready" "$([[ "$healthy_nodes" == "$total_nodes" && "$total_nodes" != "0" ]] && echo true || echo false)" "${healthy_nodes}/${total_nodes} nodes ready"

# =============================================================================
# APPLICATION HEALTH
# =============================================================================
write_section "Demo Application (pets namespace)"

# Check if namespace exists
if kubectl get namespace pets -o json &>/dev/null; then
    write_check "Namespace 'pets' exists" "true"
else
    write_check "Namespace 'pets' exists" "false"
    echo -e "  ${YELLOW}⚠️  Run: kubectl apply -f k8s/base/application.yaml${NC}"
fi

# Check pods
pods_json=$(kubectl get pods -n pets -o json 2>/dev/null || echo '{"items":[]}')
pod_count=$(echo "$pods_json" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['items']))" 2>/dev/null || echo "0")

if [[ "$pod_count" -gt 0 ]]; then
    echo -e "\n  ${WHITE}Pod Status:${NC}"

    # Process each pod
    echo "$pods_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for pod in data['items']:
    name = pod['metadata']['name']
    phase = pod['status']['phase']
    containers = pod['status'].get('containerStatuses', [])
    ready = sum(1 for c in containers if c.get('ready'))
    total = len(containers)
    healthy = phase == 'Running' and ready == total
    icon = '✅' if healthy else '❌'
    print(f'{icon}|{name}|{phase}|{ready}/{total}|{healthy}')
" 2>/dev/null | while IFS='|' read -r icon name phase readiness is_healthy; do
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        if [[ "$is_healthy" == "True" ]]; then
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            if [[ "$DETAILED" == "true" ]]; then
                echo -e "    ${GREEN}${icon} ${name} - ${phase} (${readiness} ready)${NC}"
            fi
        else
            echo -e "    ${RED}${icon} ${name} - ${phase} (${readiness} ready)${NC}"
        fi
    done

    running_pods=$(echo "$pods_json" | python3 -c "import sys,json; print(sum(1 for p in json.load(sys.stdin)['items'] if p['status']['phase']=='Running'))" 2>/dev/null || echo "0")
    color=$([[ "$running_pods" == "$pod_count" ]] && echo "$GREEN" || echo "$YELLOW")
    echo -e "\n  ${color}Summary: ${running_pods}/${pod_count} pods running${NC}"
else
    echo -e "  ${YELLOW}⚠️  No pods found in 'pets' namespace${NC}"
    echo -e "     ${GRAY}Run: kubectl apply -f k8s/base/application.yaml${NC}"
fi

# Check services
echo -e "\n  ${WHITE}Services:${NC}"
services_json=$(kubectl get svc -n pets -o json 2>/dev/null || echo '{"items":[]}')

echo "$services_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for svc in data['items']:
    name = svc['metadata']['name']
    svc_type = svc['spec']['type']
    if svc_type == 'LoadBalancer':
        ingress = svc.get('status',{}).get('loadBalancer',{}).get('ingress',[])
        endpoint = ingress[0]['ip'] if ingress else 'Pending'
        has_endpoint = bool(ingress)
    elif svc_type == 'ClusterIP':
        endpoint = svc['spec']['clusterIP']
        has_endpoint = True
    else:
        endpoint = svc_type
        has_endpoint = True
    print(f'{has_endpoint}|{name} ({svc_type})|{endpoint}')
" 2>/dev/null | while IFS='|' read -r has_endpoint name endpoint; do
    write_check "$name" "$([[ "$has_endpoint" == "True" ]] && echo true || echo false)" "$endpoint"
done

# Check for store-front LoadBalancer
store_ip=$(kubectl get svc store-front -n pets -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [[ -n "$store_ip" ]]; then
    echo -e "\n  ${CYAN}🌐 Store Front URL: http://${store_ip}${NC}"
fi

# =============================================================================
# OBSERVABILITY
# =============================================================================
write_section "Observability"

ci_pods=$(kubectl get daemonset -n kube-system -l component=oms-agent -o json 2>/dev/null || echo '{"items":[]}')
ci_count=$(echo "$ci_pods" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['items']))" 2>/dev/null || echo "0")

if [[ "$ci_count" -gt 0 ]]; then
    desired=$(echo "$ci_pods" | python3 -c "import sys,json; print(json.load(sys.stdin)['items'][0]['status']['desiredNumberScheduled'])" 2>/dev/null || echo "0")
    ready=$(echo "$ci_pods" | python3 -c "import sys,json; print(json.load(sys.stdin)['items'][0]['status']['numberReady'])" 2>/dev/null || echo "0")
    write_check "Container Insights agent running" "$([[ "$ready" == "$desired" ]] && echo true || echo false)" "${ready}/${desired} pods"
else
    ama_pods=$(kubectl get pods -n kube-system -l app=ama-logs -o json 2>/dev/null || echo '{"items":[]}')
    ama_count=$(echo "$ama_pods" | python3 -c "import sys,json; print(sum(1 for p in json.load(sys.stdin)['items'] if p['status']['phase']=='Running'))" 2>/dev/null || echo "0")

    if [[ "$ama_count" -gt 0 ]]; then
        write_check "Azure Monitor Agent running" "true" "${ama_count} pods"
    else
        echo -e "  ${GRAY}ℹ️  No Container Insights agent detected${NC}"
    fi
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
if [[ "$PASSED_CHECKS" -eq "$TOTAL_CHECKS" && "$TOTAL_CHECKS" -gt 0 ]]; then
    color="$GREEN"
else
    color="$YELLOW"
fi

echo -e "${color}══════════════════════════════════════════════════════════════${NC}"
echo -e "  ${color}VALIDATION SUMMARY: ${PASSED_CHECKS}/${TOTAL_CHECKS} checks passed${NC}"
echo -e "${color}══════════════════════════════════════════════════════════════${NC}"

if [[ "$PASSED_CHECKS" -eq "$TOTAL_CHECKS" && "$TOTAL_CHECKS" -gt 0 ]]; then
    echo -e "${GREEN}"
    echo "✅ All checks passed! Your deployment is healthy."
    echo ""
    echo "Next steps:"
    echo "1. Create SRE Agent: https://portal.azure.com/#create/Microsoft.SREAgent"
    echo "2. Break something: kubectl apply -f k8s/scenarios/oom-killed.yaml"
    echo "3. Ask SRE Agent to diagnose!"
    echo -e "${NC}"
else
    failed=$((TOTAL_CHECKS - PASSED_CHECKS))
    echo -e "${YELLOW}"
    echo "⚠️  ${failed} check(s) failed. Review the issues above."
    echo ""
    echo "Common fixes:"
    echo "- Deploy application: kubectl apply -f k8s/base/application.yaml"
    echo "- Wait for pods: kubectl get pods -n pets -w"
    echo "- Check events: kubectl get events -n pets --sort-by='.lastTimestamp'"
    echo -e "${NC}"
fi

if [[ "$PASSED_CHECKS" -ne "$TOTAL_CHECKS" ]]; then
    exit 1
fi
