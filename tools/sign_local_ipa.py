#!/usr/bin/env python3
"""Provision and sign a personal preloaded Sunshine IPA locally; never upload it."""

import argparse
import datetime
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

from package_ipa import package
from package_local_ipa import PRIVATE_DIRECTORY, digest


ROOT = Path(__file__).resolve().parents[1]
BUNDLE = "dev.chasem.sunshine.game"


def validate_archive(archive):
    seen = set()
    for entry in archive.infolist():
        path = PurePosixPath(entry.filename)
        if (path.is_absolute() or ".." in path.parts or "\\" in entry.filename
                or len(path.parts) < 2 or path.parts[:2] != ("Payload", "SunshineGame.app")
                or entry.filename in seen or path.as_posix() != entry.filename.rstrip("/")):
            raise ValueError("IPA must contain only one regular Payload/SunshineGame.app tree.")
        mode = entry.external_attr >> 16
        if stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR):
            raise ValueError("IPA contains a symlink or special file.")
        if any(part in ("Frameworks", "PlugIns", "Watch", "AppClips") for part in path.parts[2:]):
            raise ValueError("Nested executable bundles require a separate signing workflow.")
        seen.add(entry.filename)
    info = plistlib.loads(archive.read("Payload/SunshineGame.app/Info.plist"))
    if (info.get("CFBundleIdentifier") != BUNDLE or info.get("CFBundleExecutable") != "SunshineGame"
            or info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]
            or info.get("SMSLocalOnly") is not True
            or info.get("SMSLocalBundledDisc") != "LocalGame/disc.gcm"):
        raise ValueError("Expected a private preloaded iPhoneOS SunshineGame IPA.")
    archive.getinfo("Payload/SunshineGame.app/LocalGame/disc.gcm")
    archive.getinfo("Payload/SunshineGame.app/SunshineGame")
    return info


def validate_profile(profile, device, team=None):
    expiration = profile["ExpirationDate"].replace(tzinfo=datetime.timezone.utc)
    if expiration <= datetime.datetime.now(datetime.timezone.utc):
        raise ValueError("Provisioning profile has expired.")
    allowed = profile["Entitlements"]
    profile_team = profile["TeamIdentifier"][0]
    if team and profile_team != team:
        raise ValueError("Provisioning profile belongs to a different team.")
    prefixes = profile.get("ApplicationIdentifierPrefix", [])
    authorized = allowed.get("application-identifier", "")
    identifier = None
    for prefix in prefixes:
        candidate = prefix + "." + BUNDLE
        if authorized == candidate or (isinstance(authorized, str) and authorized.endswith("*")
                and authorized.count("*") == 1 and authorized.startswith(prefix + ".")
                and candidate.startswith(authorized[:-1])):
            identifier = candidate
            break
    if identifier is None:
        raise ValueError("Profile must authorize the Sunshine game bundle ID (explicitly or by matching wildcard).")
    if allowed.get("get-task-allow") is not True:
        raise ValueError("This helper supports development profiles only.")
    if device not in profile.get("ProvisionedDevices", []):
        raise ValueError("Device UDID is not registered in the provisioning profile.")
    if allowed.get("com.apple.developer.team-identifier") != profile_team:
        raise ValueError("Profile team entitlement is inconsistent.")
    return {"application-identifier": identifier, "get-task-allow": True,
            "com.apple.developer.team-identifier": profile_team}


def select_identity(profile, identities):
    available = set(re.findall(r"\b[0-9A-Fa-f]{40}\b", identities.upper()))
    for certificate in profile.get("DeveloperCertificates", []):
        identity = hashlib.sha1(certificate).hexdigest().upper()
        if identity in available:
            return identity
    raise ValueError("No matching valid signing certificate/private key in Keychain. "
                     "Sign in to Xcode Settings > Accounts and create an Apple Development certificate.")


def resolve_device(identifier, work):
    if re.fullmatch(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{16}|[0-9a-fA-F]{40}", identifier):
        return identifier.upper()
    details = work / "device.json"
    subprocess.run(["xcrun", "devicectl", "device", "info", "details", "--device", identifier,
                    "--json-output", str(details), "--timeout", "45"], check=True)
    return json.loads(details.read_text())["result"]["hardwareProperties"]["udid"]


def provision(team, device, work):
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("Team ID must contain 10 uppercase letters/digits.")
    build = work / "provision"
    subprocess.run(["cmake", "-S", str(ROOT), "-B", str(build), "-G", "Xcode",
                    "-DCMAKE_SYSTEM_NAME=iOS", "-DCMAKE_OSX_SYSROOT=iphoneos",
                    "-DCMAKE_OSX_ARCHITECTURES=arm64", "-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0",
                    f"-DSMS_DEVELOPMENT_TEAM={team}", f"-DSMS_BUNDLE_ID={BUNDLE}",
                    "-DBUILD_TESTING=OFF"], check=True)
    log = PRIVATE_DIRECTORY / "signing-provision.log"
    with log.open("w") as stream:
        result = subprocess.run(["xcodebuild", "-project", str(build / "SMSiOS.xcodeproj"),
                                 "-target", "sms_ios", "-configuration", "Release",
                                 "-destination", f"id={device}", "-allowProvisioningUpdates",
                                 "-allowProvisioningDeviceRegistration", "build"],
                                stdout=stream, stderr=subprocess.STDOUT)
    log.chmod(0o600)
    if result.returncode:
        raise ValueError(f"Xcode provisioning failed. Sign in under Xcode Settings > Accounts; see {log}")
    return build / "Release-iphoneos/Sunshine.app/embedded.mobileprovision"


def sign_local(ipa, output, device, team=None, profile_path=None):
    ipa, output = Path(ipa).resolve(strict=True), Path(output).resolve()
    private = PRIVATE_DIRECTORY.resolve()
    if (private not in ipa.parents or private not in output.parents or output.suffix != ".ipa"
            or output == ipa or output.with_suffix(".json") == ipa):
        raise ValueError("Input and distinct output must stay under build/local-private with .ipa output.")
    if profile_path and Path(profile_path).resolve() in (output, output.with_suffix(".json")):
        raise ValueError("Output must not overwrite the provisioning profile.")
    if not team and not profile_path:
        raise ValueError("Supply --team for Xcode provisioning or --profile for an existing profile.")
    with zipfile.ZipFile(ipa) as archive:
        validate_archive(archive)
    output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    output.parent.chmod(0o700)
    with tempfile.TemporaryDirectory(prefix="sign-private-", dir=output.parent) as temporary:
        work = Path(temporary)
        udid = resolve_device(device, work)
        selected = Path(profile_path).resolve(strict=True) if profile_path else provision(team, udid, work)
        profile = plistlib.loads(subprocess.check_output(["security", "cms", "-D", "-i", str(selected)]))
        entitlements = validate_profile(profile, udid, team)
        identity = select_identity(profile, subprocess.check_output(
            ["security", "find-identity", "-v", "-p", "codesigning"], text=True))
        with zipfile.ZipFile(ipa) as archive:
            archive.extractall(work)
        app = work / "Payload/SunshineGame.app"
        shutil.rmtree(app / "_CodeSignature", ignore_errors=True)
        (app / "CodeResources").unlink(missing_ok=True)
        shutil.copyfile(selected, app / "embedded.mobileprovision")
        (app / "SunshineGame").chmod(0o755)
        entitlement_file = work / "signing.entitlements"
        entitlement_file.write_bytes(plistlib.dumps(entitlements))
        subprocess.run(["codesign", "--force", "--sign", identity, "--timestamp=none",
                        "--generate-entitlement-der", "--entitlements", str(entitlement_file), str(app)], check=True)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        actual = plistlib.loads(subprocess.check_output(
            ["codesign", "-d", "--entitlements", ":-", str(app)], stderr=subprocess.DEVNULL))
        if actual != entitlements:
            raise ValueError("Signed entitlements do not match the validated profile.")
        package(app, output, require_signed=True, local_bundled_disc=True)
        with output.open("rb") as stream:
            checksum = digest(stream)
        receipt = {"localOnly": True, "signatureVerified": True, "installed": False,
                   "physicalDeviceGameplayVerified": False, "bundleIdentifier": BUNDLE,
                   "profileExpiration": profile["ExpirationDate"].isoformat(),
                   "ipa": str(output), "ipaSHA256": checksum}
        with tempfile.NamedTemporaryFile(mode="w", dir=output.parent, delete=False) as stream:
            receipt_path = Path(stream.name)
            json.dump(receipt, stream, indent=2)
            stream.write("\n")
        receipt_path.replace(output.with_suffix(".json"))
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", type=Path, default=PRIVATE_DIRECTORY / "Sunshine-personal-unsigned.ipa")
    parser.add_argument("--output", type=Path, default=PRIVATE_DIRECTORY / "Sunshine-personal-signed.ipa")
    parser.add_argument("--device", required=True, help="Registered hardware UDID or connected CoreDevice identifier")
    parser.add_argument("--team", help="Apple team ID for automatic Xcode provisioning")
    parser.add_argument("--profile", type=Path, help="Existing development profile authorizing this app and device")
    args = parser.parse_args()
    try:
        print(sign_local(args.ipa, args.output, args.device, args.team, args.profile))
        print("LOCAL ONLY. Signature verified; device installation and gameplay remain unverified.")
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Signing stopped: {error}\n")


if __name__ == "__main__":
    main()
