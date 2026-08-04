from types import SimpleNamespace

from apps.ocr.providers.rapidocr import RapidOCRProvider


class FakeEngine:
    def __call__(self, image_bytes):
        assert image_bytes == b"jpeg"
        return SimpleNamespace(
            boxes=[
                [[0, 0], [20, 0], [20, 10], [0, 10]],
                [[0, 12], [20, 12], [20, 22], [0, 22]],
            ],
            txts=["布洛芬缓释胶囊", "低置信度"],
            scores=[0.96, 0.30],
        )


def test_adapter_normalizes_and_filters_lines():
    provider = RapidOCRProvider(engine=FakeEngine(), minimum_score=0.50)
    document = provider.recognize(b"jpeg", role="front")
    assert document.role == "front"
    assert [line.text for line in document.lines] == ["布洛芬缓释胶囊"]
    assert document.lines[0].score == 0.96
