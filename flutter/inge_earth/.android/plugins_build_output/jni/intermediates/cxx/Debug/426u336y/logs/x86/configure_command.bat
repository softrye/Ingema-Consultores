@echo off
"C:\\Users\\PC-02\\AppData\\Local\\Android\\Sdk\\cmake\\3.22.1\\bin\\cmake.exe" ^
  "-HC:\\Users\\PC-02\\AppData\\Local\\Pub\\Cache\\hosted\\pub.dev\\jni-1.0.3\\src" ^
  "-DCMAKE_SYSTEM_NAME=Android" ^
  "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON" ^
  "-DCMAKE_SYSTEM_VERSION=21" ^
  "-DANDROID_PLATFORM=android-21" ^
  "-DANDROID_ABI=x86" ^
  "-DCMAKE_ANDROID_ARCH_ABI=x86" ^
  "-DANDROID_NDK=C:\\Users\\PC-02\\AppData\\Local\\Android\\Sdk\\ndk\\28.2.13676358" ^
  "-DCMAKE_ANDROID_NDK=C:\\Users\\PC-02\\AppData\\Local\\Android\\Sdk\\ndk\\28.2.13676358" ^
  "-DCMAKE_TOOLCHAIN_FILE=C:\\Users\\PC-02\\AppData\\Local\\Android\\Sdk\\ndk\\28.2.13676358\\build\\cmake\\android.toolchain.cmake" ^
  "-DCMAKE_MAKE_PROGRAM=C:\\Users\\PC-02\\AppData\\Local\\Android\\Sdk\\cmake\\3.22.1\\bin\\ninja.exe" ^
  "-DCMAKE_LIBRARY_OUTPUT_DIRECTORY=C:\\Users\\PC-02\\Documents\\InGePlus\\AppCalicatasDemo\\flutter\\inge_earth\\.android\\plugins_build_output\\jni\\intermediates\\cxx\\Debug\\426u336y\\obj\\x86" ^
  "-DCMAKE_RUNTIME_OUTPUT_DIRECTORY=C:\\Users\\PC-02\\Documents\\InGePlus\\AppCalicatasDemo\\flutter\\inge_earth\\.android\\plugins_build_output\\jni\\intermediates\\cxx\\Debug\\426u336y\\obj\\x86" ^
  "-DCMAKE_BUILD_TYPE=Debug" ^
  "-BC:\\Users\\PC-02\\AppData\\Local\\Pub\\Cache\\hosted\\pub.dev\\jni-1.0.3\\android\\.cxx\\Debug\\426u336y\\x86" ^
  -GNinja
