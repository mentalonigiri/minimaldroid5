#!/bin/env -S nim e --hints:off

import os
import strutils
import strformat

# calculate automatic app version
var auto_app_version = (CompileDate & CompileTime)
auto_app_version = auto_app_version.replace("-", "").replace(":", "")
auto_app_version = (auto_app_version.parseInt() div 2100000000).intToStr()

var app_version = getEnv("APP_VERSION", auto_app_version)

# override variables from environment instead of editing the code
const
    home = getHomeDir()
    android_home = getEnv("ANDROID_HOME", home / "Android/Sdk")
    debug_key_store = home / ".cache/androiddev-debug-keystore.ks"
    ndk_version = getEnv("ANDROID_NDK_VERSION", "26.2.11394342")
    build_for_archs = getEnv("BUILD_FOR_ARCHS", "x86_64,armeabi-v7a,arm64-v8a").split(",")
    buildtools_version = getEnv("ANDROID_BUILDTOOLS_VERSION", "34.0.0")
    android_legacy_platform = getEnv("ANDROID_LEGACY_PLATFORM", "21")
    android_target_platform = getEnv("ANDROID_TARGET_PLATFORM", "34")
    android_host_os = getEnv("ANDROID_HOST_OS", "linux-x86_64")
    key_store = getEnv("KEY_STORE", debug_key_store) # key store with "release" key
    ks_pass = getEnv("KS_PASS", "mypassword") # password for the key store
    key_pass = getEnv("KEY_PASS", "mypassword") # password for the key key (yes, it is)
    key_alias = getEnv("KEY_ALIAS", "debug")
    cmake_version = getEnv("ANDROID_CMAKE_VERSION", "3.22.1")
    ndk_root = android_home / "ndk" / ndk_version
    toolchain_path = ndk_root / "toolchains/llvm/prebuilt" / android_host_os / "bin"
    buildtools_path = android_home / "build-tools" / buildtools_version
    path = getEnv("PATH")
    needed_sdk_dirs = @[
        &"ndk/{ndk_version}",
        &"build-tools/{buildtools_version}",
        &"cmake/{cmake_version}",
        &"platform-tools",
        &"tools",
        &"platforms/android-{android_target_platform}"
    ]
    begindir = getCurrentDir()

# dir setup
cd(thisDir())

# env setup
putEnv("ANDROID_HOME", android_home)
putEnv("ANDROID_SDK_ROOT", android_home)
putEnv("ANDROID_NDK_ROOT", ndk_root)

# PATH setup
putEnv("PATH", &"{toolchain_path}:{buildtools_path}:{path}")

# determine if we need to install sdk components
var want_sdk = false
for component in needed_sdk_dirs:
    if not dirExists(android_home / component):
        want_sdk = true

const
    sdkmanager_license_command = fmt"""
        sdkmanager --sdk_root="{android_home}" --licenses"""
    sdkmanager_install_command = fmt"""
            sdkmanager --sdk_root="{android_home}"
            "build-tools;{buildtools_version}"
            "cmake;{cmake_version}"
            "ndk;{ndk_version}"
            "platform-tools"
            "platforms;android-{android_target_platform}"
            "tools"
        """
        .unindent()
        .replace("\n", " ")

proc installAndroidSdk() =
    mkDir(android_home)
    exec(sdkmanager_license_command, "y\r\n".repeat(42))
    exec(sdkmanager_install_command)
    exec(sdkmanager_license_command, "y\r\n".repeat(42))

# install sdk if needed
if want_sdk:
   installAndroidSdk()

# install bundletool
const bundletool_fpath = home / ".cache/bundletool.jar"

mkDir(home / ".cache")
if not fileExists(home / ".cache/bundletool.jar"):
    echo("downloading bundletool...")
    var (outp, exitCode) = system.gorgeEx(&"""curl -L -o {home / ".cache/bundletool0.jar"} --retry 50 --retry-delay 10 --retry-max-time 60 -C - 'https://github.com/google/bundletool/releases/download/1.15.6/bundletool-all-1.15.6.jar'""")
    if exitCode == 0:
        mvFile(home / ".cache/bundletool0.jar", bundletool_fpath)

for arch in build_for_archs:
    exec(&"xmake f --ndk_sdkver={android_legacy_platform} -y -p android -m release -a {arch}")
    exec("xmake build -y jni-main")
    mkDir(&"build/apk/lib/{arch}")
    for path in walkDirRec(&"build/android/{arch}"):
        if path.endsWith(".so"):
            let destPath = &"build/apk/lib/{arch}/{extractFilename(path)}"
            cpFile(path, destPath)
    var (libpath, exitCode) = gorgeEx(&"""xrepo env nim --hints:off --eval:'echo getEnv("LIBRARY_PATH")'""")
    var pathdirs = libpath.split(":")
    for pathdir in pathdirs:
        if dirExists(pathdir) and ("packages/" in pathdir):
            for path in walkDirRec(pathdir):
                if path.endsWith(".so"):
                    let destPath = &"build/apk/lib/{arch}/{extractFilename(path)}"
                    cpFile(path, destPath)

# exec(&"""aapt package -f -M AndroidManifest.xml -I {android_home}/platforms/android-{android_target_platform}/android.jar -S res -F apk-unaligned.apk build/apk""")

exec(&"""aapt2 compile --dir res -o build/res.zip""")
exec(fmt"""aapt2 link --version-name "{app_version}.0" --version-code {app_version} --min-sdk-version {android_legacy_platform} --target-sdk-version {android_target_platform} --proto-format -o build/aab-unaligned.apk -I "{android_home}/platforms/android-{android_target_platform}/android.jar"
    --manifest AndroidManifest.xml --java java build/res.zip --auto-add-overlay""".replace("\n", " "))
exec(fmt"""aapt2 link --version-name "{app_version}.0" --version-code {app_version} --min-sdk-version {android_legacy_platform} --target-sdk-version {android_target_platform} -o build/apk-unaligned.apk -I "{android_home}/platforms/android-{android_target_platform}/android.jar"
    --manifest AndroidManifest.xml --java java build/res.zip --auto-add-overlay""".replace("\n", " "))
exec(&"""javac -d build/obj -cp "{android_home}/platforms/android-{android_target_platform}/android.jar:java" -sourcepath java java/org/libsdl/app/*.java java/org/bakacorp/game/*.java""")

mkDir("build/dex")
exec(&"""d8 --release --min-api {android_legacy_platform} --lib "{android_home}/platforms/android-{android_target_platform}/android.jar" --output build/dex build/obj/**/**/**/*.class""")

exec("zip -r build/apk-unaligned.apk assets")

cd("build")

rmDir("lib")
mvDir("apk/lib", "lib")

cd("dex")
exec(&"""zip -r ../apk-unaligned.apk *""")
cd("..")

exec(&"""zip -r apk-unaligned.apk lib""")

exec(&"""jar xf aab-unaligned.apk resources.pb AndroidManifest.xml res""")
mkDir("manifest")
mvFile("AndroidManifest.xml", "manifest/AndroidManifest.xml")
# for path in walkDirRec("dex"):
#     if path.endsWith(".dex"):
#         let destPath = &"dex/{extractFilename(path)}"
#         cpFile(path, destPath)

exec("jar cMf base.zip manifest lib dex res ../assets resources.pb")


rmFile("../app.aab")
exec(&"""java -jar {bundletool_fpath} build-bundle --modules=base.zip --output=../app.aab""")

cd("..")

if (key_store == debug_key_store):
    if not fileExists(debug_key_store):
        exec(&"""keytool -genkey -v -keystore "{debug_key_store}" -alias {key_alias} -keyalg RSA -keysize 2048 -validity 10000 -storepass "{ks_pass}" -keypass "{key_pass}" -dname "CN=John Doe, OU=Mobile Development, O=My Company, L=New York, ST=NY, C=US" -noprompt""")

exec(&"""jarsigner -keystore {key_store} -storepass {ks_pass} -keypass {key_pass} app.aab {key_alias}""")

exec("zipalign -f 4 build/apk-unaligned.apk build/apk-unsigned.apk")

exec(&"""apksigner sign --ks {key_store} --ks-pass pass:{ks_pass} --key-pass pass:{key_pass} --out app.apk build/apk-unsigned.apk""")

rmFile("apk-unsigned.apk")
rmFile("apk-unaligned.apk")
rmFile("app.apk.idsig")
rmFile("debug.keystore")
rmDir("build")
rmDir(".xmake")

cd(begindir)
