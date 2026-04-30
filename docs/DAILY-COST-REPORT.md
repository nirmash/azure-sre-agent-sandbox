# Daily Azure Cost Report — Scheduled Task Runbook

A ready-to-use prompt and configuration for setting up a recurring daily cost report using Azure SRE Agent's scheduled task feature.

---

## Overview

This scheduled task queries Azure Cost Management daily, generates a 7-day cost breakdown by resource group and service, produces trend charts, and flags anomalies (spikes or unexpected changes).

> **Important:** The task uses Python with Azure Managed Identity to call the Cost Management REST API directly. Do **not** use `az rest` or `az cli` commands — they are not available in the SRE Agent scheduled task environment.

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
Set up a daily scheduled task at 8:00 AM UTC called "Daily Cost Report (7-Day)" that does the following:

1. Use Python (ExecutePythonCode) with Azure Managed Identity (client_id: 080f7f24-909a-4b05-a1df-8f2d71aa257f) to query the Azure Cost Management REST API for the last 7 days of actual costs, grouped by ResourceGroup and ServiceName (daily granularity), filtered to these resource groups:
   - rg-srelab-eastus2
   - mc_rg-srelab-eastus2_aks-srelab_eastus2
   - rg-sre-demo-w4k9
   - sre-agent-demo-2

2. Also query the same 7-day window grouped by ResourceGroup only (for trend charts).

3. Generate a summary report that includes:
   - A table of the latest day's costs by resource group and service (with subtotals)
   - A stacked area chart for the 7-day daily trend by resource group
   - A cumulative cost chart
   - Comparison of the latest day's total vs. the 7-day average
   - Flag any day where cost exceeded 120% of the 7-day average as an anomaly
   - Key metrics: daily cost, period average, projected monthly, % change vs previous day

4. Use subscription ID: 93cba93f-571e-44e9-ac0a-a2987b58848c

5. Use the Cost Management REST API via Python requests:
   POST https://management.azure.com/subscriptions/{subscriptionId}/providers/Microsoft.CostManagement/query?api-version=2023-11-01
```

### Option 2: Using the Subagent Builder (Portal)

1. Navigate to your SRE Agent resource in the Azure Portal
2. Go to **Subagent builder** > **Create scheduled task**
3. Configure:

| Setting | Value |
|---|---|
| **Task Name** | Daily Cost Report (7-Day) |
| **Cron Expression** | `0 8 * * *` |
| **Description** | Daily 7-day cost breakdown and anomaly detection for managed resource groups |

4. Use the agent prompt from the [Agent Prompt](#agent-prompt) section below.

---

## Agent Prompt

Copy this prompt into the scheduled task's **Agent Prompt** field:

````
You are running a daily cost report for Azure resources. Follow these steps precisely:

## Step 1: Query Last 7 Days of Costs Using Python

Use ExecutePythonCode with Azure Managed Identity to query the Cost Management REST API directly. Do NOT use `az rest` or `az cli` commands — they are not supported in this environment.

```python
from azure.identity import ManagedIdentityCredential
import requests, json
from datetime import datetime, timedelta

credential = ManagedIdentityCredential(client_id="080f7f24-909a-4b05-a1df-8f2d71aa257f")
token = credential.get_token("https://management.azure.com/.default")
headers = {"Authorization": f"Bearer {token.token}", "Content-Type": "application/json"}

subscription_id = "93cba93f-571e-44e9-ac0a-a2987b58848c"
url = f"https://management.azure.com/subscriptions/{subscription_id}/providers/Microsoft.CostManagement/query?api-version=2023-11-01"
```

### Query A: 7-Day Detail (by ResourceGroup + ServiceName, Daily granularity)

POST to the Cost Management API with:
- timeframe: Custom, last 7 days (today minus 7 days through today)
- granularity: Daily
- aggregation: Sum of Cost
- grouping: ResourceGroup AND ServiceName
- filter: ResourceGroup In ["rg-srelab-eastus2", "mc_rg-srelab-eastus2_aks-srelab_eastus2", "rg-sre-demo-w4k9", "sre-agent-demo-2"]

Save the response JSON to `/mnt/data/7day_detail.json`.

### Query B: 7-Day Trend (by ResourceGroup only, Daily granularity)

Same as Query A but grouping by ResourceGroup only (no ServiceName). Save to `/mnt/data/7day_trend.json`.

If you get a 429 rate limit, wait 10 seconds and retry once.

## Step 2: Generate Report Using Python

Using ExecutePythonCode, load both JSON files and produce:

1. **Identify the latest available day** — Cost data has a 24-48h billing lag, so the most recent day with data may not be yesterday. Use the latest date in the results as the "report day".

2. **Cost Summary Table** — The report day's costs by resource group and service, with subtotals per resource group and a grand total. Use short names for resource groups:
   - rg-srelab-eastus2 → rg-srelab
   - mc_rg-srelab-eastus2_aks-srelab_eastus2 → mc_aks-srelab
   - rg-sre-demo-w4k9 → rg-sre-demo
   - sre-agent-demo-2 → sre-agent-demo

3. **Stacked Area Chart** — 7-day daily cost trend by resource group. Include a horizontal dashed red line for the period average and a dotted line at 120% threshold. Save as `/mnt/data/daily_cost_report.png`.

4. **Cumulative Cost Chart** — Running total over the 7-day window with annotated data points. Include on the same figure as a second subplot.

5. **Anomaly Detection** — Flag any day where total cost exceeded 120% of the period average.

6. **Key Metrics**:
   - Report day's total cost
   - Period average daily cost
   - Period total cost
   - Projected 30-day cost (period avg × 30)
   - % change vs. previous day

## Step 3: Present Results

Format the output as:

### Daily Azure Cost Report — {date}

> Note if the report day is not yesterday due to billing lag.

**Quick Stats:**
| Metric | Value |
|---|---|
| Report Day Cost | $X.XX |
| 7-Day Avg | $X.XX/day |
| Period Total | $X.XX |
| Projected Monthly | $X.XX |
| vs. Previous Day | +/- X.X% |

Then show the chart image, the detailed cost table, any anomaly alerts, and key observations about top cost drivers and trends.
````

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
| `az rest` or `az cli` commands fail | **Do not use `az rest` or `az cli`** in scheduled tasks — they are not available in the SRE Agent execution environment. Use Python with `ManagedIdentityCredential` and `requests` to call Azure REST APIs directly. |
| Cost Management API returns 429 | The API is rate-limited. Add a 10-second sleep and retry once. If persistent, increase the schedule interval. |
| Latest day shows $0 or lower cost | Cost data has a 24-48 hour billing lag. The report automatically uses the latest day with complete data. |
| Costs show $0 for a resource group | The resource group may be empty or resources were deallocated. Verify via the Azure Portal or `SearchResource` tool. |
| Chart not rendering | Ensure the scheduled task has access to Python code execution (ExecutePythonCode). matplotlib and pandas are pre-installed. |
| Authentication errors (401/403) | Verify the managed identity client ID (`080f7f24-909a-4b05-a1df-8f2d71aa257f`) has **Cost Management Reader** role on the subscription. |

---

## Related Documentation

- [SRE Agent Prompts Guide](PROMPTS-GUIDE.md) — General prompt library
- [SRE Agent Setup](SRE-AGENT-SETUP.md) — RBAC and permissions configuration
- [Azure Cost Management REST API](https://learn.microsoft.com/en-us/rest/api/cost-management/query/usage)
