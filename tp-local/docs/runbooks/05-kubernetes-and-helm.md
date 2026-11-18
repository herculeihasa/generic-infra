# 05 Kubernetes and Helm operations

| | |
|---|---|
| **Scope** | Stage 2 (`tp-local/environments/dev`): namespaces, RBAC, Kubernetes resources, Helm releases |
| **Status** | Configuration validated offline (`environments/dev/tests`, `modules/k8s-namespace/tests`); every cluster command **Pending external prerequisites** |
| **Code** | `environments/dev/main.tf`, `environments/dev/helm.tf`, `environments/dev/terraform.tfvars`, `modules/k8s-namespace/` |

**Context:** WSL; `export KUBECONFIG=~/.kube/tp-local-microk8s.yaml`;
Terraform commands in `tp-local/environments/dev`. Changes go through
`terraform.tfvars` → `terraform plan -out=dev.tfplan` → review →
`terraform apply dev.tfplan` ([04 TF-05](04-terraform-operations.md#tf-05-plan-and-apply-stage-2)).

## 1. What a managed namespace contains

| Element | `apps` | `sandbox` |
|---|---|---|
| Pod Security Admission (enforce / audit / warn) | baseline / restricted / restricted | privileged / baseline / baseline |
| ResourceQuota | requests 2 CPU / 4Gi, limits 4 CPU / 8Gi, 30 pods, 10 PVCs | none |
| LimitRange (container defaults) | requests 100m / 128Mi, limits 500m / 512Mi | none |
| Ingress isolation | default deny + same namespace + namespace `ingress` | open |
| Default service account | no token automount | no token automount |
| Service accounts | `app-deployer` bound to ClusterRole `edit` in `apps` | none |

Source: `environments/dev/terraform.tfvars`; mechanics:
`modules/k8s-namespace/README.md`.

## K8S-01 Add, change or remove a namespace

**Status:** Pending external prerequisites.

```hcl
# environments/dev/terraform.tfvars — add an entry to `namespaces`
namespaces = {
  # ... apps, sandbox ...
  monitoring = {
    pod_security                  = { enforce = "baseline" }
    allow_ingress_from_namespaces = ["ingress"]
    limit_range = {
      default_request = { cpu = "50m", memory = "64Mi" }
      default_limit   = { cpu = "250m", memory = "256Mi" }
    }
  }
}
```

Names must be RFC 1123 labels; `default`, `kube-system`, `kube-public`,
`kube-node-lease` and `ingress` are refused by validation.

> [!WARNING]
> Removing an entry **deletes the namespace and everything in it**
> (workloads, PVCs, secrets). Releases in `helm_releases` referencing it must
> be removed first (validation enforces it).

**Validation:**

```bash
kubectl get namespace monitoring --show-labels       # pod-security.kubernetes.io/* labels
kubectl -n monitoring get networkpolicy,limitrange,resourcequota
```

## K8S-02 Adjust quotas, limits and isolation

**Status:** Pending external prerequisites.

Edit `resource_quota`, `limit_range`, `default_deny_ingress` or
`allow_ingress_from_namespaces` of the namespace, plan, apply.

```bash
kubectl -n apps describe resourcequota apps-quota          # used vs hard
kubectl -n apps get limitrange apps-limits -o yaml
kubectl -n apps get networkpolicy                          # default-deny-ingress, allow-same-namespace, allow-from-namespaces
```

With a CPU/memory quota, pods without resources get the LimitRange
defaults; pods exceeding the quota are rejected (`exceeded quota` in the
ReplicaSet events).

## K8S-03 Manage RBAC

**Status:** Pending external prerequisites.

Service accounts and their namespace-scoped bindings are declared per
namespace:

```hcl
service_accounts = {
  app-deployer = { cluster_role = "edit" }   # RoleBinding app-deployer-edit in this namespace
  ci-reader    = { cluster_role = "view" }
}
role_bindings = {
  devs-view = { cluster_role = "view", subjects = [{ kind = "Group", name = "<group-name>" }] }
}
```

Verify effective permissions:

```bash
kubectl auth can-i create deployments -n apps --as=system:serviceaccount:apps:app-deployer   # yes
kubectl auth can-i create deployments -n sandbox --as=system:serviceaccount:apps:app-deployer # no
kubectl create token app-deployer -n apps --duration=1h      # short-lived token for a pipeline test
```

RBAC is enforced only with the `rbac` add-on enabled (stage 1 default). User
and Group subjects require an authentication method that provides those
identities; MicroK8s' default authentication is the admin certificate, so in
practice bindings are used with service accounts.

## K8S-04 Manage other Kubernetes resources

**Status:** Pending external prerequisites (outside Terraform by design).

Workloads that are not Helm releases of `helm_releases` are deployed with
`kubectl` into a managed namespace, which applies its quota, limits, Pod
Security level and network policies:

```bash
kubectl apply -n apps -f <manifest>.yaml
kubectl -n apps get all
```

Do not hand-edit objects created by Terraform (namespaces, policies,
quotas, service accounts): the next plan reverts them.

## K8S-05 Helm repositories

**Status:** Implemented. Terraform's Helm provider reads charts directly from
the `repository` URL of each release (`https://` or `oci://` only, enforced
by validation): no `helm repo add` is needed for deployments. For inspection
with the Helm CLI:

```bash
helm repo add podinfo https://stefanprodan.github.io/podinfo
helm repo update
helm search repo podinfo/podinfo --versions | head -5
```

## K8S-06 Install a release

**Status:** Pending external prerequisites.

Add an entry to `helm_releases` in `terraform.tfvars`:

```hcl
helm_releases = {
  # ... podinfo ...
  <release-name> = {
    namespace       = "apps"                       # must be a managed namespace
    repository      = "https://<chart-repository>"
    chart           = "<chart>"
    version         = "<exact-version>"            # ranges and "latest" are rejected
    timeout_seconds = 300
    values_yaml     = <<-YAML
      resources:
        requests: { cpu: 50m, memory: 64Mi }
        limits: { cpu: 200m, memory: 256Mi }
    YAML
  }
}
```

Releases are installed with `atomic` (rolled back if not healthy before the
timeout), `wait`, `cleanup_on_fail`, and keep 5 revisions. Set resources and
a `securityContext` compatible with the namespace's Pod Security level.

**Validation:** K8S-10.

## K8S-07 Upgrade a release

**Status:** Pending external prerequisites.

Change `version` (or `values_yaml`), plan (in-place update of
`helm_release.this["<release>"]`), apply. A failed upgrade is rolled back
automatically (`atomic`) and the apply fails with the Helm error.

```bash
helm history podinfo -n apps        # revisions and their status
```

## K8S-08 Roll back a release

**Status:** Pending external prerequisites.

**Preferred:** revert the change of `version`/`values_yaml` in Git and apply:
the desired state stays in code.

**Emergency:** roll back with Helm, then align the code before the next apply
(otherwise Terraform re-applies the configured version):

```bash
helm history podinfo -n apps
helm rollback podinfo <revision> -n apps --wait
```

## K8S-09 Remove a release

**Status:** Pending external prerequisites.

Delete its entry from `helm_releases`, plan (`helm_release.this["<release>"]`
will be destroyed), apply. Helm uninstalls every object of the release;
PersistentVolumeClaims created by StatefulSets may remain:
`kubectl -n <namespace> get pvc`.

## K8S-10 Check deployment health

**Status:** Pending external prerequisites.

```bash
terraform output helm_releases                       # status "deployed"
helm status podinfo -n apps
kubectl -n apps rollout status deployment/podinfo --timeout=120s
kubectl -n apps get pods,svc,ingress
curl -s -H 'Host: podinfo.localtest.me' "http://$(hostname -I | awk '{print $1}')/" | head -5
kubectl -n apps port-forward svc/podinfo 9898:9898   # then http://localhost:9898 (Windows browser too)
tp-local/scripts/verify-cluster.sh                   # repository root: all checks
```

Expected: release `deployed`, deployment rolled out, podinfo JSON response
with `"hostname"`.

## References

* [04 Terraform operations](04-terraform-operations.md), [03 MK-11 Ingress](03-microk8s-operations.md#mk-11-ingress)
* Module README: `modules/k8s-namespace/README.md`
