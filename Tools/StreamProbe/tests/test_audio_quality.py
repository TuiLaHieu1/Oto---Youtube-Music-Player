"""Kiểm tra chọn chất lượng và tái sử dụng Python bằng dữ liệu giả, không gọi mạng."""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'Vendor/app_packages'))
sys.path.insert(0, str(ROOT / 'Tools/StreamProbe/python'))
import oto_resolve


class AudioQualityTests(unittest.TestCase):
    def setUp(self):
        oto_resolve._POOL.clear()

    def tearDown(self):
        oto_resolve._POOL.clear()

    def select(self, low_bandwidth, formats):
        client = oto_resolve._borrow(None, 'fast', low_bandwidth)
        selected = list(client.format_selector({'formats': formats, 'incomplete_formats': False}))
        return selected[0]['format_id']

    def test_quality_selects_audio_without_video(self):
        formats = [
            {'format_id': 'low', 'ext': 'm4a', 'acodec': 'mp4a.40.2', 'vcodec': 'none', 'abr': 48},
            {'format_id': 'high', 'ext': 'm4a', 'acodec': 'mp4a.40.2', 'vcodec': 'none', 'abr': 128},
            {'format_id': 'video', 'ext': 'mp4', 'acodec': 'mp4a.40.2', 'vcodec': 'avc1', 'abr': 192},
        ]
        self.assertEqual(self.select(True, formats), 'low')
        self.assertEqual(self.select(False, formats), 'high')

    def test_single_audio_format_remains_playable(self):
        formats = [{'format_id': 'only', 'ext': 'm4a', 'acodec': 'mp4a.40.2', 'vcodec': 'none', 'abr': 128}]
        self.assertEqual(self.select(True, formats), 'only')

    def test_aac_fallback(self):
        formats = [{'format_id': 'aac', 'ext': 'mp4', 'acodec': 'mp4a.40.2', 'vcodec': 'none', 'abr': 64}]
        self.assertEqual(self.select(True, formats), 'aac')

    def test_warm_client_is_reused_and_quality_pools_are_separate(self):
        oto_resolve.warm()
        warmed = oto_resolve._POOL[0][0]
        normal = oto_resolve._borrow(None, 'fast')
        self.assertIs(normal, warmed)
        oto_resolve._give_back(normal, None, 'fast')
        economy = oto_resolve._borrow(None, 'fast', True)
        self.assertIsNot(economy, normal)
        oto_resolve._give_back(economy, None, 'fast', True)
        self.assertIs(oto_resolve._borrow(None, 'fast', True), economy)
        self.assertIs(oto_resolve._borrow(None, 'fast'), normal)


if __name__ == '__main__':
    unittest.main()
