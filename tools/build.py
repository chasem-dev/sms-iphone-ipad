#!/usr/bin/env python3
import argparse
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description="Build the native Sunshine iPhone/iPad host.")
    parser.add_argument("platform", choices=("device", "simulator"))
    parser.add_argument("--team", default="", help="Apple team ID; omission produces unsigned output")
    parser.add_argument("--bundle-id", default="dev.chasem.sms-iphone-ipad")
    parser.add_argument("--configuration", choices=("Debug", "Release"), default="Release")
    parser.add_argument("--deployment-target", default="16.0")
    args = parser.parse_args()
    sdk = "iphoneos" if args.platform == "device" else "iphonesimulator"
    build = ROOT / "build" / args.platform
    subprocess.run([
        "cmake", "-S", str(ROOT), "-B", str(build), "-G", "Xcode",
        "-DCMAKE_SYSTEM_NAME=iOS", f"-DCMAKE_OSX_SYSROOT={sdk}",
        "-DCMAKE_OSX_ARCHITECTURES=arm64",
        f"-DCMAKE_OSX_DEPLOYMENT_TARGET={args.deployment_target}",
        f"-DSMS_DEVELOPMENT_TEAM={args.team}", f"-DSMS_BUNDLE_ID={args.bundle_id}",
        "-DBUILD_TESTING=OFF",
    ], check=True)
    command = ["cmake", "--build", str(build), "--config", args.configuration, "--target", "sms_ios"]
    if args.team:
        command += ["--", "-allowProvisioningUpdates"]
    subprocess.run(command, check=True)
    print(f"App: {build / (args.configuration + '-' + sdk) / 'Sunshine.app'}")


if __name__ == "__main__":
    main()
