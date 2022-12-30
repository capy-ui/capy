# Android Apps in Zig

![Project banner](design/logo.png)

This repository contains a example on how to create a minimal Android app in Zig.

## State of the project

This project contains a really small app skeleton in `example/main.zig` which initializes OpenGL and renders a color cycle. Touchscreen events will be displayed as small circles beneath the fingers that will fade as soon as no event for the same finger will happen again.

The code contains some commented examples on how to interface with the JNI to use advanced features of the `ANativeActivity`.

It has no dependencies to C code except for the android libraries, so it can be considered a pure Zig app.

We're running a CI that will verify the build for Windows, macOS and Linux:

[![CI](https://github.com/MasterQ32/ZigAndroidTemplate/actions/workflows/main-ci.yml/badge.svg)](https://github.com/MasterQ32/ZigAndroidTemplate/actions/workflows/main-ci.yml)

## Presentation

There is a [FOSDEM Talk](https://fosdem.org/2021/schedule/event/zig_android/) you can watch here:

- [MP4 Video](https://video.fosdem.org/2021/D.zig/zig_android.mp4)
- [WebM Video](https://video.fosdem.org/2021/D.zig/zig_android.webm)

## What's missing

- Configuration management example
- Save/load app state example

## Requirements & Build

You need the [Android SDK](https://developer.android.com/studio#command-tools) installed together with the [Android NDK](https://developer.android.com/ndk).

You also need [adb](https://developer.android.com/studio/command-line/adb) and a Java SDK installed (required for `jarsigner`).

Now you need to generate yourself a keystore to sign your apps. For debugging purposes, the build script contains a helper. Just invoke `zig build keystore` to generate yourself a debug keystore that can be used with later build invocations.

**Note** that the build file might ask you to configure some paths. Do as requested and just run the build again, it should work then.

If all of the above is done, you should be able to build the app by running `zig build`.

There are convenience options with `zig build push` (installs the app on a connected phone) and `zig build run` (which installs, then runs the app).

### Quick Start

Install the [`sdkmanager`](https://developer.android.com/studio/command-line/sdkmanager) and invoke the following command line:

```
# Android Platforms for your target Android version
# Min version: Android 5
sdkmanager --install "platforms;android-21"
# you can install other versions as well
# remember to set it like `zig build -Dandroid=android99`

sdkmanager --install "build-tools;33.0.1"
sdkmanager --install "ndk;25.1.8937393"
zig build keystore install run
```

This should build an APK and install it on your connected phone if possible.

## Getting started

Check out the [`build.zig`](build.zig) to see how to build a new android app, and [`example/main.zig`](example/main.zig) to see how to create a basic application. All of this is still very rough, though.

## Credits

Huge thanks to [@cnlohr](https://github.com/cnlohr) to create [rawdrawandroid](https://github.com/cnlohr/rawdrawandroid) and making this project possible!
