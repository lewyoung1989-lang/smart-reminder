from apps.ocr.providers.storage import S3ObjectStorage


class FakeBody:
    def read(self):
        return b"image-bytes"


class FakeClient:
    def __init__(self, label):
        self.label = label
        self.calls = []

    def generate_presigned_url(self, operation, *, Params, ExpiresIn):
        self.calls.append((operation, Params, ExpiresIn))
        return f"https://{self.label}.invalid/{Params['Bucket']}/{Params['Key']}"

    def get_object(self, *, Bucket, Key):
        self.calls.append(("get_object", Bucket, Key))
        return {"Body": FakeBody()}

    def delete_object(self, *, Bucket, Key):
        self.calls.append(("delete_object", Bucket, Key))

    def copy_object(self, *, Bucket, Key, CopySource):
        self.calls.append(("copy_object", Bucket, Key, CopySource))


def test_presign_uses_public_client_and_reads_use_internal_client(settings):
    settings.S3_BUCKET = "smart-reminder-private"
    public = FakeClient("files")
    internal = FakeClient("minio")
    storage = S3ObjectStorage(
        internal_client=internal,
        public_client=public,
    )

    signed = storage.presign_put(
        key="ocr/tmp/user/front.jpg",
        content_type="image/jpeg",
        expires_in=600,
    )
    download_url = storage.presign_get(
        key="medicine-photos/user/photo.jpg",
        expires_in=3600,
    )
    image = storage.get_bytes("ocr/tmp/user/front.jpg")
    storage.copy(
        source_key="ocr/tmp/user/front.jpg",
        destination_key="medicine-photos/user/photo.jpg",
    )
    storage.delete("ocr/tmp/user/front.jpg")

    assert signed["url"].startswith("https://files.invalid/")
    assert public.calls[0][0] == "put_object"
    assert download_url.startswith("https://files.invalid/")
    assert public.calls[1][0] == "get_object"
    assert image == b"image-bytes"
    assert [call[0] for call in internal.calls] == [
        "get_object",
        "copy_object",
        "delete_object",
    ]
