"""Regras puras do serviço de SAS: validação do pedido, nome do blob e janela de validade.

Sem dependência do SDK do Azure, para ser testado isoladamente.
"""

from __future__ import annotations

import re
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta

MIB = 1024 * 1024
DEFAULT_CONTENT_TYPE = "application/octet-stream"

_UNSAFE_CHARS = re.compile(r"[^A-Za-z0-9._-]+")
_CONTENT_TYPE = re.compile(r"^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+$")


class ValidationError(ValueError):
    """Pedido de upload inválido (vira HTTP 400)."""


@dataclass(frozen=True)
class UploadRequest:
    file_name: str
    size: int
    content_type: str


def sanitize_file_name(name: str, max_length: int = 100) -> str:
    """Mantém só o nome do arquivo, com caracteres seguros para o nome do blob."""
    base = name.replace("\\", "/").rsplit("/", 1)[-1].strip()
    safe = _UNSAFE_CHARS.sub("-", base).strip(".-")
    if not safe:
        raise ValidationError("fileName inválido")
    if len(safe) > max_length:
        stem, dot, ext = safe.rpartition(".")
        if dot and stem and len(ext) <= 10:
            safe = f"{stem[: max_length - len(ext) - 1]}.{ext}"
        else:
            safe = safe[:max_length]
    return safe


def parse_upload_request(payload: object, max_bytes: int) -> UploadRequest:
    """Valida o corpo `{fileName, size, contentType}` enviado pelo frontend."""
    if not isinstance(payload, dict):
        raise ValidationError("o corpo deve ser um objeto JSON")

    file_name = payload.get("fileName")
    if not isinstance(file_name, str) or not file_name.strip():
        raise ValidationError("fileName é obrigatório")

    size = payload.get("size")
    if isinstance(size, bool) or not isinstance(size, int) or size <= 0:
        raise ValidationError("size deve ser um inteiro positivo, em bytes")
    if size > max_bytes:
        raise ValidationError(f"arquivo maior que o limite de {max_bytes // MIB} MiB")

    content_type = payload.get("contentType") or DEFAULT_CONTENT_TYPE
    if not isinstance(content_type, str) or not _CONTENT_TYPE.match(content_type):
        raise ValidationError("contentType inválido")

    return UploadRequest(sanitize_file_name(file_name), size, content_type)


def build_blob_name(file_name: str, now: datetime, unique_id: str | None = None) -> str:
    """`AAAA/MM/DD/<uuid>-<arquivo>`: único, então a SAS nunca sobrescreve outro upload."""
    unique_id = unique_id or uuid.uuid4().hex
    return f"{now:%Y/%m/%d}/{unique_id}-{file_name}"


def sas_window(
    now: datetime, ttl_minutes: int, clock_skew_minutes: int = 5
) -> tuple[datetime, datetime]:
    """Início um pouco no passado (tolerância de relógio) e expiração curta."""
    if ttl_minutes <= 0:
        raise ValueError("ttl_minutes deve ser positivo")
    return now - timedelta(minutes=clock_skew_minutes), now + timedelta(minutes=ttl_minutes)
