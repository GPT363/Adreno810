#!/bin/bash -e

# Цвета для логов
green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'

# Зависимости и пути
deps="git meson ninja patchelf unzip curl pip flex bison zip glslang-tools"
workdir="$(pwd)/turnip_workdir"
ndkver="android-ndk-r26b" # Стабильная версия для Mesa
ndk="$workdir/$ndkver/toolchains/llvm/prebuilt/linux-x86_64/bin"
sdkver="34"
mesasrc="https://gitlab.freedesktop.org/mesa/mesa"
srcfolder="mesa"

run_all(){
    echo "====== Пошла сборка Mesa Turnip Upstream для Adreno 810 ======"
    check_deps
    prepare_workdir
    build_lib_for_android
}

check_deps(){
    echo "Проверка зависимостей..."
    sudo apt update && sudo apt install -y $deps
    pip install mako --break-system-packages || pip install mako
}

prepare_workdir(){
    mkdir -p "$workdir" && cd "$workdir"

    echo "Загрузка NDK..."
    curl -L https://dl.google.com/android/repository/"$ndkver"-linux.zip --output "$ndkver"-linux.zip
    unzip -q "$ndkver"-linux.zip

    echo "Клонирование свежей Mesa из GitLab..."
    git clone $mesasrc --depth=1 $srcfolder
    cd $srcfolder
}

build_lib_for_android(){
    echo "Применение патчей GPU Enablement..."
    # Здесь мы берем патчсет Беляша для Gen8 (A8xx)
    wget https://github.com/whitebelyash/mesa-tu8/releases/download/patchset-head-v2/tu8_kgsl.patch
    git apply tu8_kgsl.patch || echo "Ошибка наложения патча, возможно в upstream уже есть часть кода"

    # Настройка путей компилятора
    export PATH="$ndk:$PATH"
    GITHASH=$(git rev-parse --short HEAD)

    echo "Создание cross-file..."
    cat <<EOF >"android-aarch64.txt"
[binaries]
ar = '$ndk/llvm-ar'
c = '$ndk/aarch64-linux-android$sdkver-clang'
cpp = ['$ndk/aarch64-linux-android$sdkver-clang++', '-fno-exceptions', '-static-libstdc++']
strip = '$ndk/llvm-strip'
pkg-config = '/usr/bin/pkg-config'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

    echo "Конфигурация Meson..."
    meson setup build-android \
        --cross-file "android-aarch64.txt" \
        --prefix /tmp/turnip-output \
        -Dbuildtype=release \
        -Dplatforms=android \
        -Dandroid-stub=true \
        -Dgallium-drivers= \
        -Dvulkan-drivers=freedreno \
        -Dfreedreno-kmds=kgsl \
        -Dvulkan-beta=true \
        -Dshader-cache=enabled

    ninja -C build-android install

    echo "Упаковка драйвера..."
    cd /tmp/turnip-output/lib
    cat <<EOF >"meta.json"
{
  "schemaVersion": 1,
  "name": "Mesa Upstream Turnip (A810)",
  "description": "Built from mesa-git with Gen8 patches by GPT363",
  "author": "GPT363",
  "packageVersion": "$BUILD_VERSION",
  "vendor": "Mesa",
  "driverVersion": "Git-$GITHASH",
  "minApi": 27,
  "libraryName": "libvulkan_freedreno.so"
}
EOF
    zip /tmp/mesa-turnip-gen8-V$BUILD_VERSION.zip libvulkan_freedreno.so meta.json
    echo "Готово! Архив в /tmp/"
}

run_all
