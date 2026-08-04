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


class S3ObjectStorage:
    def __init__(self):
        self._bucket = settings.S3_BUCKET
        self._client = boto3.client(
            "s3",
            endpoint_url=settings.S3_ENDPOINT,
            region_name=settings.S3_REGION,
            aws_access_key_id=settings.S3_ACCESS_KEY_ID or None,
            aws_secret_access_key=settings.S3_SECRET_ACCESS_KEY or None,
            config=Config(
                s3={"addressing_style": settings.S3_ADDRESSING_STYLE}
            ),
        )

    def presign_put(self, *, key, content_type, expires_in):
        url = self._client.generate_presigned_url(
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
        response = self._client.get_object(Bucket=self._bucket, Key=key)
        return response["Body"].read()

    def delete(self, key):
        self._client.delete_object(Bucket=self._bucket, Key=key)


def get_object_storage():
    if settings.OCR_STORAGE_PROVIDER in {"s3", "oss", "cos"}:
        return S3ObjectStorage()
    raise ValueError(
        f"Unsupported OCR storage provider: {settings.OCR_STORAGE_PROVIDER}"
    )
