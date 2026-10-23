#!/usr/bin/env python3
import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import zipfile


FORBIDDEN_SUFFIXES = {".iso", ".gcm", ".ciso", ".rvz", ".wia", ".wbfs", ".dol"}


def package(app, output, require_signed=False, *, local_bundled_disc=False):
    app = Path(app).resolve()
    output = Path(output).resolve()
    if not app.is_dir() or app.suffix != ".app":
        raise ValueError("Input must be an existing .app bundle.")
    with (app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
        raise ValueError("Only an iPhoneOS device build can be packaged, not a simulator/macOS app.")
    executable = info.get("CFBundleExecutable", "")
    if not executable or Path(executable).name != executable or not (app / executable).is_file():
        raise ValueError("The app bundle is missing its executable.")
    if info.get("SMSLocalOnly") and not local_bundled_disc:
        raise ValueError("Local-only bundles cannot use the distribution packager.")
    if local_bundled_disc and (info.get("SMSLocalOnly") is not True
            or info.get("SMSLocalBundledDisc") != "LocalGame/disc.gcm"
            or not (app / "LocalGame/disc.gcm").is_file()):
        raise ValueError("Local packaging requires the explicit local-only bundled-disc marker and image.")
    files = sorted(app.rglob("*"))
    for file in files:
        allowed_local_disc = local_bundled_disc and file.relative_to(app).as_posix() == "LocalGame/disc.gcm"
        if file.suffix.lower() in FORBIDDEN_SUFFIXES and not allowed_local_disc:
            raise ValueError(f"Refusing to distribute game assets: {file.relative_to(app)}")
        if file.is_symlink():
            raise ValueError("Symlinks are not supported by this initial IPA packager.")
    if output == app or app in output.parents:
        raise ValueError("Output must be outside the app bundle.")
    if require_signed:
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        signature = subprocess.run(["codesign", "-dv", str(app)], check=True, capture_output=True, text=True)
        if "Signature=adhoc" in signature.stderr or not (app / "embedded.mobileprovision").is_file():
            raise ValueError("Installable output requires a provisioning profile and a non-ad-hoc signature.")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=output.parent, suffix=".ipa", delete=False) as stream:
            temporary = Path(stream.name)
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for file in files:
                if not file.is_file():
                    continue
                archive_name = Path("Payload") / app.name / file.relative_to(app)
                archive.write(file, archive_name.as_posix())
        os.chmod(temporary, 0o600 if local_bundled_disc else 0o644)
        temporary.replace(output)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return output


def main():
    parser = argparse.ArgumentParser(description="Package a device app without bundling game images.")
    parser.add_argument("app", type=Path)
    parser.add_argument("--output", type=Path, default=Path("build/Sunshine-unsigned.ipa"))
    parser.add_argument("--require-signed", action="store_true")
    args = parser.parse_args()
    print(package(args.app, args.output, args.require_signed))
    if not args.require_signed:
        print("Signing not verified. An unsigned IPA must be signed and provisioned before device installation.")


if __name__ == "__main__":
    main()
