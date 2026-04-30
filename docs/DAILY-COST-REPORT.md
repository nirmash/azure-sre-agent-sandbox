# Daily Azure Cost Report — Scheduled Task Runbook

A ready-to-use prompt and configuration for setting up a recurring daily cost report using Azure SRE Agent's scheduled task feature.

---

## Overview

This scheduled task queries Azure Cost Management daily, generates a cost breakdown by resource group and service, produces a trend chart, and flags anomalies (spikes or unexpected changes).

### What It Covers

| Resource Group | Contents |
|---|---|
| `rg-srelab-eastus2` | AKS cluster, Grafana, ACR, Key Vault, App Insights, Log Analytics, Azure Monitor |
| `MC_rg-srelab-eastus2_aks-srelab_eastus2` | AKS managed infrastructure (VMs, Load Balancer, VNet, Storage) |
| `rg-sre-demo-w4k9` | Web App demo (App Service B1, App Insights, Log Analytics) |
| `sre-agent-demo-2` | SRE Agent (Foundry Tools, Log Analytics) |

---

## Scheduled Task Setup

### Option 1: Using SRE Agent Chat

Paste this prompt directly in a conversation with SRE Agent:

```
Set up a daily scheduled task at 8:00 AM UTC called "Daily Cost Report" that does the following:

1. Query Azure Cost Management for the last 24 hours of actual costs, grouped by ResourceGroup and ServiceName, filtered to these resource groups:
   - rg-srelab-eastus2
   - mc_rg-srelab-eastus2_aks-srelab_eastus2
   - rg-sre-demo-w4k9
   - sre-agent-demo-2

2. Also query the last 7 days of daily costs (granularity: Daily) for the same resource groups to show trends.

3. Generate a summary report that includes:
   - A table of yesterday's costs by resource group and service
   - A daily trend chart for the past 7 days (stacked area by resource group)
   - A cumulative cost chart
   - Comparison of yesterday's total vs. the 7-day average
   - Flag any day where cost exceeded 120% of the 7-day average as an anomaly

4. Use subscription ID: 93cba93f-571e-44e9-ac0a-a2987b58848c

5. Use the Cost Management REST API via:
   POST https://management.azure.com/subscriptions/{subscriptionId}/providers/Microsoft.CostManagement/query?api-version=2023-11-01
```

### Option 2: Using the Subagent Builder (Portal)

1. Navigate to your SRE Agent resource in the Azure Portal
2. Go to **Subagent builder** > **Create scheduled task**
3. Configure:

| Setting | Value |
|---|---|
| **Task Name** | Daily Cost Report |
| **Cron Expression** | `0 8 * * *` |
| **Description** | Daily cost breakdown and anomaly detection for managed resource groups |

4. Use the agent prompt from the [Agent Prompt](#agent-prompt) section below.

---

## Agent Prompt

Copy this prompt into the scheduled task's **Agent Prompt** field:

```
You are running a daily cost report for Azure resources. Follow these steps precisely:

## Step 1: Query Yesterday's Costs

Use `az rest --method post` against the Cost Management API:
- URL: https://management.azure.com/subscriptions/93cba93f-571e-44e9-ac0a-a2987b58848c/providers/Microsoft.CostManagement/query?api-version=2023-11-01
- Body:
  {
    "type": "ActualCost",
    "timeframe": "Custom",
    "timePeriod": {
      "from": "<yesterday_start_UTC>",
      "to": "<today_start_UTC>"
    },
    "dataset": {
      "granularity": "None",
      "aggregation": { "totalCost": { "name": "Cost", "function": "Sum" } },
      "grouping": [
        { "type": "Dimension", "name": "ResourceGroup" },
        { "type": "Dimension", "name": "ServiceName" }
      ],
      "filter": {
        "dimensions": {
          "name": "ResourceGroup",
          "operator": "In",
          "values": [
            "rg-srelab-eastus2",
            "mc_rg-srelab-eastus2_aks-srelab_eastus2",
            "rg-sre-demo-w4k9",
            "sre-agent-demo-2"
          ]
        }
      }
    }
  }

## Step 2: Query 7-Day Trend

Same API, but with:
- timePeriod: last 7 days
- granularity: "Daily"
- grouping: ResourceGroup only (remove ServiceName)
- Same filter as above

## Step 3: Generate Report

Using Python (ExecutePythonCode), create:

1. **Cost Summary Table** — Yesterday's costs by resource group and service, with subtotals
2. **Stacked Area Chart** — 7-day daily trend by resource group (save as PNG)
3. **Cumulative Cost Chart** — Running total over the 7-day window
4. **Anomaly Detection** — Flag any day where total cost > 120% of the 7-day average
5. **Key Metrics**:
   - Yesterday's total cost
   - 7-day average daily cost
   - 7-day total cost
   - Projected 30-day cost (7-day avg × 30)
   - % change vs. previous day

## Step 4: Present Results

Format the output as:

### Daily Azure Cost Report — {date}

**Quick Stats:**
| Metric | Value |
|---|---|
| Yesterday's Cost | $X.XX |
| 7-Day Avg | $X.XX/day |
| Projected Monthly | $X.XX |
| vs. Previous Day | +/- X.X% |

Then show the chart, the detailed table, and any anomaly alerts.

If any anomaly is detected (>120% of average), prominently flag it with details on which resource group and service caused the spike.
```

---

## Cron Schedule Options

| Schedule | Cron Expression | Use Case |
|---|---|---|
| Daily at 8 AM UTC | `0 8 * * *` | Standard daily report |
| Weekdays only at 9 AM UTC | `0 9 * * 1-5` | Business-hours reporting |
| Every 6 hours | `0 */6 * * *` | High-frequency cost monitoring |
| Weekly on Monday at 8 AM UTC | `0 8 * * 1` | Weekly cost summary |

---

## Customization

### Adjusting the Anomaly Threshold

Change the `120%` threshold in the agent prompt to suit your needs:
- **110%** — More sensitive, catches smaller spikes
- **150%** — Less noisy, only flags major spikes

### Adding Resource Groups

To monitor additional resource groups, add them to the `values` array in the filter:

```json
"values": [
  "rg-srelab-eastus2",
  "mc_rg-srelab-eastus2_aks-srelab_eastus2",
  "rg-sre-demo-w4k9",
  "sre-agent-demo-2",
  "your-new-resource-group"
]
```

### Adding Budget Alerts

Extend the agent prompt with a budget check:

```
## Step 5: Budget Check

Compare the projected monthly cost against these budgets:
- rg-srelab-eastus2 (including MC_ group): $100/month
- sre-agent-demo-2: $60/month
- rg-sre-demo-w4k9: $5/month

If any resource group is projected to exceed its budget, flag it as a BUDGET WARNING with the projected overage amount and percentage.
```

---

## Expected Output

A typical daily report looks like:

```
### Daily Azure Cost Report — Apr 30, 2026

Quick Stats:
| Metric             | Value        |
|--------------------|--------------|
| Yesterday's Cost   | $4.72        |
| 7-Day Avg          | $4.58/day    |
| Projected Monthly  | $137.40      |
| vs. Previous Day   | +2.8%        |

[Stacked area chart showing 7-day trend]
[Cumulative cost chart]

Breakdown:
| Resource Group          | Service                  | Cost     |
|-------------------------|--------------------------|----------|
| rg-srelab-eastus2       | Azure Kubernetes Service | $1.40    |
| rg-srelab-eastus2       | Azure Grafana Service    | $0.93    |
| ...                     | ...                      | ...      |

No anomalies detected.
```

---

## Troubleshooting

| Issue | Solution |
|---|---|
| Cost Management API returns 429 | The API is rate-limited. The agent will retry automatically. If persistent, increase the schedule interval. |
| Costs show $0 for a resource group | The resource group may be empty or resources were deallocated. Check resource inventory with `az resource list`. |
| Partial day data | Data for the current day is incomplete until the billing pipeline finalizes (~24-48 hours). Use the previous day's data for accuracy. |
| Chart not rendering | Ensure the scheduled task has access to Python code execution. |

---

## Related Documentation

- [SRE Agent Prompts Guide](PROMPTS-GUIDE.md) — General prompt library
- [SRE Agent Setup](SRE-AGENT-SETUP.md) — RBAC and permissions configuration
- [Azure Cost Management REST API](https://learn.microsoft.com/en-us/rest/api/cost-management/query/usage)
