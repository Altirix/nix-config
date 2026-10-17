# Incus authorization scriptlet for restricted TLS certificates (authorization.client.tls-restricted):
# they can view what is in their projects and the cluster around it, and change nothing.
#
# Left out on purpose:
#   can_view_operations, can_view_events: operation metadata carries websocket secrets
#     (migrations, image and backup transfers) that work without a trusted certificate.
#   can_view_sensitive (server config), certificates, warnings (server can_edit).
#   storage buckets: their backups export with can_view.
#   can_view_metrics, except for restricted metrics certificates, as Incus' own tls driver does.
# can_view still reads instance config (cloud-init included), NVRAM and logs, and exports existing
# custom volume backups. Incus also lets any trusted certificate replace or delete itself, GET
# network state, and cancel an operation it knows the id of when that has no permission attached.

PROJECT_TYPES = [
    "project",
    "instance",
    "image",
    "image_alias",
    "network",
    "network_acl",
    "network_address_set",
    "network_zone",
    "profile",
    "storage_volume",
]

def authorize(details, object, entitlement):
    cert = details.Certificate
    if details.Protocol != "tls" or cert == None or not cert.restricted:
        return False

    # --all-projects
    if details.IsAllProjectsRequest:
        return False

    kind, _, rest = object.partition(":")
    if kind == "server":
        if cert.type == "metrics":
            return entitlement == "can_view_metrics"
        return entitlement in ["can_view", "can_view_resources"]

    if entitlement != "can_view":
        return False

    if kind == "storage_pool":
        return True

    if kind in PROJECT_TYPES:
        return rest.split("/")[0] in cert.projects

    return False
