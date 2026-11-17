"""Emite user delegation SAS para upload de um único blob.

A Function usa a própria managed identity (DefaultAzureCredential): não há chave da
conta de armazenamento em lugar nenhum, e a conta pode ficar com shared key desabilitada.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from azure.identity import DefaultAzureCredential
from azure.storage.blob import (
    BlobSasPermissions,
    BlobServiceClient,
    UserDelegationKey,
    generate_blob_sas,
)

from sas_logic import sas_window

# A user delegation key vale até 7 dias; aqui ela vale 1 hora e é reaproveitada.
_KEY_LIFETIME = timedelta(hours=1)


@dataclass(frozen=True)
class IssuedSas:
    upload_url: str
    blob_name: str
    expires_on: datetime


class UploadSasIssuer:
    def __init__(self, account_url: str, container: str, ttl_minutes: int, credential=None):
        self._service = BlobServiceClient(
            account_url, credential=credential or DefaultAzureCredential()
        )
        self._container = container
        self._ttl_minutes = ttl_minutes
        self._key: UserDelegationKey | None = None
        self._key_expiry: datetime | None = None

    def _delegation_key(self, now: datetime) -> UserDelegationKey:
        needed_until = now + timedelta(minutes=self._ttl_minutes + 5)
        if self._key is None or self._key_expiry is None or self._key_expiry < needed_until:
            expiry = now + max(_KEY_LIFETIME, timedelta(minutes=self._ttl_minutes + 10))
            self._key = self._service.get_user_delegation_key(
                key_start_time=now - timedelta(minutes=5), key_expiry_time=expiry
            )
            self._key_expiry = expiry
        return self._key

    def issue(self, blob_name: str, now: datetime | None = None) -> IssuedSas:
        now = now or datetime.now(UTC)
        start, expiry = sas_window(now, self._ttl_minutes)
        token = generate_blob_sas(
            account_name=self._service.account_name,
            container_name=self._container,
            blob_name=blob_name,
            user_delegation_key=self._delegation_key(now),
            # create + write: Put Blob, Put Block e Put Block List. Sem read, list ou delete.
            permission=BlobSasPermissions(create=True, write=True),
            start=start,
            expiry=expiry,
            protocol="https",
        )
        blob_url = self._service.get_blob_client(self._container, blob_name).url
        return IssuedSas(upload_url=f"{blob_url}?{token}", blob_name=blob_name, expires_on=expiry)
