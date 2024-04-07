add_requires("blake3", {configs = {shared = true}})
add_requires("libsdl", {configs = {shared = true}})
add_requires("libsdl_image")

add_rules("mode.release", "mode.debug")

target("glue")
set_kind("static")
add_includedirs("$(env ANDROID_NDK_ROOT)/sources/android/native_app_glue", {public = true})
add_files("$(env ANDROID_NDK_ROOT)/sources/android/native_app_glue/android_native_app_glue.c")

target("jni-main")
set_default(true)
add_files("main.cpp")
add_packages("libsdl")
add_packages("libsdl_image")
if is_plat("android") then
  set_kind("shared")
--   add_deps("glue")

  add_syslinks("android",
    "EGL",
    "GLESv1_CM",
    "log")
  add_shflags("-u ANativeActivity_onCreate")
end
