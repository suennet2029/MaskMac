from configparser import ConfigParser
from pathlib import Path
import plistlib
import shutil
import subprocess


ROOT = Path(__file__).resolve().parent
CONFIG_PATH = ROOT / "config.ini"
DIST_DIR = ROOT / "dist"


def read_app_config() -> tuple[ConfigParser, str]:
    config = ConfigParser()
    if not config.read(CONFIG_PATH, encoding="utf-8"):
        raise FileNotFoundError(f"缺少配置文件：{CONFIG_PATH}")
    if "app" not in config:
        raise ValueError(f"配置文件缺少 [app] 节：{CONFIG_PATH}")
    return config, config["app"].get("executable", "MaskMac")


def main() -> None:
    config, executable = read_app_config()
    app_config = config["app"]
    app_name = app_config.get("name", "MaskMac")
    app_path = DIST_DIR / f"{app_name}.app"
    zip_path = DIST_DIR / f"{app_name}-arm64.zip"

    print("[1/6] 编译 Swift release 版本")
    bin_dir = Path(subprocess.check_output(
        ["swift", "build", "-c", "release", "--show-bin-path", "--disable-sandbox"],
        cwd=ROOT,
        text=True,
    ).strip())
    subprocess.run(
        ["swift", "build", "-c", "release", "--disable-sandbox"],
        cwd=ROOT,
        check=True,
    )
    bin_path = bin_dir / executable
    if not bin_path.is_file():
        raise FileNotFoundError(f"找不到编译产物：{bin_path}")

    print("[2/6] 清理并准备 dist 目录")
    if not DIST_DIR.exists():
        DIST_DIR.mkdir()
    if app_path.exists():
        shutil.rmtree(app_path)
    if zip_path.exists():
        zip_path.unlink()
    macos_dir = app_path / "Contents" / "MacOS"
    resources_dir = app_path / "Contents" / "Resources"
    macos_dir.mkdir(parents=True)
    resources_dir.mkdir(parents=True)

    print("[3/6] 复制可执行文件和图标资源")
    shutil.copy2(bin_path, macos_dir / executable)
    (macos_dir / executable).chmod(0o755)
    for resource_name in ("maskmac-menu-icon.png", "AppIcon.icns"):
        resource_path = ROOT / "Resources" / resource_name
        if not resource_path.is_file():
            raise FileNotFoundError(f"缺少资源文件：{resource_path}")
        shutil.copy2(resource_path, resources_dir / resource_name)

    print("[4/6] 生成 Info.plist")
    version = app_config.get("version", "1.0.0")
    info = {
        "CFBundleDisplayName": app_name,
        "CFBundleExecutable": executable,
        "CFBundleIdentifier": app_config.get("bundle_identifier", "local.maskmac.app"),
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": app_name,
        "CFBundlePackageType": "APPL",
        "CFBundleIconFile": "AppIcon.icns",
        "CFBundleIconName": "AppIcon",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": version,
        "LSMinimumSystemVersion": app_config.get("minimum_macos", "13.0"),
        "LSUIElement": True,
    }
    with (app_path / "Contents" / "Info.plist").open("wb") as plist_file:
        plistlib.dump(info, plist_file, sort_keys=False)

    print("[5/6] 执行本地签名")
    subprocess.run(
        ["codesign", "--force", "--deep", "--sign", app_config.get("sign_identity", "-"), str(app_path)],
        check=True,
    )

    print("[6/6] 生成 arm64 压缩包")
    subprocess.run(
        ["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app_path), str(zip_path)],
        check=True,
    )
    print(f"\n已生成应用：{app_path.resolve()}")
    print(f"已生成压缩包：{zip_path.resolve()}")


if __name__ == "__main__":
    main()
