import base64
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "update-appcast.py"
SIGNATURE = base64.b64encode(bytes(64)).decode("ascii")


class UpdateAppcastTests(unittest.TestCase):
    def run_generator(self, directory: Path, *extra_args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--version", "0.3.6",
                "--macos-url", "https://github.com/One-SuperMark/voicestick/releases/download/v0.3.6/VoiceStick-0.3.6.dmg",
                "--signature", SIGNATURE,
                "--length", "1234",
                "--output", str(directory / "appcast.xml"),
                *extra_args,
            ],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_fork_dmg_feed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            result = self.run_generator(
                directory,
                "--feed-url", "https://github.com/One-SuperMark/voicestick/releases/latest/download/appcast.xml",
                "--release-url", "https://github.com/One-SuperMark/voicestick/releases/tag/v0.3.6",
                "--macos-arch", "arm64",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            root = ET.parse(directory / "appcast.xml").getroot()
            channel = root.find("channel")
            self.assertIsNotNone(channel)
            self.assertEqual(
                channel.findtext("link"),
                "https://github.com/One-SuperMark/voicestick/releases/latest/download/appcast.xml",
            )
            item = channel.find("item")
            self.assertIsNotNone(item)
            enclosure = item.find("enclosure")
            self.assertEqual(enclosure.attrib["url"], "https://github.com/One-SuperMark/voicestick/releases/download/v0.3.6/VoiceStick-0.3.6.dmg")
            self.assertEqual(enclosure.attrib["length"], "1234")
            self.assertEqual(enclosure.attrib["{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"], SIGNATURE)
            self.assertIn("查看完整更新说明", item.findtext("description"))
            self.assertEqual(
                item.findtext("{http://www.andymatuschak.org/xml-namespaces/sparkle}hardwareRequirements"),
                "arm64",
            )

    def test_invalid_version_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            result = self.run_generator(Path(temporary_directory), "--version", "0.3.6.1")
            self.assertNotEqual(result.returncode, 0)

    def test_invalid_signature_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            result = self.run_generator(Path(temporary_directory), "--signature", "not-a-signature")
            self.assertNotEqual(result.returncode, 0)

    def test_legacy_zip_url_option_remains_available(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            result = self.run_generator(
                directory,
                "--zip-url", "https://github.com/78/voicestick/releases/download/v0.3.6/VoiceStick-0.3.6.zip",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            enclosure = ET.parse(directory / "appcast.xml").getroot().find("channel/item/enclosure")
            self.assertTrue(enclosure.attrib["url"].endswith("VoiceStick-0.3.6.zip"))

    def test_http_archive_url_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            result = self.run_generator(Path(temporary_directory), "--macos-url", "http://example.com/update.dmg")
            self.assertNotEqual(result.returncode, 0)

    def test_markdown_notes_are_embedded_without_content_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            notes = "## 更新内容\n\n- 检查更新 & 安装前校验 <签名>。\n- [查看公告](https://example.com/notes)\n- 保留特殊文本 ]]>。"
            notes_file = directory / "release-notes.md"
            notes_file.write_text(notes, encoding="utf-8")
            result = self.run_generator(
                directory,
                "--release-notes-file", str(notes_file),
                "--release-url", "https://github.com/One-SuperMark/voicestick/releases/tag/v0.3.6",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            item = ET.parse(directory / "appcast.xml").getroot().find("channel/item")
            description = item.find("description")
            self.assertEqual(description.attrib["{http://www.andymatuschak.org/xml-namespaces/sparkle}format"], "markdown")
            self.assertEqual(description.text.strip(), notes)
            self.assertEqual(
                item.findtext("{http://www.andymatuschak.org/xml-namespaces/sparkle}fullReleaseNotesLink"),
                "https://github.com/One-SuperMark/voicestick/releases/tag/v0.3.6",
            )

    def test_empty_markdown_notes_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            notes_file = directory / "release-notes.md"
            notes_file.write_text(" \n\t", encoding="utf-8")
            result = self.run_generator(directory, "--release-notes-file", str(notes_file))
            self.assertNotEqual(result.returncode, 0)

    def test_missing_markdown_notes_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            result = self.run_generator(directory, "--release-notes-file", str(directory / "missing.md"))
            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
