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

## Inputs and outputs

Types, defaults and descriptions: [Reference (generated)](#reference-generated).

## Tests

```bash
terraform init -backend=false && terraform test   # mocked kubernetes provider
```

## Reference (generated)

Generated from the module code by [terraform-docs](https://terraform-docs.io/)
(configuration: `.terraform-docs.yml` at the repository root). Do not edit
between the markers: change the code, then run
`pre-commit run terraform-docs --all-files`.

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.9.0, < 2.0.0 |
| kubernetes | >= 3.5.0, < 4.0.0 |

### Providers

| Name | Version |
| ---- | ------- |
| kubernetes | >= 3.5.0, < 4.0.0 |

### Modules

No modules.

### Resources

| Name | Type |
| ---- | ---- |
| [kubernetes_default_service_account_v1.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/default_service_account_v1) | resource |
| [kubernetes_limit_range_v1.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/limit_range_v1) | resource |
| [kubernetes_namespace_v1.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |
| [kubernetes_network_policy_v1.allow_from_namespaces](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/network_policy_v1) | resource |
| [kubernetes_network_policy_v1.allow_same_namespace](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/network_policy_v1) | resource |
| [kubernetes_network_policy_v1.default_deny_ingress](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/network_policy_v1) | resource |
| [kubernetes_resource_quota_v1.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/resource_quota_v1) | resource |
| [kubernetes_role_binding_v1.service_account](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/role_binding_v1) | resource |
| [kubernetes_role_binding_v1.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/role_binding_v1) | resource |
| [kubernetes_service_account_v1.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_account_v1) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Namespace name (RFC 1123 label). System namespaces are refused: the module creates and owns the namespace. | `string` | n/a | yes |
| annotations | Namespace annotations. | `map(string)` | `{}` | no |
| labels | Additional namespace labels. | `map(string)` | `{}` | no |
| limit\_range | Container defaults (default\_request / default\_limit) and optional max, e.g. { default\_request = { cpu = "100m", memory = "128Mi" }, default\_limit = { cpu = "500m", memory = "512Mi" } }. Null = no LimitRange. | ```object({ default_request = map(string) default_limit = map(string) max = optional(map(string), {}) })``` | `null` | no |
| network\_policy | Ingress isolation. default\_deny\_ingress blocks all inbound traffic to the namespace except from the same namespace (allow\_same\_namespace) and from allow\_from\_namespaces (e.g. ["ingress"] for the MicroK8s ingress controller). Egress stays open. | ```object({ default_deny_ingress = optional(bool, true) allow_same_namespace = optional(bool, true) allow_from_namespaces = optional(list(string), []) })``` | `{}` | no |
| pod\_security | Pod Security Admission levels (privileged \| baseline \| restricted): enforce rejects violating pods, audit/warn only report. | ```object({ enforce = optional(string, "baseline") audit = optional(string, "restricted") warn = optional(string, "restricted") })``` | `{}` | no |
| resource\_quota | ResourceQuota `hard` limits (e.g. { "requests.cpu" = "2", "limits.memory" = "8Gi", pods = "30" }). Empty = no quota. With CPU/memory quotas, pair it with limit\_range so pods without resources still get defaults. | `map(string)` | `{}` | no |
| role\_bindings | Namespace-scoped bindings of ClusterRoles to users or groups (binding name => { cluster\_role, subjects = [{ kind = User\|Group, name }] }). | ```map(object({ cluster_role = string subjects = list(object({ kind = string name = string })) }))``` | `{}` | no |
| service\_accounts | Service accounts to create (name => settings). cluster\_role (e.g. "edit", "view") is bound inside this namespace only. Tokens are not automounted unless automount\_token = true. | ```map(object({ cluster_role = optional(string) automount_token = optional(bool, false) }))``` | `{}` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| name | Namespace name (depends on the namespace resource: use it to order dependent resources such as Helm releases). |
| network\_isolated | Whether inbound traffic is denied by default. |
| pod\_security\_enforce | Enforced Pod Security Admission level. |
| service\_account\_names | Service accounts created in the namespace. |
<!-- END_TF_DOCS -->
