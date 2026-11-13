# The mcp user (README.md): view-only, sees every document and what files it through the mcp group, with the
# token from $TOKEN_FILE. A workflow shares each document with the group as it's added; this runs on every start and
# every 15 minutes for whatever came before it, and for new tags, correspondents and the like.
import os

from django.contrib.auth.models import Group, Permission, User
from guardian.shortcuts import assign_perm
from rest_framework.authtoken.models import Token

from documents.models import (
    Correspondent, Document, DocumentType, StoragePath, Tag, Workflow, WorkflowAction, WorkflowTrigger,
)

key = open(os.environ["TOKEN_FILE"]).read().strip()

group, _ = Group.objects.get_or_create(name="mcp")
user, created = User.objects.get_or_create(username="mcp")
if created:
    user.set_unusable_password()
    user.save()
user.groups.add(group)

# Global view permissions, which owner-aware lists still narrow to what's shared: hence the sharing below.
group.permissions.set(Permission.objects.filter(codename__in=[
    "view_document", "view_note", "view_customfield",
    "view_tag", "view_correspondent", "view_documenttype", "view_storagepath",
]))

Token.objects.filter(user=user).exclude(key=key).delete()
Token.objects.get_or_create(user=user, key=key)

# Everything you own is shared with the group to view, never to change.
for model, perm in [
    (Document, "view_document"),
    (Tag, "view_tag"),
    (Correspondent, "view_correspondent"),
    (DocumentType, "view_documenttype"),
    (StoragePath, "view_storagepath"),
]:
    assign_perm(perm, group, model.objects.all())

# Every new document, from any source, shared with the group to view as it's added.
workflow, created = Workflow.objects.get_or_create(name="mcp: share new documents", defaults={"order": 0})
if created:
    trigger = WorkflowTrigger.objects.create(type=WorkflowTrigger.WorkflowTriggerType.DOCUMENT_ADDED)
    action = WorkflowAction.objects.create(type=WorkflowAction.WorkflowActionType.ASSIGNMENT)
    workflow.triggers.add(trigger)
    workflow.actions.add(action)
workflow.enabled = True
workflow.save()
for action in workflow.actions.all():
    action.assign_view_groups.add(group)
