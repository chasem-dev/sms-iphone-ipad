#!/usr/bin/env python3
"""Create an unsigned, owner-private IPA with one locally supplied disc; never publish it."""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import zipfile

from package_ipa import package
from run_game_simulator import inspect_disc


ROOT = Path(__file__).resolve().parents[1]
PRIVATE_DIRECTORY = ROOT / "build/local-private"
DISC_MEMBER = "LocalGame/disc.gcm"


def digest(stream):
    checksum = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1 << 20), b""):
        checksum.update(chunk)
    return checksum.hexdigest()


def compile_icon(source, staged, temporary):
    catalog = Path(temporary) / "PrivateIcons.xcassets"
    iconset = catalog / "AppIcon.appiconset"
    iconset.mkdir(parents=True)
    subprocess.run(["swift", str(ROOT / "tools/render_app_icon.swift"), str(source), str(iconset)], check=True)
    images = []
    for idiom, points, scales in [("iphone", [20, 29, 40, 60], [2, 3]),
                                   ("ipad", [20, 29, 40, 76], [1, 2]),
                                   ("ipad", [83.5], [2]), ("ios-marketing", [1024], [1])]:
        for point in points:
            for scale in scales:
                images.append({"idiom": idiom, "size": f"{point}x{point}", "scale": f"{scale}x",
                               "filename": f"Icon-{int(point * scale)}.png"})
    (iconset / "Contents.json").write_text(json.dumps({"images": images, "info": {"version": 1, "author": "xcode"}}))
    partial = Path(temporary) / "IconInfo.plist"
    subprocess.run(["xcrun", "actool", "--app-icon", "AppIcon", "--platform", "iphoneos",
                    "--minimum-deployment-target", "15.0", "--target-device", "iphone",
                    "--target-device", "ipad", "--output-partial-info-plist", str(partial),
                    "--compile", str(staged), str(catalog)], check=True)
    with partial.open("rb") as stream:
        return plistlib.load(stream)


def package_local(app, disc, output, icon=None):
    app, disc, output = Path(app).resolve(), Path(disc).resolve(), Path(output).resolve()
    if PRIVATE_DIRECTORY.resolve() not in output.parents or output.suffix != ".ipa":
        raise ValueError(f"Private IPAs must stay under the ignored local directory: {PRIVATE_DIRECTORY}")
    if output == app or app in output.parents or disc in (output, output.with_suffix(".json")):
        raise ValueError("Output must not overwrite the app or disc.")
    if icon is not None:
        icon = Path(icon).resolve(strict=True)
        if not icon.is_file() or icon in (output, output.with_suffix(".json")):
            raise ValueError("Icon must be a separate source image file.")
    inspect_disc(disc)
    with (app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
        raise ValueError("A real iPhoneOS device build is required; simulator builds cannot become device IPAs.")
    if info.get("CFBundleExecutable") != "SunshineGame" or info.get("CFBundleIdentifier") != "dev.chasem.sunshine.game":
        raise ValueError("Use the native SunshineGame engine app, not the diagnostic host.")
    if info.get("SMSLocalOnly") or (app / "LocalGame").exists():
        raise ValueError("Start from a clean, asset-free engine app, not an existing local bundle.")
    output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    output.parent.chmod(0o700)
    with disc.open("rb") as stream:
        disc_hash = digest(stream)
    with tempfile.TemporaryDirectory(prefix="private-ipa-", dir=output.parent) as temporary:
        staged = Path(temporary) / app.name
        shutil.copytree(app, staged, symlinks=True)
        shutil.rmtree(staged / "_CodeSignature", ignore_errors=True)
        (staged / "embedded.mobileprovision").unlink(missing_ok=True)
        (staged / "CodeResources").unlink(missing_ok=True)
        info["SMSLocalOnly"] = True
        info["SMSLocalBundledDisc"] = DISC_MEMBER
        if icon is not None:
            info.update(compile_icon(icon, staged, temporary))
        with (staged / "Info.plist").open("wb") as stream:
            plistlib.dump(info, stream)
        bundled = staged / DISC_MEMBER
        bundled.parent.mkdir(mode=0o700)
        shutil.copyfile(disc, bundled)
        package(staged, output, local_bundled_disc=True)
    member = f"Payload/{app.name}/{DISC_MEMBER}"
    with zipfile.ZipFile(output) as archive:
        with archive.open(member) as stream:
            embedded_hash = digest(stream)
        if embedded_hash != disc_hash:
            output.unlink()
            raise ValueError("Embedded disc differs from the selected local image; IPA removed.")
        with archive.open(f"Payload/{app.name}/Info.plist") as stream:
            packaged_info = plistlib.load(stream)
        if packaged_info.get("SMSLocalBundledDisc") != DISC_MEMBER or packaged_info.get("SMSLocalOnly") is not True:
            output.unlink()
            raise ValueError("Local bundle metadata verification failed; IPA removed.")
        if icon is not None:
            for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
                primary = packaged_info.get(key, {}).get("CFBundlePrimaryIcon", {})
                if primary.get("CFBundleIconName") != "AppIcon" or not primary.get("CFBundleIconFiles"):
                    raise ValueError("App icon metadata verification failed.")
            if f"Payload/{app.name}/Assets.car" not in archive.namelist():
                raise ValueError("Compiled app icon catalog is missing.")
    with output.open("rb") as stream:
        ipa_hash = digest(stream)
    report = {"localOnly": True, "platform": "iPhoneOS", "signing": "unsigned; sign and provision before installation",
              "gameplayOnPhysicalDeviceVerified": False, "launcher": "Ready to Play; no image selection needed",
              "ipa": str(output), "ipaBytes": output.stat().st_size, "ipaSHA256": ipa_hash,
              "embeddedDisc": member, "discBytes": disc.stat().st_size, "discSHA256": disc_hash,
              "embeddedDiscSHA256": embedded_hash}
    if icon is not None:
        with icon.open("rb") as stream:
            report["appIcon"] = {"source": str(icon), "sourceSHA256": digest(stream),
                                 "name": "AppIcon", "devices": ["iphone", "ipad"]}
    report_path = output.with_suffix(".json")
    with tempfile.NamedTemporaryFile(mode="w", dir=output.parent, suffix=".json", delete=False) as stream:
        temporary_report = Path(stream.name)
        json.dump(report, stream, indent=2)
        stream.write("\n")
    temporary_report.replace(report_path)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=ROOT / "build/engine-device/SunshineGame.app")
    parser.add_argument("--disc", type=Path, required=True)
    parser.add_argument("--icon", type=Path, help="Local artwork compiled as opaque iPhone/iPad Home Screen icons")
    parser.add_argument("--output", type=Path, default=PRIVATE_DIRECTORY / "Sunshine-personal-unsigned.ipa")
    args = parser.parse_args()
    print(package_local(args.app, args.disc, args.output, args.icon))
    print("LOCAL ONLY — includes your disc. Do not upload, share, attach to releases, or distribute.")
    print("Unsigned device IPA: signing/provisioning and physical-device gameplay are not verified.")


if __name__ == "__main__":
    main()
