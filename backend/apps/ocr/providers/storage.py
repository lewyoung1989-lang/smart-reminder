from typing import Protocol

import boto3
from botocore.config import Config
from django.conf import settings


class ObjectStorage(Protocol):
    def presign_put(
        self,
        *,
        key: str,
        content_type: str,
        expires_in: int,
    ) -> dict[str, object]: ...

    def get_bytes(self, key: str) -> bytes: ...

    def delete(self, key: str) -> None: ...


def _build_client(endpoint_url):
    return boto3.client(
        "s3",
        endpoint_url=endpoint_url,
        region_name=settings.S3_REGION,
        aws_access_key_id=settings.S3_ACCESS_KEY_ID or None,
        aws_secret_access_key=settings.S3_SECRET_ACCESS_KEY or None,
        config=Config(
            signature_version="s3v4",
            s3={"addressing_style": settings.S3_ADDRESSING_STYLE},
        ),
    )


class S3ObjectStorage:
    def __init__(self, *, internal_client=None, public_client=None):
        self._bucket = settings.S3_BUCKET
        self._internal_client = internal_client or _build_client(
            settings.S3_INTERNAL_ENDPOINT
        )
        self._public_client = public_client or _build_client(
            settings.S3_PUBLIC_ENDPOINT
        )

    def presign_put(self, *, key, content_type, expires_in):
        url = self._public_client.generate_presigned_url(
            "put_object",
            Params={
                "Bucket": self._bucket,
                "Key": key,
                "ContentType": content_type,
            },
            ExpiresIn=expires_in,
        )
        return {
            "url": url,
            "headers": {"Content-Type": content_type},
        }

    def get_bytes(self, key):
        response = self._internal_client.get_object(
            Bucket=self._bucket,
            Key=key,
        )
        return response["Body"].read()

    def delete(self, key):
        self._internal_client.delete_object(Bucket=self._bucket, Key=key)


def get_object_storage():
    if settings.OCR_STORAGE_PROVIDER in {"s3", "oss", "cos"}:
        return S3ObjectStorage()
    raise ValueError(
        f"Unsupported OCR storage provider: {settings.OCR_STORAGE_PROVIDER}"
    )
