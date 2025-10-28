# Security policies for Kubernetes manifests
# These policies enforce security best practices across all deployments

package main

import future.keywords.contains
import future.keywords.if
import future.keywords.in

##############################################################################
# DENY: Images using :latest tag
##############################################################################

deny[msg] {
	input.kind == "Deployment"
	some container in input.spec.template.spec.containers
	endswith(container.image, ":latest")
	msg := sprintf("Container '%s' uses :latest tag. Use specific version tags or SHA digests.", [container.name])
}

deny[msg] {
	input.kind == "Deployment"
	some container in input.spec.template.spec.containers
	not contains(container.image, ":")
	msg := sprintf("Container '%s' has no tag specified (defaults to :latest). Use specific version tags.", [container.name])
}

##############################################################################
# DENY: Missing runAsNonRoot
##############################################################################

deny[msg] {
	input.kind == "Deployment"
	not input.spec.template.spec.securityContext.runAsNonRoot
	msg := "Deployment must set spec.template.spec.securityContext.runAsNonRoot: true"
}

deny[msg] {
	input.kind == "Deployment"
	input.spec.template.spec.securityContext.runAsNonRoot != true
	msg := "Deployment must set securityContext.runAsNonRoot to true (currently false or missing)"
}

##############################################################################
# DENY: Missing resource limits
##############################################################################

deny[msg] {
	input.kind == "Deployment"
	some container in input.spec.template.spec.containers
	not container.resources.limits
	msg := sprintf("Container '%s' must define resources.limits (cpu and memory)", [container.name])
}

deny[msg] {
	input.kind == "Deployment"
	some container in input.spec.template.spec.containers
	not container.resources.requests
	msg := sprintf("Container '%s' must define resources.requests (cpu and memory)", [container.name])
}

##############################################################################
# DENY: Privileged containers
##############################################################################

deny[msg] {
	input.kind == "Deployment"
	some container in input.spec.template.spec.containers
	container.securityContext.privileged == true
	msg := sprintf("Container '%s' cannot run in privileged mode", [container.name])
}

##############################################################################
# DENY: Host network access
##############################################################################

deny[msg] {
	input.kind == "Deployment"
	input.spec.template.spec.hostNetwork == true
	msg := "Deployment cannot use hostNetwork: true"
}

##############################################################################
# DENY: Host PID access
##############################################################################

deny[msg] {
	input.kind == "Deployment"
	input.spec.template.spec.hostPID == true
	msg := "Deployment cannot use hostPID: true"
}

##############################################################################
# DENY: Host IPC access
##############################################################################

deny[msg] {
	input.kind == "Deployment"
	input.spec.template.spec.hostIPC == true
	msg := "Deployment cannot use hostIPC: true"
}

##############################################################################
# WARN: Missing readOnlyRootFilesystem
##############################################################################

warn[msg] {
	input.kind == "Deployment"
	some container in input.spec.template.spec.containers
	not container.securityContext.readOnlyRootFilesystem
	msg := sprintf("Container '%s' should set securityContext.readOnlyRootFilesystem: true", [container.name])
}

##############################################################################
# WARN: Missing security context at container level
##############################################################################

warn[msg] {
	input.kind == "Deployment"
	some container in input.spec.template.spec.containers
	not container.securityContext
	msg := sprintf("Container '%s' should define securityContext with runAsNonRoot and readOnlyRootFilesystem", [container.name])
}

##############################################################################
# PRODUCTION-ONLY: Require SHA digests instead of tags
##############################################################################

deny[msg] {
	input.kind == "Deployment"
	input.metadata.namespace == "claude-hub-prod"  # Only for prod
	some container in input.spec.template.spec.containers
	not contains(container.image, "@sha256:")
	msg := sprintf("Production deployment: Container '%s' must use SHA digest (image@sha256:...)", [container.name])
}

##############################################################################
# Utility functions
##############################################################################

# Check if metadata has specific label
has_label(label_name) {
	input.metadata.labels[label_name]
}

# Check if deployment is in specific namespace
in_namespace(ns) {
	input.metadata.namespace == ns
}
