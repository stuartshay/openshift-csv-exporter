"""SQLAlchemy ORM models for OCP audit data.

Models are split into per-audit-area submodules; this package re-exports
every class so ``from schema.models import X`` continues to work.
"""

from .api_console import ApiServerConsoleAccess
from .cluster import Cluster, ClusterEnv
from .configuration import PlatformGuardrail, PolicyAsCodeConstraint
from .credentials import ClusterAdminBinding, CredentialManagementSecret
from .oauth import OAuthExternalAuth
from .overview import ClusterOverview
from .rbac import (
    ClusterRole,
    ClusterRoleBinding,
    ClusterRoleBindingSubject,
    ClusterRoleRule,
    ClusterRoleRuleApiGroup,
    ClusterRoleRuleNonResourceUrl,
    ClusterRoleRuleResource,
    ClusterRoleRuleVerb,
    SelfProvisionerBinding,
    SelfProvisionerSubject,
)
from .worker_node import WorkerNodeAuth

__all__ = [
    "ApiServerConsoleAccess",
    "Cluster",
    "ClusterAdminBinding",
    "ClusterEnv",
    "ClusterOverview",
    "ClusterRole",
    "ClusterRoleBinding",
    "ClusterRoleBindingSubject",
    "ClusterRoleRule",
    "ClusterRoleRuleApiGroup",
    "ClusterRoleRuleNonResourceUrl",
    "ClusterRoleRuleResource",
    "ClusterRoleRuleVerb",
    "CredentialManagementSecret",
    "OAuthExternalAuth",
    "PlatformGuardrail",
    "PolicyAsCodeConstraint",
    "SelfProvisionerBinding",
    "SelfProvisionerSubject",
    "WorkerNodeAuth",
]
