# 08 Maintenance and lifecycle

| | |
|---|---|
| **Scope** | Upgrades (MicroK8s, Terraform, providers, add-ons, charts), backups and restores, reset, full recreation and decommissioning |
| **Status** | Version pinning **Implemented**; channel-change logic covered by the stubbed script suite; every procedure on a real host **Pending external prerequisites** |
| **Code** | `tp-local/.terraform-version`, `bootstrap/variables.tf`, `environments/dev/versions.tf`, `environments/dev/.terraform.lock.hcl`, `environments/dev/terraform.tfvars`, `scripts/wsl/prepare-wsl.sh` |

## 1. What is pinned where

| Component | Pinned in | Updated by |
|---|---|---|
| Terraform CLI | `tp-local/.terraform-version` (read by `prepare-wsl.sh` and the pipeline); roots require `~> 1.17` | MNT-03 |
| Kubernetes and Helm providers | `environments/dev/versions.tf` (`~> 3.5`, `~> 3.3`) + lock file (four platforms) | MNT-04 |
| MicroK8s / Kubernetes | `microk8s_channel` (`1.35/stable`); patch releases arrive through snap refreshes | MNT-01, MNT-02 |
| MicroK8s add-ons | Delivered with the MicroK8s snap; selection and arguments in `addons` | MNT-05 |
| Helm charts | `version` of each `helm_releases` entry (`podinfo` 6.17.0) | MNT-06 |
| Ubuntu packages | `apt` (Terraform held by `apt-mark hold`) | `sudo apt update && sudo apt upgrade` |

## 2. Maintenance calendar

| When | Task | Procedure |
|---|---|---|
| Before any upgrade or risky change | Back up the state (and volume data if any) | MNT-07 |
| Weekly | `verify-cluster.sh`; pending refreshes `snap refresh --list`; disk `df -h /var` | [03 MK-01](03-microk8s-operations.md#mk-01-check-cluster-readiness), MNT-02 |
| Monthly | Chart updates; Terraform and provider releases | MNT-06, MNT-03, MNT-04 |
| Each Kubernetes minor release (about three per year) | MicroK8s upgrade, one minor at a time | MNT-01 |
| Before a Windows or WSL major update | Export the distribution | MNT-07 |

## MNT-01 Upgrade MicroK8s (Kubernetes minor version)

**Status:** Implemented (channel change through `snap refresh`; logic
covered by the stubbed suite); Pending external prerequisites.

**Prerequisites:** backup (MNT-07); move **one minor version at a time**;
stay on the same confinement (classic → `-strict` needs R-06 of
[07](07-troubleshooting-and-recovery.md#r-06-recreate-the-cluster-reinstall-microk8s)).
Root is needed, so the apply is interactive
([06 CD-08](06-cicd-and-deployment.md#cd-08-changes-that-need-root)).

1. List the available channels:

   ```bash
   snap info microk8s | grep -E '^\s+[0-9]+\.[0-9]+/stable'
   ```

2. Set `microk8s_channel` to `<next-minor>/stable` (default in
   `bootstrap/variables.tf`, or a tfvars file passed with `-var-file`), merge
   to `main`, update the WSL checkout. Local pipeline stages only run on a
   manual dispatch, so merging does not trigger the apply.
3. Plan and apply (WSL, `tp-local/bootstrap`):

   ```bash
   terraform plan -out=bootstrap.tfplan
   # expected: replace terraform_data.channel, .ready, .kubeconfig; addon[*] updated in place
   sudo -v
   terraform apply bootstrap.tfplan
   ```

**Validation:**

```bash
snap list microk8s                      # tracking <next-minor>/stable
kubectl get nodes                       # VERSION v<next-minor>.x
terraform -chdir=tp-local/environments/dev plan     # no changes expected
tp-local/scripts/verify-cluster.sh
```

**Rollback (not validated):** Kubernetes does not support minor-version
downgrades. Options: `sudo snap revert microk8s` (previous snap revision),
then set `microk8s_channel` back; or recreate the cluster and restore from
backup (07 R-06, MNT-08).

## MNT-02 Control automatic snap refreshes

**Status:** Not implemented by the code (host setting, operator choice).

snapd refreshes MicroK8s automatically within the tracked channel (patch
releases of the same minor version), which restarts its services. Inspect
and control it:

```bash
snap refresh --time                                   # refresh schedule, last and next refresh
snap refresh --list                                   # pending refreshes
sudo snap set system refresh.timer=sat,03:00-05:00    # (sudo) refresh window
sudo snap refresh --hold=72h microk8s                 # (sudo) postpone microk8s refreshes
sudo snap refresh --unhold microk8s                   # (sudo) resume
sudo snap refresh microk8s                            # (sudo) apply a pending refresh now, in a maintenance window
```

Holding indefinitely (`--hold` without duration) delays security fixes:
prefer a refresh window. After any refresh: `verify-cluster.sh`.

## MNT-03 Upgrade the Terraform CLI

**Status:** Implemented (single pinned version); Pending external
prerequisites.

1. Read the Terraform release notes; set the new version in
   `tp-local/.terraform-version` (the pipeline reads the same file). A new
   major version also needs `required_version` in `bootstrap/versions.tf`
   and `environments/dev/versions.tf`.
2. Run the offline gates ([04 TF-02](04-terraform-operations.md#tf-02-format-validate-and-test-offline))
   and open a pull request.
3. After merge, install it in WSL (repository root):

   ```bash
   sudo apt-mark unhold terraform          # (sudo) the script reinstalls the pinned version, then holds it again
   sudo tp-local/scripts/wsl/prepare-wsl.sh
   terraform version
   ```

**Validation:** `terraform version` shows the new version; `terraform plan`
in both roots shows `No changes.` Terraform upgrades the state format on the
next apply: the self-hosted runner uses the same binary, older binaries may
refuse the upgraded state.

## MNT-04 Upgrade the providers

**Status:** Pending external prerequisites (the offline steps can run
anywhere).

```bash
cd tp-local/environments/dev
terraform init -upgrade -backend=false
terraform providers lock -platform=windows_amd64 -platform=linux_amd64 -platform=darwin_amd64 -platform=darwin_arm64
terraform validate && terraform test
git diff .terraform.lock.hcl
```

A new **major** version (e.g. 4.x) also needs the constraints in
`environments/dev/versions.tf` and `modules/k8s-namespace/versions.tf`, and
a reading of the provider upgrade guide. After merge, in WSL:

```bash
tp-local/scripts/tf-init.sh environments/dev
cd tp-local/environments/dev && terraform plan     # expected: no changes
```

The pipeline initializes with `-lockfile=readonly`: the updated lock file
must be committed. **Rollback:** revert the commit and initialize again; if
the newer provider already wrote the state, restore the state backup (07 R-03).

## MNT-05 Update the add-ons

**Status:** Implemented.

| Need | Procedure |
|---|---|
| Newer add-on versions | Come with MicroK8s upgrades and refreshes (MNT-01, MNT-02) |
| Re-apply an add-on (e.g. after an upgrade) | [04 TF-08](04-terraform-operations.md#tf-08-re-run-a-provisioning-step) (replace `addon["<name>"]`: disable + enable, short outage of that add-on; volume data kept) |
| Add, remove or change arguments | [03 MK-08](03-microk8s-operations.md#mk-08-manage-add-ons) |

Check the running versions: `kubectl get deploy,daemonset -A -o wide`
(IMAGES column).

## MNT-06 Update Helm charts

**Status:** Pending external prerequisites.

```bash
helm repo add podinfo https://stefanprodan.github.io/podinfo && helm repo update
helm search repo podinfo/podinfo --versions | head -5
```

Read the chart changelog, then bump `version` in `terraform.tfvars`:
[05 K8S-07](05-kubernetes-and-helm.md#k8s-07-upgrade-a-release) (rollback: K8S-08).

## MNT-07 Back up the environment

**Status:** Pending external prerequisites.

| Item | Location | Back up? |
|---|---|---|
| Terraform state, both stages | `~/.local/state/tp-local/` | **Yes**: without it, recovery needs imports (07 R-04) |
| Application volume data | `/var/snap/microk8s/common/default-storage` (one directory per volume) | Yes, if workloads hold data |
| Objects created outside Terraform ([05 K8S-04](05-kubernetes-and-helm.md#k8s-04-manage-other-kubernetes-resources)) | Cluster | Keep their manifests in Git |
| Kubeconfig | `~/.kube/tp-local-microk8s.yaml` | **No**: cluster-admin credential, re-exported by 07 R-02 |
| Code, tfvars | Git | Push |

```bash
mkdir -p ~/backups && chmod 700 ~/backups
tar -czf ~/backups/tp-local-state-$(date +%Y%m%d).tgz -C ~/.local/state tp-local
sudo tar -czf ~/backups/tp-local-volumes-$(date +%Y%m%d).tgz -C /var/snap/microk8s/common default-storage   # (sudo)
```

Stop or scale down writing workloads before copying volume data. Copy the
archives off the distribution (e.g. `/mnt/c/Users/<windows-user>/<backup-folder>/`),
since deleting the distribution deletes `~/backups`.

Whole distribution (everything at once, including the cluster):

```powershell
wsl --shutdown
wsl --export Ubuntu-24.04 "<backup-folder>\ubuntu-24.04-tp-local.tar"
```

> [!WARNING]
> State archives contain Kubernetes object specifications and Helm values;
> distribution exports also contain the cluster certificates and the
> kubeconfig. Keep them out of shared or synced folders.

## MNT-08 Restore

**Status:** Pending external prerequisites.

| What | Procedure |
|---|---|
| A state file | Copy the current file aside, extract the archive (`tar -xzf <archive> -C ~/.local/state`), then `terraform plan` (same rules as 07 R-03) |
| Volume data, same cluster | Workloads stopped, `sudo tar -xzf <archive> -C /var/snap/microk8s/common` |
| Volume data, recreated cluster | New volumes have new directories: copy the data into the path given by `kubectl get pv <pv> -o jsonpath='{.spec.hostPath.path}'` |
| Whole distribution | PowerShell: `wsl --import Ubuntu-24.04 "<install-folder>" "<backup-folder>\ubuntu-24.04-tp-local.tar" --version 2` (after `wsl --unregister` of the broken one). An imported distribution logs in as root: set `[user] default=<linux-user>` in `/etc/wsl.conf`, then `wsl --shutdown` |

## MNT-09 Reset workloads and configuration

**Status:** Pending external prerequisites.

Returns the cluster to the state defined in code, MicroK8s kept:

1. Destroy stage 2, then apply it again
   ([04 TF-10](04-terraform-operations.md#tf-10-destroy) first part,
   [TF-05](04-terraform-operations.md#tf-05-plan-and-apply-stage-2)).
2. Objects created outside Terraform in other namespaces are not touched:
   delete them with `kubectl`.
3. Volumes of `microk8s-hostpath-retain` survive: list them with
   `kubectl get pv` and delete the ones no longer needed.

Complete cluster reset (MicroK8s reinstalled):
[07 R-06](07-troubleshooting-and-recovery.md#r-06-recreate-the-cluster-reinstall-microk8s).

## MNT-10 Recreate the workstation environment

**Status:** Pending external prerequisites.

> [!CAUTION]
> `wsl --unregister` deletes the distribution and **everything in it**:
> repository clone, Terraform state, cluster, volumes, runner. It cannot be
> undone.

1. Back up (MNT-07) and push any work in progress.
2. Remove the runner registration ([06 CD-10](06-cicd-and-deployment.md#cd-10-pause-or-remove-the-self-hosted-runner)).
3. PowerShell: `wsl --unregister Ubuntu-24.04`.
4. Rebuild: [02 SET-02](02-wsl-initial-setup.md#set-02-install-wsl-and-the-ubuntu-distribution) to SET-11,
   with an **empty** state (an old stage 1 state would describe a cluster
   that no longer exists).
5. Restore volume data if needed (MNT-08), register the runner again
   ([06 CD-03](06-cicd-and-deployment.md#cd-03-register-the-self-hosted-wsl-runner)).

## MNT-11 Decommission

**Status:** Pending external prerequisites.

1. Back up what must be kept (MNT-07).
2. Destroy both stages and uninstall MicroK8s
   ([04 TF-10](04-terraform-operations.md#tf-10-destroy) with `uninstall_on_destroy=true`).
3. Disable local deployments and remove the runner
   ([06 CD-10](06-cicd-and-deployment.md#cd-10-pause-or-remove-the-self-hosted-runner)).
4. Delete copies of the kubeconfig, e.g. on Windows:
   `Remove-Item "$env:USERPROFILE\.kube\tp-local-microk8s.yaml"` (PowerShell).
5. Once `terraform state list` is empty in both roots:
   `rm -rf ~/.local/state/tp-local`.
6. Optional: `wsl --unregister Ubuntu-24.04` (see MNT-10 caution).

## References

* [04 Terraform operations](04-terraform-operations.md), [07 Troubleshooting and recovery](07-troubleshooting-and-recovery.md)
* [CI/CD documentation](../../../docs/ci-cd.md)
