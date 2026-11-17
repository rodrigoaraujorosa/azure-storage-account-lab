"""Microserviço de SAS (Azure Functions, modelo v2 em Python).

POST /api/sas  {"fileName": "...", "size": 123, "contentType": "..."}
  -> 201 {"uploadUrl": "...", "blobName": "...", "expiresOn": "...", "maxBytes": ...}

Fica atrás do APIM, que injeta a function key no header `x-functions-key`.
O arquivo em si nunca passa por aqui nem pelo APIM: o navegador envia direto ao Storage.
"""

from __future__ import annotations

import json
import logging
import os
from datetime import UTC, datetime

import azure.functions as func

from sas_issuer import UploadSasIssuer
from sas_logic import MIB, ValidationError, build_blob_name, parse_upload_request

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

_MAX_BYTES = int(os.environ.get("MAX_UPLOAD_MB", "400")) * MIB
_issuer: UploadSasIssuer | None = None


def _get_issuer() -> UploadSasIssuer:
    global _issuer
    if _issuer is None:
        _issuer = UploadSasIssuer(
            account_url=os.environ["STORAGE_ACCOUNT_URL"],
            container=os.environ.get("UPLOAD_CONTAINER", "uploads"),
            ttl_minutes=int(os.environ.get("SAS_TTL_MINUTES", "15")),
        )
    return _issuer


def _json(body: dict, status: int) -> func.HttpResponse:
    return func.HttpResponse(
        json.dumps(body, ensure_ascii=False),
        status_code=status,
        mimetype="application/json",
        headers={"Cache-Control": "no-store"},
    )


@app.route(route="sas", methods=["POST"])
def create_upload_sas(req: func.HttpRequest) -> func.HttpResponse:
    try:
        payload = req.get_json()
    except ValueError:
        return _json({"error": "o corpo deve ser JSON"}, 400)

    try:
        upload = parse_upload_request(payload, _MAX_BYTES)
    except ValidationError as exc:
        return _json({"error": str(exc)}, 400)

    now = datetime.now(UTC)
    blob_name = build_blob_name(upload.file_name, now)
    try:
        issued = _get_issuer().issue(blob_name, now)
    except Exception:
        logging.exception("falha ao gerar a SAS para %s", blob_name)
        return _json({"error": "falha ao gerar a SAS"}, 500)

    # Nunca registre a URL com o token: ela dá acesso de escrita até expirar.
    logging.info("SAS emitida: blob=%s size=%d", blob_name, upload.size)
    return _json(
        {
            "uploadUrl": issued.upload_url,
            "blobName": issued.blob_name,
            "expiresOn": issued.expires_on.isoformat(),
            "maxBytes": _MAX_BYTES,
        },
        201,
    )
