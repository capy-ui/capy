{ pkgs }:

with pkgs;

# Configure your development environment.
#
# Documentation: https://github.com/numtide/devshell
devshell.mkShell {
  name = "android-project";
  motd = ''
    Entered the Android app development environment.
  '';
  env = [
    {
      name = "ANDROID_HOME";
      value = "${android-sdk}/share/android-sdk";
    }
    {
      name = "ANDROID_SDK_ROOT";
      value = "${android-sdk}/share/android-sdk";
    }
    {
      name = "ANDROID_NDK_ROOT";
      value = "${android-sdk}/share/android-sdk/ndk";
    }
    {
      name = "JAVA_HOME";
      value = jdk11.home;
    }
  ];
  packages = [
    android-sdk
    gradle
    jdk11
    zig
  ];
}
