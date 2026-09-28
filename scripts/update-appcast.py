#!/usr/bin/env python3
import argparse
import base64
import binascii
import email.utils
import html
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


def existing_windows_item(path: Path) -> str:
    if not path.exists():
        return ""
    content = path.read_text(encoding="utf-8")
    match = re.search(
        r"    <item>\s*.*?sparkle:os=\"windows\".*?    </item>\r?\n?",
        content,
        flags=re.DOTALL,
    )
    return match.group(0) if match else ""


def main() -> None:
    parser = argparse.ArgumentParser(description="Write the Sparkle appcast for a VoiceStick release.")
    parser.add_argument("--version", required=True)
    parser.add_argument("--macos-url", "--zip-url", dest="macos_url", required=True)
    parser.add_argument("--signature", required=True)
    parser.add_argument("--length", required=True, type=int)
    parser.add_argument("--feed-url", default="https://78.github.io/voicestick/appcast.xml")
    parser.add_argument("--release-url")
    parser.add_argument("--macos-arch", choices=["arm64"])
    parser.add_argument("--msi-url")
    parser.add_argument("--msi-length", type=int)
    parser.add_argument("--output", default="website/public/appcast.xml")
    notes_group = parser.add_mutually_exclusive_group()
    notes_group.add_argument("--release-notes", default="VoiceStick macOS release.")
    notes_group.add_argument("--release-notes-file", type=Path, help="UTF-8 Markdown notes for Sparkle 2.9 and macOS 12+.")
    args = parser.parse_args()

    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version):
        sys.exit("Error: --version must have three numeric components.")
    if args.length <= 0:
        sys.exit("Error: --length must be greater than 0 for Sparkle updates.")
    if "REPLACE_WITH" in args.signature or not args.signature.strip():
        sys.exit("Error: --signature must be a real Sparkle EdDSA signature.")
    try:
        signature_bytes = base64.b64decode(args.signature, validate=True)
    except binascii.Error:
        sys.exit("Error: --signature must be valid base64.")
    if len(signature_bytes) != 64:
        sys.exit("Error: --signature must be a 64-byte EdDSA signature.")
    if args.msi_url and (not args.msi_length or args.msi_length <= 0):
        sys.exit("Error: --msi-length must be greater than 0 when --msi-url is set.")
    if not args.macos_url.startswith("https://") or not args.feed_url.startswith("https://"):
        sys.exit("Error: macOS archive and appcast URLs must use HTTPS.")
    if args.release_url and not args.release_url.startswith("https://"):
        sys.exit("Error: release URL must use HTTPS.")

    notes_source = args.release_notes
    if args.release_notes_file:
        try:
            notes_source = args.release_notes_file.read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            sys.exit("Error: --release-notes-file must be a readable UTF-8 file.")
        if not notes_source.strip():
            sys.exit("Error: --release-notes-file must not be empty.")

    notes = "".join(f"<li>{html.escape(line)}</li>" for line in notes_source.splitlines() if line.strip())
    if not notes:
        notes = "<li>VoiceStick macOS release.</li>"
    if args.release_url:
        notes += f'<li><a href="{html.escape(args.release_url, quote=True)}">查看完整更新说明</a></li>'

    if args.release_notes_file:
        markdown_notes = notes_source.strip().replace("]]>", "]]]]><![CDATA[>")
        macos_description = f'<description sparkle:format="markdown"><![CDATA[\n{markdown_notes}\n      ]]></description>'
    else:
        macos_description = f"""<description><![CDATA[
        <ul>
          {notes}
        </ul>
      ]]></description>"""
    full_release_notes_link = (
        f"      <sparkle:fullReleaseNotesLink>{html.escape(args.release_url)}</sparkle:fullReleaseNotesLink>\n"
        if args.release_url else ""
    )

    pub_date = email.utils.format_datetime(datetime.now(timezone.utc))
    output_path = Path(args.output)
    hardware_requirement = (
        "      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>\n"
        if args.macos_arch == "arm64" else ""
    )
    windows_item = ""
    if args.msi_url and args.msi_length:
        windows_item = f"""    <item>
      <title>Version {html.escape(args.version)}</title>
      <description><![CDATA[
        <ul>
          {notes}
        </ul>
      ]]></description>
      <pubDate>{pub_date}</pubDate>
      <enclosure
        url="{html.escape(args.msi_url)}"
        sparkle:os="windows"
        sparkle:version="{html.escape(args.version)}"
        sparkle:shortVersionString="{html.escape(args.version)}"
        sparkle:installerArguments="/passive"
        length="{args.msi_length}"
        type="application/octet-stream"
      />
    </item>
"""
    else:
        windows_item = existing_windows_item(output_path)

    content = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>VoiceStick</title>
    <link>{html.escape(args.feed_url)}</link>
    <description>VoiceStick app updates</description>
    <language>zh-CN</language>
{windows_item}    <item>
      <title>Version {html.escape(args.version)}</title>
      {macos_description}
{full_release_notes_link}      <pubDate>{pub_date}</pubDate>
{hardware_requirement}      <sparkle:minimumSystemVersion>12.0.0</sparkle:minimumSystemVersion>
      <enclosure
        url="{html.escape(args.macos_url, quote=True)}"
        sparkle:os="macos"
        sparkle:version="{html.escape(args.version)}"
        sparkle:shortVersionString="{html.escape(args.version)}"
        sparkle:edSignature="{html.escape(args.signature)}"
        length="{args.length}"
        type="application/octet-stream"
      />
    </item>
  </channel>
</rss>
"""
    output_path.write_text(content, encoding="utf-8")


if __name__ == "__main__":
    main()
