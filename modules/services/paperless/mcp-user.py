# The mcp user (README.md): view-only, sees every document and what files it through the mcp group, with the
# token from @token@. Run on every start and every 15 minutes, so new documents are shared too.
from django.contrib.auth.models import Group, Permission, User
from guardian.shortcuts import assign_perm
from rest_framework.authtoken.models import Token

from documents.models import Correspondent, Document, DocumentType, StoragePath, Tag

key = open("@token@").read().strip()

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
