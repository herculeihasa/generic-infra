# =============================================================================
# MicroK8s on a systemd-based Ubuntu host (WSL2 or native)
#
# No Terraform provider manages snaps, so each step is a terraform_data
# resource running an idempotent script at APPLY time (plans have no side
# effects). Scripts live in ./scripts and can also be run by hand.
#
#   install     snap install (once) + CLI access for the current user
#   channel     snap refresh when var.channel changes (in place, keeps data)
#   addon[*]    one resource per add-on: enable on create, disable on destroy
#   ready       readiness gate (services, node, deployments, daemonsets)
#   kubeconfig  admin kubeconfig export, server rewritten to 127.0.0.1
#
# Re-run a step after manual changes on the host, e.g.:
#   terraform apply -replace='module.microk8s.terraform_data.kubeconfig'
# =============================================================================

resource "terraform_data" "install" {
  # Stored for the destroy-time provisioner (it can only read self).
  # Changing these values updates the state in place, it does not reinstall.
  input = {
    scripts_dir          = local.scripts_dir
    uninstall_on_destroy = var.uninstall_on_destroy
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash"]
    command     = "${local.scripts_dir}/install.sh"
    environment = {
      MICROK8S_CHANNEL     = var.channel
      WAIT_TIMEOUT_SECONDS = tostring(var.wait_timeout_seconds)
    }
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash"]
    command     = "${self.input.scripts_dir}/uninstall.sh"
    environment = {
      UNINSTALL = tostring(self.input.uninstall_on_destroy)
    }
  }
}

# Separate from "install" on purpose: a channel change replaces THIS resource
# (snap refresh) and never triggers the uninstall attached to "install".
resource "terraform_data" "channel" {
  triggers_replace = [var.channel]

  input = {
    channel = var.channel
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash"]
    command     = "${local.scripts_dir}/set-channel.sh"
    environment = {
      MICROK8S_CHANNEL     = var.channel
      WAIT_TIMEOUT_SECONDS = tostring(var.wait_timeout_seconds)
    }
  }

  depends_on = [terraform_data.install]
}

# One resource per add-on so that removing an entry disables only that
# add-on. Changing its arguments re-enables it (disable + enable).
resource "terraform_data" "addon" {
  for_each = var.addons

  triggers_replace = [
    terraform_data.install.id,
    jsonencode(each.value.args),
  ]

  input = {
    name        = each.key
    channel     = var.channel
    scripts_dir = local.scripts_dir
  }

  # Terraform appends `command` as ONE argument: the script goes in the
  # interpreter list and the action is the command.
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "${local.scripts_dir}/addon.sh"]
    command     = "enable"
    environment = {
      ADDON_NAME       = each.key
      ADDON_ARGS       = join("\n", each.value.args)
      MICROK8S_CHANNEL = var.channel
    }
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "${self.input.scripts_dir}/addon.sh"]
    command     = "disable"
    environment = {
      ADDON_NAME       = self.input.name
      MICROK8S_CHANNEL = self.input.channel
    }
  }

  depends_on = [terraform_data.channel]
}

resource "terraform_data" "ready" {
  triggers_replace = [
    terraform_data.install.id,
    terraform_data.channel.id,
    sort([for addon in terraform_data.addon : addon.id]),
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash"]
    command     = "${local.scripts_dir}/wait-ready.sh"
    environment = {
      MICROK8S_CHANNEL     = var.channel
      WAIT_TIMEOUT_SECONDS = tostring(var.wait_timeout_seconds)
    }
  }
}

resource "terraform_data" "kubeconfig" {
  # Re-exported when the cluster is (re)installed, its channel changes, or
  # the destination/address change.
  triggers_replace = [
    terraform_data.install.id,
    terraform_data.channel.id,
    local.kubeconfig_path,
    var.api_server_address,
  ]

  input = {
    path = local.kubeconfig_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash"]
    command     = "${local.scripts_dir}/export-kubeconfig.sh"
    environment = {
      MICROK8S_CHANNEL   = var.channel
      KUBECONFIG_PATH    = local.kubeconfig_path
      API_SERVER_ADDRESS = var.api_server_address
    }
  }

  # Only removes the file this module wrote.
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = "rm -f -- \"$KUBECONFIG_PATH\""
    environment = {
      KUBECONFIG_PATH = self.input.path
    }
  }

  # Exported once the cluster and its add-ons (e.g. rbac) are settled.
  depends_on = [terraform_data.ready]
}
