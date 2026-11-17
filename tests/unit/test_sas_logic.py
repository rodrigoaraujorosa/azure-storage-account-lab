from datetime import UTC, datetime, timedelta

import pytest

from sas_logic import (
    DEFAULT_CONTENT_TYPE,
    MIB,
    ValidationError,
    build_blob_name,
    parse_upload_request,
    sanitize_file_name,
    sas_window,
)

MAX = 400 * MIB
NOW = datetime(2026, 11, 16, 12, 0, tzinfo=UTC)


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("video.mp4", "video.mp4"),
        ("C:\\Users\\x\\relatório final.pdf", "relat-rio-final.pdf"),
        ("../../etc/passwd", "passwd"),
        ("  .oculto  ", "oculto"),
        ("a b&c.zip", "a-b-c.zip"),
    ],
)
def test_sanitize_file_name(raw, expected):
    assert sanitize_file_name(raw) == expected


def test_sanitize_file_name_rejects_empty_result():
    with pytest.raises(ValidationError):
        sanitize_file_name("///")


def test_sanitize_file_name_truncates_keeping_extension():
    name = sanitize_file_name("a" * 300 + ".bin", max_length=50)
    assert len(name) == 50
    assert name.endswith(".bin")


def test_parse_valid_request():
    req = parse_upload_request(
        {"fileName": "big.bin", "size": 200 * MIB, "contentType": "video/mp4"}, MAX
    )
    assert (req.file_name, req.size, req.content_type) == ("big.bin", 200 * MIB, "video/mp4")


def test_parse_defaults_content_type():
    req = parse_upload_request({"fileName": "x.bin", "size": 1}, MAX)
    assert req.content_type == DEFAULT_CONTENT_TYPE


def test_parse_accepts_exact_limit():
    assert parse_upload_request({"fileName": "x", "size": MAX}, MAX).size == MAX


@pytest.mark.parametrize(
    "payload",
    [
        None,
        [],
        {},
        {"fileName": "", "size": 1},
        {"fileName": "x", "size": 0},
        {"fileName": "x", "size": -1},
        {"fileName": "x", "size": "10"},
        {"fileName": "x", "size": True},
        {"fileName": "x", "size": MAX + 1},
        {"fileName": "x", "size": 1, "contentType": "não é mime"},
    ],
)
def test_parse_rejects_invalid(payload):
    with pytest.raises(ValidationError):
        parse_upload_request(payload, MAX)


def test_build_blob_name_is_dated_and_unique():
    assert build_blob_name("f.bin", NOW, "abc") == "2026/11/16/abc-f.bin"
    assert build_blob_name("f.bin", NOW) != build_blob_name("f.bin", NOW)


def test_sas_window():
    start, expiry = sas_window(NOW, 15)
    assert start == NOW - timedelta(minutes=5)
    assert expiry == NOW + timedelta(minutes=15)


def test_sas_window_rejects_non_positive_ttl():
    with pytest.raises(ValueError):
        sas_window(NOW, 0)
