# Azure SRE Agent Demo — Breakable Scenario Quick Reference

## Prerequisites

```bash
go to the project directory
cd ~/Projects/azure-sre-agent-sandbox

# 1. Login to Azure
az login --use-device-code

# 2. Get AKS credentials
az aks get-credentials -g rg-srelab-eastus2 -n aks-srelab

# 3. Verify access
kubectl get pods -n pets

#4 Start breaking things!
in github copilot cli call .agents/skills/sre-load-test/SKILL.md to run tests against the webapp and show how SRE Agent picked up the events and what it did

#5 
run one of the break commands below, then show how SRE Agent picked up the events and what it did

```

## Break Scenarios

Apply one at a time for clean demos.

| #  | Scenario                                                        | Command                                                    |
| -- | --------------------------------------------------------------- | ---------------------------------------------------------- |
| 1  | **OOM Killed** — memory exhaustion                       | `kubectl apply -f k8s/scenarios/oom-killed.yaml`         |
| 2  | **Crash Loop** — startup failure                         | `kubectl apply -f k8s/scenarios/crash-loop.yaml`         |
| 3  | **Image Pull Error** — bad image tag                     | `kubectl apply -f k8s/scenarios/image-pull-backoff.yaml` |
| 4  | **High CPU** — resource contention                       | `kubectl apply -f k8s/scenarios/high-cpu.yaml`           |
| 5  | **Pending Pods** — unschedulable                         | `kubectl apply -f k8s/scenarios/pending-pods.yaml`       |
| 6  | **Probe Failure** — health check fails                   | `kubectl apply -f k8s/scenarios/probe-failure.yaml`      |
| 7  | **Network Block** — connectivity blocked                 | `kubectl apply -f k8s/scenarios/network-block.yaml`      |
| 8  | **Missing Config** — ConfigMap not found                 | `kubectl apply -f k8s/scenarios/missing-config.yaml`     |
| 9  | **MongoDB Down** — cascading dependency failure          | `kubectl apply -f k8s/scenarios/mongodb-down.yaml`       |
| 10 | **Service Mismatch** — selector mismatch, silent failure | `kubectl apply -f k8s/scenarios/service-mismatch.yaml`   |

## Observe the Break

```bash
kubectl get pods -n pets              # check pod statuses
kubectl describe pod <NAME> -n pets   # see events & errors
kubectl logs <NAME> -n pets           # check container logs
```

## Fix Commands

**Scenarios 1–3, 9, 10** (overwrite-style fix):

```bash
kubectl apply -f k8s/base/application.yaml
```

**Individual fixes for scenarios 4–8:**

```bash
# 4 — High CPU
kubectl delete deployment cpu-stress-test -n pets

# 5 — Pending Pods
kubectl delete deployment resource-hog -n pets

# 6 — Probe Failure
kubectl delete deployment unhealthy-service -n pets

# 7 — Network Block
kubectl delete networkpolicy deny-order-service -n pets

# 8 — Missing Config
kubectl delete deployment misconfigured-service -n pets
```

**Fix everything at once:**

```bash
kubectl apply -f k8s/base/application.yaml && \
kubectl delete deployment cpu-stress-test resource-hog unhealthy-service misconfigured-service -n pets --ignore-not-found && \
kubectl delete networkpolicy deny-order-service -n pets --ignore-not-found
```

## Webapp Tests

Show the webapp https://app-sre-demo-s3bmyd.azurewebsites.net/ looks
Webapp section: use  .agents/skills/sre-load-test/SKILL.md. to run tests against the webapp
Show how SRE Agent picked up the events and what it did 

**Reset the webapp by redeploying the base application:**
 From ~/Projects/sre-demo-webapp
```bash
cd src/web && az webapp up \
     --name app-sre-demo-s3bmyd \
     --resource-group rg-sre-demo-w4k9 \
     --location westus2
```
