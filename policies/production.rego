# Production Security Policies
# Stricter policies for production environment beyond base security.rego

package main

import future.keywords.contains
import future.keywords.if
import future.keywords.in

##############################################################################
# PRODUCTION: Require SHA256 digests (not just version tags)
##############################################################################

deny[msg] {
	input.kind == "Deployment"
	input.metadata.labels.environment == "prod"
	some container in input.spec.template.spec.containers
	not contains(container.image, "@sha256:")
	msg := sprintf("Production deployment '%s' container '%s' must use SHA256 digest (image@sha256:...), not version tags", [input.metadata.name, container.name])
}

##############################################################################
# PRODUCTION: Require runAsNonRoot at container level
##############################################################################

deny[msg] {
	input.kind == "Deployment"
	input.metadata.labels.environment == "prod"
	some container in input.spec.template.spec.containers
	not container.securityContext.runAsNonRoot == true
	msg := sprintf("Production deployment '%s' container '%s' must set securityContext.runAsNonRoot: true", [input.metadata.name, container.name])
}

##############################################################################
# PRODUCTION: Require resource limits
##############################################################################

deny[msg] {
	input.kind == "Deployment"
	input.metadata.labels.environment == "prod"
	some container in input.spec.template.spec.containers
	not container.resources.limits.cpu
	msg := sprintf("Production deployment '%s' container '%s' must define resources.limits.cpu", [input.metadata.name, container.name])
}

deny[msg] {
	input.kind == "Deployment"
	input.metadata.labels.environment == "prod"
	some container in input.spec.template.spec.containers
	not container.resources.limits.memory
	msg := sprintf("Production deployment '%s' container '%s' must define resources.limits.memory", [input.metadata.name, container.name])
}

##############################################################################
# PRODUCTION: Require resource requests
##############################################################################

deny[msg] {
	input.kind == "Deployment"
	input.metadata.labels.environment == "prod"
	some container in input.spec.template.spec.containers
	not container.resources.requests.cpu
	msg := sprintf("Production deployment '%s' container '%s' must define resources.requests.cpu", [input.metadata.name, container.name])
}

deny[msg] {
	input.kind == "Deployment"
	input.metadata.labels.environment == "prod"
	some container in input.spec.template.spec.containers
	not container.resources.requests.memory
	msg := sprintf("Production deployment '%s' container '%s' must define resources.requests.memory", [input.metadata.name, container.name])
}

##############################################################################
# PRODUCTION: Require seccomp profile
##############################################################################

deny[msg] {
	input.kind == "Deployment"
	input.metadata.labels.environment == "prod"
	not input.spec.template.spec.securityContext.seccompProfile.type
	msg := sprintf("Production deployment '%s' must set securityContext.seccompProfile.type (recommend: RuntimeDefault)", [input.metadata.name])
}

deny[msg] {
	input.kind == "Deployment"
	input.metadata.labels.environment == "prod"
	input.spec.template.spec.securityContext.seccompProfile.type != "RuntimeDefault"
	input.spec.template.spec.securityContext.seccompProfile.type != "Localhost"
	msg := sprintf("Production deployment '%s' seccompProfile must be RuntimeDefault or Localhost, not %s", [input.metadata.name, input.spec.template.spec.securityContext.seccompProfile.type])
}

##############################################################################
# PRODUCTION: Require readOnlyRootFilesystem
##############################################################################

deny[msg] {
	input.kind == "Deployment"
	input.metadata.labels.environment == "prod"
	some container in input.spec.template.spec.containers
	not container.securityContext.readOnlyRootFilesystem == true
	msg := sprintf("Production deployment '%s' container '%s' should set securityContext.readOnlyRootFilesystem: true", [input.metadata.name, container.name])
}

##############################################################################
# PRODUCTION: Require allowPrivilegeEscalation = false
##############################################################################

deny[msg] {
	input.kind == "Deployment"
	input.metadata.labels.environment == "prod"
	some container in input.spec.template.spec.containers
	not container.securityContext.allowPrivilegeEscalation == false
	msg := sprintf("Production deployment '%s' container '%s' must set securityContext.allowPrivilegeEscalation: false", [input.metadata.name, container.name])
}

##############################################################################
# PRODUCTION: Require capabilities dropped
##############################################################################

deny[msg] {
	input.kind == "Deployment"
	input.metadata.labels.environment == "prod"
	some container in input.spec.template.spec.containers
	not container.securityContext.capabilities.drop
	msg := sprintf("Production deployment '%s' container '%s' must drop capabilities (minimum: [ALL])", [input.metadata.name, container.name])
}

deny[msg] {
	input.kind == "Deployment"
	input.metadata.labels.environment == "prod"
	some container in input.spec.template.spec.containers
	container.securityContext.capabilities.drop
	not "ALL" in container.securityContext.capabilities.drop
	msg := sprintf("Production deployment '%s' container '%s' must drop ALL capabilities", [input.metadata.name, container.name])
}

##############################################################################
# PRODUCTION: Require liveness and readiness probes
##############################################################################

deny[msg] {
	input.kind == "Deployment"
	input.metadata.labels.environment == "prod"
	some container in input.spec.template.spec.containers
	not container.livenessProbe
	msg := sprintf("Production deployment '%s' container '%s' must define livenessProbe", [input.metadata.name, container.name])
}

deny[msg] {
	input.kind == "Deployment"
	input.metadata.labels.environment == "prod"
	some container in input.spec.template.spec.containers
	not container.readinessProbe
	msg := sprintf("Production deployment '%s' container '%s' must define readinessProbe", [input.metadata.name, container.name])
}

##############################################################################
# PRODUCTION: Require replicas >= 2 for HA
##############################################################################

deny[msg] {
	input.kind == "Deployment"
	input.metadata.labels.environment == "prod"
	not input.metadata.labels["allow-single-replica"] == "true"
	input.spec.replicas < 2
	msg := sprintf("Production deployment '%s' must have replicas >= 2 for HA (or set label allow-single-replica: 'true')", [input.metadata.name])
}

##############################################################################
# PRODUCTION: Require pod disruption budget reference
##############################################################################

warn[msg] {
	input.kind == "Deployment"
	input.metadata.labels.environment == "prod"
	input.spec.replicas >= 2
	not input.metadata.labels["pdb-name"]
	msg := sprintf("Production deployment '%s' with multiple replicas should reference a PodDisruptionBudget (label: pdb-name)", [input.metadata.name])
}

##############################################################################
# PRODUCTION: Block latest tags
##############################################################################

deny[msg] {
	input.kind == "Deployment"
	input.metadata.labels.environment == "prod"
	some container in input.spec.template.spec.containers
	endswith(container.image, ":latest")
	msg := sprintf("Production deployment '%s' container '%s' cannot use :latest tag", [input.metadata.name, container.name])
}

##############################################################################
# PRODUCTION: Require specific user ID range (not root)
##############################################################################

deny[msg] {
	input.kind == "Deployment"
	input.metadata.labels.environment == "prod"
	input.spec.template.spec.securityContext.runAsUser < 1000
	msg := sprintf("Production deployment '%s' runAsUser must be >= 1000 (currently: %d)", [input.metadata.name, input.spec.template.spec.securityContext.runAsUser])
}

##############################################################################
# PRODUCTION: Require fsGroup for volume permissions
##############################################################################

warn[msg] {
	input.kind == "Deployment"
	input.metadata.labels.environment == "prod"
	input.spec.template.spec.volumes
	not input.spec.template.spec.securityContext.fsGroup
	msg := sprintf("Production deployment '%s' with volumes should set securityContext.fsGroup for proper permissions", [input.metadata.name])
}

##############################################################################
# PRODUCTION: Require environment label
##############################################################################

deny[msg] {
	input.kind == "Deployment"
	input.metadata.namespace == "claude-hub-prod"
	not input.metadata.labels.environment == "prod"
	msg := sprintf("Deployment '%s' in claude-hub-prod namespace must have label environment: prod", [input.metadata.name])
}
