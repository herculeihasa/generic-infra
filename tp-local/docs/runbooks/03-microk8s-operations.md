# 03 MicroK8s operations

| | |
|---|---|
| **Scope** | Day-to-day operation of the MicroK8s cluster inside WSL Ubuntu |
| **Status** | **Pending external prerequisites**: commands are standard MicroK8s/kubectl commands, not yet executed on this project's cluster |
| **Code** | `modules/microk8s/scripts/lib.sh`, `modules/microk8s/scripts/wait-ready.sh`, `modules/microk8s/scripts/addon.sh`, `scripts/verify-cluster.sh` |

**Conventions:** run in **WSL** as the cluster owner (member of the
`microk8s` group). `kubectl` means either the standalone client with
`KUBECONFIG=~/.kube/tp-local-microk8s.yaml` or `microk8s kubectl` (no
kubeconfig needed). Commands needing root are marked **(sudo)**.

> [!IMPORTANT]
> Add-ons and the snap channel are **managed by Terraform** (stage 1). Change
> them through `tp-local/bootstrap` (MK-08), not by hand: Terraform does not
> read MicroK8s' state and would not notice a manual change.

## MK-01 Check cluster readiness

**Status:** Pending external prerequisites (`wait-ready.sh` logic covered by the stubbed suite).

```bash
microk8s status --wait-ready --timeout 60      # "microk8s is running" + add-on list
microk8s status --format short                 # one line per add-on: core/<name>: enabled|disabled
kubectl get --raw=/readyz                      # "ok"
kubectl get nodes                              # STATUS Ready
```

Full readiness gate (same as the Terraform `ready` step: services, node,
every Deployment Available, every DaemonSet rolled out):

```bash
bash tp-local/modules/microk8s/scripts/wait-ready.sh
```

Expected: `cluster and add-ons are ready`. Complete post-deployment check:
`tp-local/scripts/verify-cluster.sh`.

## MK-02 Check MicroK8s services

**Status:** Pending external prerequisites.

```bash
snap services microk8s                                     # daemons and their state
systemctl status snap.microk8s.daemon-kubelite --no-pager  # API server, scheduler, controllers, kubelet
systemctl status snap.microk8s.daemon-containerd --no-pager
systemctl status snap.microk8s.daemon-k8s-dqlite --no-pager  # datastore
snap list microk8s                                         # version, revision, tracking channel
```

Expected: services `active`; `snap list` tracking `1.35/stable` (or the
configured `microk8s_channel`).

## MK-03 Inspect nodes

**Status:** Pending external prerequisites.

```bash
kubectl get nodes -o wide                       # name (WSL hostname), IP, OS image, runtime
kubectl describe node "$(hostname | tr '[:upper:]' '[:lower:]')"
kubectl top nodes                               # needs metrics-server
kubectl get nodes --show-labels | grep tp-local/role      # label set by stage 2
```

## MK-04 Inspect pods and events

**Status:** Pending external prerequisites.

```bash
kubectl get pods -A -o wide
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
kubectl describe pod "<pod>" -n "<namespace>"
kubectl get events -A --sort-by=.lastTimestamp | tail -30
```

## MK-05 View logs

**Status:** Pending external prerequisites.

```bash
kubectl logs "<pod>" -n "<namespace>" [--previous]           # container logs
journalctl -u snap.microk8s.daemon-kubelite --since "30 min ago" --no-pager
journalctl -u snap.microk8s.daemon-containerd --since "30 min ago" --no-pager
sudo microk8s inspect                                          # (sudo) full diagnostic bundle
```

`microk8s inspect` checks the services and writes a report archive (path
printed at the end) to attach to an escalation.

## MK-06 Stop and start the cluster

**Status:** Pending external prerequisites.

```bash
microk8s stop     # stops every MicroK8s service (frees CPU/RAM); may ask for sudo depending on the release
microk8s start
microk8s status --wait-ready --timeout 300
```

Stopping WSL stops the cluster too (PowerShell: `wsl --shutdown`); with
systemd, MicroK8s starts again with the distribution. Workloads restart on
their own; nothing is lost (data lives under `/var/snap/microk8s`).

## MK-07 Restart services

**Status:** Pending external prerequisites.

```bash
sudo snap restart microk8s                          # (sudo) all MicroK8s services
sudo snap restart microk8s.daemon-kubelite          # (sudo) control plane + kubelet only
microk8s status --wait-ready --timeout 300
```

## MK-08 Manage add-ons

**Status:** Implemented (Terraform path; plan behaviour validated offline); Pending external prerequisites.

**Preferred (Terraform):** edit the `addons` map of stage 1 and apply.

```hcl
# tp-local/bootstrap: in a tfvars file of your choice, or by changing the default
addons = {
  dns              = {}
  rbac             = {}
  hostpath-storage = {}
  metrics-server   = {}
  ingress          = {}
  registry         = { args = ["--size", "20Gi"] }   # adding an add-on
}
```

```bash
cd tp-local/bootstrap
terraform plan -var-file="<your-file>.tfvars" -out=bootstrap.tfplan   # + terraform_data.addon["registry"]
terraform apply bootstrap.tfplan
```

Removing an entry disables that add-on (volume data kept: the script answers
"n" to deletion prompts). Changing its `args` disables then re-enables it.

**Emergency (manual):** `microk8s enable <name>` / `microk8s disable <name>`.
Terraform will not see it. To realign a managed add-on afterwards:

```bash
terraform apply -replace='module.microk8s.terraform_data.addon["<name>"]'
```

## MK-09 DNS (CoreDNS)

**Status:** Pending external prerequisites.

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl run dnstest -n sandbox --rm -it --restart=Never --image=busybox:1.36 -- \
  nslookup kubernetes.default.svc.cluster.local
```

Expected: CoreDNS `Running`; the lookup returns the service IP. Upstream
DNS servers can be passed as `dns` add-on arguments (`addons.dns.args`); the
accepted syntax depends on the MicroK8s release: check
`microk8s enable dns --help` before changing it.

## MK-10 Storage (hostpath)

**Status:** Pending external prerequisites.

```bash
kubectl get storageclass         # microk8s-hostpath (default), microk8s-hostpath-retain
kubectl get pv,pvc -A
sudo ls /var/snap/microk8s/common/default-storage     # (sudo) volume data on the WSL disk
```

`microk8s-hostpath` deletes the data with the claim; `microk8s-hostpath-retain`
(stage 2) keeps the PersistentVolume and its data when the claim is deleted
(clean it manually). Volumes are local to the WSL virtual disk.

## MK-11 Ingress

**Status:** Pending external prerequisites.

```bash
kubectl -n ingress get daemonset,pods
kubectl get ingressclass                     # public
kubectl get ingress -A
curl -s -H 'Host: podinfo.localtest.me' "http://$(hostname -I | awk '{print $1}')/" | head -5
```

Expected: one controller pod `Running`; podinfo answers with JSON
containing `"hostname"`.

## MK-12 Metrics Server

**Status:** Pending external prerequisites.

```bash
kubectl -n kube-system get deployment metrics-server
kubectl top nodes
kubectl top pods -A
```

`error: Metrics API not available` right after enabling: wait one or two
minutes.

## MK-13 Local registry

**Status:** Implemented as an opt-in (not enabled by default); Pending
external prerequisites. Enable it through MK-08
(`registry = { args = ["--size", "20Gi"] }`), then push images to
`localhost:32000/<image>:<tag>` and reference them in workloads.
It depends on `hostpath-storage`.

## MK-14 Kubernetes API access

**Status:** Pending external prerequisites.

| Access path | Command | Needs |
|---|---|---|
| MicroK8s wrapper | `microk8s kubectl …` | `microk8s` group |
| Exported kubeconfig | `kubectl --kubeconfig ~/.kube/tp-local-microk8s.yaml …` | file from stage 1 |
| Raw API health | `curl -sk https://127.0.0.1:16443/readyz` | nothing (unauthenticated health endpoint) |

Re-export the kubeconfig (after certificate refresh, deleted file, or a
changed `api_server_address`):

```bash
cd tp-local/bootstrap
terraform apply -replace='module.microk8s.terraform_data.kubeconfig'
```

## References

* [01 Architecture §3 and §7](01-architecture.md#7-microk8s-add-ons)
* Module README: `modules/microk8s/README.md`
