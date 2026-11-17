# Module `k8s-namespace`

Creates a Kubernetes namespace with a security baseline (Kubernetes provider
3.x, `*_v1` resources). Works on any conformant cluster (MicroK8s, AKS, ...).

| Feature | Resources |
|---|---|
| Pod Security Admission (enforce `baseline`, audit/warn `restricted` by default) | namespace labels |
| No token automount for pods using the default service account | `kubernetes_default_service_account_v1` |
| Resource consumption limits (optional) | `kubernetes_resource_quota_v1`, `kubernetes_limit_range_v1` |
| Ingress isolation: default deny, same-namespace allowed, listed namespaces allowed (e.g. `ingress`) | `kubernetes_network_policy_v1` x 3 |
| Workload identities bound to a ClusterRole **inside this namespace only** | `kubernetes_service_account_v1`, `kubernetes_role_binding_v1` |
| User/group access (namespace-scoped) | `kubernetes_role_binding_v1` |

Network policies need a CNI that enforces them (MicroK8s' default Calico
does). RoleBindings need RBAC authorization (MicroK8s `rbac` add-on).

## Usage

```hcl
module "apps_namespace" {
  source = "../../modules/k8s-namespace"

  name = "apps"
  resource_quota = { "requests.cpu" = "2", "limits.memory" = "8Gi", pods = "30" }
  limit_range = {
    default_request = { cpu = "100m", memory = "128Mi" }
    default_limit   = { cpu = "500m", memory = "512Mi" }
  }
  network_policy   = { allow_from_namespaces = ["ingress"] }
  service_accounts = { app-deployer = { cluster_role = "edit" } }
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | required | RFC 1123 label; system/add-on namespaces refused. |
| `labels` / `annotations` | map(string) | `{}` | Extra metadata. |
| `pod_security` | object({ enforce, audit, warn }) | `baseline` / `restricted` / `restricted` | PSA levels: privileged, baseline, restricted. |
| `resource_quota` | map(string) | `{}` | ResourceQuota `hard` (empty = none). |
| `limit_range` | object({ default_request, default_limit, max }) | `null` | Container defaults. |
| `network_policy` | object({ default_deny_ingress, allow_same_namespace, allow_from_namespaces }) | `true`, `true`, `[]` | Ingress isolation. |
| `service_accounts` | map(object({ cluster_role, automount_token })) | `{}` | SAs, optionally bound to a ClusterRole in the namespace. |
| `role_bindings` | map(object({ cluster_role, subjects = [{ kind = User\|Group, name }] })) | `{}` | User/group bindings. |

## Outputs

`name`, `service_account_names`, `pod_security_enforce`, `network_isolated`.

## Tests

```bash
terraform init -backend=false && terraform test   # mocked kubernetes provider
```
