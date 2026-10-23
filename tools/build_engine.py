#!/usr/bin/env python3
"""Build the pinned iOS engine in an isolated, reproducibly patched cache."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
SDL_VERSION = "2.32.10"
SDL_SHA256 = "5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165"
DEFAULT_MOLTENVK = ROOT / ".cache/MoltenVK.xcframework/ios-arm64_x86_64-simulator/libMoltenVK.a"
DEFAULT_DEVICE_MOLTENVK = ROOT / ".cache/MoltenVK.xcframework/ios-arm64/libMoltenVK.a"


def run(*command, cwd=None, capture=False):
    print("+", " ".join(map(str, command)), flush=True)
    result = subprocess.run(list(map(str, command)), cwd=cwd, check=True,
                            text=True, capture_output=capture)
    return result.stdout.strip() if capture else None


def digest(data):
    return hashlib.sha256(data).hexdigest()


def prepare_engine(reference, cache, lock, patches):
    if cache.resolve() == reference.resolve():
        raise SystemExit("The managed cache must not be the reference checkout")
    spec = importlib.util.spec_from_file_location("prepare_engine", ROOT / "tools/prepare_engine.py")
    verifier = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(verifier)
    verifier.prepare(reference, lock, managed=False)
    if not cache.exists():
        cache.parent.mkdir(parents=True, exist_ok=True)
        run("git", "clone", "--shared", "--no-checkout", reference, cache)
        run("git", "checkout", "--detach", lock["commit"], cwd=cache)
    if run("git", "rev-parse", "HEAD", cwd=cache, capture=True) != lock["commit"]:
        raise SystemExit("Managed engine HEAD differs from engine.lock.json")
    submodule_options = []
    for name in lock["submodules"]:
        gitdir = run("git", "rev-parse", "--absolute-git-dir", cwd=reference / name, capture=True)
        submodule_options.extend(["-c", f"submodule.{name}.url={gitdir}"])
    run("git", "-c", "protocol.file.allow=always", *submodule_options,
        "submodule", "update", "--init", "--recursive", cwd=cache)
    for name, commit in lock["submodules"].items():
        if run("git", "rev-parse", "HEAD", cwd=cache / name, capture=True) != commit:
            raise SystemExit(f"Managed submodule {name} differs from engine.lock.json")
        if run("git", "status", "--porcelain", "--untracked-files=no", cwd=cache / name, capture=True):
            raise SystemExit(f"Managed submodule {name} has unexpected edits")
    state_path = cache / ".ios-build-patches.json"
    diff = run("git", "diff", "--binary", "HEAD", cwd=cache, capture=True)
    state = json.loads(state_path.read_text()) if state_path.exists() else None
    if (diff and not state) or (state and digest(diff.encode()) != state["diff_sha256"]):
        raise SystemExit("Managed engine has unexpected edits; refusing to overwrite them")
    patch_texts = [path.read_text() for path in patches]
    if state and state["patches"] == patch_texts:
        return
    with tempfile.TemporaryDirectory(prefix="engine-patches-", dir=cache.parent) as temporary:
        previous = []
        for index, text in enumerate(state["patches"] if state else []):
            old_patch = Path(temporary) / f"{index}.patch"
            old_patch.write_text(text)
            previous.append(old_patch)
        if previous:
            run("git", "apply", "--reverse", *reversed(previous), cwd=cache)
        try:
            if patches:
                run("git", "apply", "--check", *patches, cwd=cache)
                run("git", "apply", *patches, cwd=cache)
        except subprocess.CalledProcessError:
            if previous:
                run("git", "apply", *previous, cwd=cache)
            raise
    diff = run("git", "diff", "--binary", "HEAD", cwd=cache, capture=True)
    state_path.write_text(json.dumps({"patches": patch_texts, "diff_sha256": digest(diff.encode())}))


def prepare_sdl(cache):
    archive = cache / "downloads" / f"SDL2-{SDL_VERSION}.tar.gz"
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        temporary = archive.with_suffix(".tmp")
        urllib.request.urlretrieve(f"https://www.libsdl.org/release/{archive.name}", temporary)
        temporary.replace(archive)
    if digest(archive.read_bytes()) != SDL_SHA256:
        raise SystemExit(f"SDL checksum mismatch: remove {archive} and retry")
    source = cache / f"SDL2-{SDL_VERSION}"
    if not source.exists():
        with tempfile.TemporaryDirectory(prefix="sdl-extract-", dir=cache) as temporary:
            run("cmake", "-E", "tar", "xzf", archive, cwd=temporary)
            (Path(temporary) / source.name).rename(source)
    return source


def build_host_plugin(llvm, source, build, platform="simulator"):
    plugin = build / "gameptr" / "libSmsGamePtr.dylib"
    plugin.parent.mkdir(parents=True, exist_ok=True)
    import shlex
    flags = shlex.split(run(llvm / "llvm-config", "--cxxflags", capture=True))
    sdk = run("xcrun", "--sdk", "macosx", "--show-sdk-path", capture=True)
    command = [llvm / "clang++", "--target=arm64-apple-macos", "-isysroot", sdk,
               "-shared", "-fPIC", "-O2", *flags, "-undefined", "dynamic_lookup",
               "-o", plugin, source / "tools/gameptr/GamePtrPass.cpp"]
    if platform == "device":
        command.append("-DSMS_IOS_DEVICE=1")
    stamp = plugin.with_suffix(".json")
    identity = digest((json.dumps(list(map(str, command))) +
                       (source / "tools/gameptr/GamePtrPass.cpp").read_text() +
                       run(llvm / "clang++", "--version", capture=True)).encode())
    if not plugin.exists() or not stamp.exists() or stamp.read_text() != identity:
        run(*command)
        stamp.write_text(identity)
    return plugin


def configure_command(args, source, sdl, plugin, sdk):
    triple = "arm64-apple-ios15.0"
    if getattr(args, "platform", "simulator") == "simulator":
        triple += "-simulator"
    return ["cmake", "-S", source, "-B", args.build_dir, "-G", "Ninja",
            "-DCMAKE_SYSTEM_NAME=iOS", "-DCMAKE_OSX_ARCHITECTURES=arm64",
            f"-DCMAKE_OSX_SYSROOT={sdk}", "-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0",
            f"-DCMAKE_C_COMPILER={args.llvm_bin / 'clang'}",
            f"-DCMAKE_CXX_COMPILER={args.llvm_bin / 'clang++'}",
            f"-DCMAKE_OBJC_COMPILER={args.llvm_bin / 'clang'}",
            f"-DCMAKE_OBJCXX_COMPILER={args.llvm_bin / 'clang++'}",
            "-DCMAKE_AR=/usr/bin/ar", "-DCMAKE_RANLIB=/usr/bin/ranlib",
            f"-DCMAKE_C_COMPILER_TARGET={triple}", f"-DCMAKE_CXX_COMPILER_TARGET={triple}",
            f"-DCMAKE_OBJC_COMPILER_TARGET={triple}", f"-DCMAKE_OBJCXX_COMPILER_TARGET={triple}",
            "-DCMAKE_BUILD_TYPE=RelWithDebInfo", "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
            f"-DSMS_IOS_OVERLAY={ROOT / 'cmake/engine-ios.cmake'}",
            f"-DSMS_IOS_SDL_SOURCE={sdl}", f"-DSMS_IOS_MOLTENVK={args.moltenvk}",
            f"-DSMS_IOS_GAMEPTR_PLUGIN={plugin}", f"-DSMS_IOS_GAME_MAIN={args.game_main}",
            f"-DSMS_IOS_INFO_PLIST={args.info_plist}", *args.cmake_arg]


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("simulator", "device"), default="simulator")
    parser.add_argument("--reference", type=Path, default=ROOT.parent / "sms-pc-port")
    parser.add_argument("--build-dir", type=Path, help="Default: build/engine-<platform>")
    parser.add_argument("--llvm-bin", type=Path, default=Path("/opt/homebrew/opt/llvm/bin"))
    parser.add_argument("--moltenvk", type=Path, help="MoltenVK archive (overrides SMS_IOS_MOLTENVK)")
    parser.add_argument("--game-main", type=Path, default=ROOT / "ios/GameMain.mm")
    parser.add_argument("--info-plist", type=Path, default=ROOT / "ios/GameInfo.plist.in")
    parser.add_argument("--patch", type=Path, action="append", default=[])
    parser.add_argument("--cmake-arg", action="append", default=[])
    parser.add_argument("--target", action="append", help="Default: sms; repeat to build libraries separately")
    parser.add_argument("--jobs", type=int, default=min(os.cpu_count() or 4, 8))
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--configure-only", action="store_true")
    args = parser.parse_args(argv)
    if args.build_dir is None:
        args.build_dir = ROOT / f"build/engine-{args.platform}"
    if args.moltenvk is None:
        default_moltenvk = DEFAULT_DEVICE_MOLTENVK if args.platform == "device" else DEFAULT_MOLTENVK
        args.moltenvk = Path(os.environ.get("SMS_IOS_MOLTENVK", str(default_moltenvk)))
    args.build_dir = args.build_dir.resolve()
    args.reference = args.reference.resolve()
    args.llvm_bin = args.llvm_bin.resolve()
    args.moltenvk = args.moltenvk.resolve()
    args.game_main = args.game_main.resolve()
    args.info_plist = args.info_plist.resolve()
    return args


def main():
    args = parse_args()
    patches = sorted((ROOT / "patches").glob("engine-*.patch")) + [path.resolve() for path in args.patch]
    source = ROOT / ".cache/engine"
    lock = json.loads((ROOT / "engine.lock.json").read_text())
    prepare_engine(args.reference, source, lock, patches)
    sdl = prepare_sdl(ROOT / ".cache")
    if args.prepare_only:
        return
    if not args.moltenvk.is_file():
        raise SystemExit(f"{args.platform.capitalize()} MoltenVK archive is missing: {args.moltenvk}")
    plugin = build_host_plugin(args.llvm_bin, source, args.build_dir, args.platform)
    sdk_name = "iphoneos" if args.platform == "device" else "iphonesimulator"
    sdk = run("xcrun", "--sdk", sdk_name, "--show-sdk-path", capture=True)
    run(*configure_command(args, source, sdl, plugin, sdk))
    if not args.configure_only:
        run("cmake", "--build", args.build_dir, "--target", *(args.target or ["sms"]), "--parallel", args.jobs)


if __name__ == "__main__":
    main()
