# Build image for Notif APKs: the web build's Flutter base (frontend/Dockerfile)
# plus the NDK that Flutter 3.44.0 pins. Used by `notif-apk build`; see
# docs/operations/fdroid_runbook.md.
FROM ghcr.io/cirruslabs/flutter:3.44.0@sha256:46691e311715845de03a3ba4753a475476936805b29431b1f00f1816981033f8

RUN sdkmanager --install "ndk;28.2.13676358" \
  && flutter config --no-analytics --no-cli-animations

# The first release build fetched these (AGP 8.9 default build-tools, a
# plugin's compileSdk, and CMake for package:jni). Baked in so that each
# throwaway build container does not download them again.
RUN sdkmanager --install "build-tools;35.0.0" "platforms;android-35" "cmake;3.22.1"
