import subprocess
import datetime
import plistlib
import os
import filecmp
import shutil

def get_version():
    env_version = os.environ.get("MIHOMO_CORE_VERSION")
    if env_version:
        return env_version

    try:
        return subprocess.check_output(
            [go_bin, "list", "-m", "-f", "{{.Version}}", "github.com/metacubex/mihomo"],
            text=True,
        ).strip()
    except Exception:
        with open("./go.mod") as file:
            for line in file.readlines():
                if line.strip().startswith("require github.com/metacubex/mihomo "):
                    return line.split()[-1].strip()
    return "vernesong-smart"

go_bin = "go"

def build_clash(version,build_time,arch):
    command = f"""
{go_bin} build -trimpath -ldflags '-X "github.com/metacubex/mihomo/constant.Version={version}" \
-X "github.com/metacubex/mihomo/constant.BuildTime={build_time}"' \
-buildmode=c-archive -o goClash_{arch}.a """
    envs = os.environ.copy()
    envs.update({
        "GOOS":"darwin",
        "GOARCH":arch,
        "CGO_ENABLED":"1",
        "CGO_LDFLAGS":"-mmacosx-version-min=10.14",
        "CGO_CFLAGS":"-mmacosx-version-min=10.14",
    })    
    subprocess.check_output(command, shell=True,env=envs)

def mergeLibs():
    if not filecmp.cmp('goClash_amd64.h','goClash_arm64.h'):
        exit(-1)
    os.rename('goClash_amd64.h', 'goClash.h')
    command = "lipo *.a -create -output goClash.a"
    subprocess.check_output(command, shell=True)

def clean():
    cmd = "rm -f *amd* *arm*"
    subprocess.check_output(cmd, shell=True)


def write_to_info(version):
    path = "../Info.plist"

    with open(path, 'rb') as f:
        contents = plistlib.load(f)

    if not contents:
        exit(-1)

    contents["coreVersion"] = version
    with open(path, 'wb') as f:
        plistlib.dump(contents, f, sort_keys=False)


def run():
    if shutil.which(go_bin) is None:
        raise RuntimeError("go is required to build the embedded Vernesong mihomo core, but it was not found on PATH")
    version = get_version()
    print("current mihomo smart core version:", version)
    build_time = datetime.datetime.now().strftime("%Y-%m-%d-%H%M")
    print("clean existing")
    subprocess.check_output("rm -f *Clash*.h *.a", shell=True)
    print("create arm64")
    build_clash(version,build_time,"arm64")
    print("create amd64")
    build_clash(version,build_time,"amd64")
    print("merge")
    mergeLibs()
    print("clean")
    clean()
    if os.environ.get("CI", False) or os.environ.get("GITHUB_ACTIONS", False):
        print("writing info.plist")
        write_to_info(version)
    print("done")


if __name__ == "__main__":
    run()
