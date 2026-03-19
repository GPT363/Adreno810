#!/bin/bash -e

# Цвета для вывода
green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'

# Переменные
workdir="$(pwd)/turnip_workdir"
ndkver="android-ndk-r29"
ndk="$workdir/$ndkver/toolchains/llvm/prebuilt/linux-x86_64/bin"
sdkver="34"
mesasrc="https://gitlab.freedesktop.org/mesa/mesa"
srcfolder="mesa"
BUILD_VERSION=${1:-"custom"}  # Версия из аргумента или "custom"

echo "====== Begin building TU V$BUILD_VERSION! ======"

# Создаём рабочую директорию
mkdir -p "$workdir"
cd "$workdir"

# Скачиваем NDK если нет
if [ ! -d "$ndkver" ]; then
    echo "Downloading android-ndk..."
    curl -L "https://dl.google.com/android/repository/${ndkver}-linux.zip" -o ndk.zip
    unzip ndk.zip > /dev/null
    rm ndk.zip
fi

# Клонируем Mesa если нет
if [ ! -d "$srcfolder" ]; then
    echo "Cloning Mesa..."
    git clone $mesasrc --depth=1 -b main $srcfolder
fi

cd $srcfolder

# Сбрасываем изменения (на случай если уже были патчи)
git reset --hard HEAD
git clean -fd

# ===== ПРИМЕНЯЕМ ПАТЧИ =====
echo "Applying patches..."

# Патчи Беляша (из репозитория)
if [ -f "../../patches/whitebelyash/tu8_kgsl.patch" ]; then
    echo "Applying whitebelyash patch..."
    cp "../../patches/whitebelyash/tu8_kgsl.patch" ./
    if git apply --check tu8_kgsl.patch; then
        git apply tu8_kgsl.patch
        echo "✓ whitebelyash patch applied"
    else
        echo "✗ Failed to apply whitebelyash patch!"
        exit 1
    fi
else
    echo "⚠ whitebelyash patch not found, skipping..."
fi

# Ваши патчи (из репозитория)
if [ -f "../../patches/gpt363/a810-all-changes.patch" ]; then
    echo "Applying GPT363 patch..."
    cp "../../patches/gpt363/a810-all-changes.patch" ./
    if git apply --check a810-all-changes.patch; then
        git apply a810-all-changes.patch
        echo "✓ GPT363 patch applied"
    else
        echo "✗ Failed to apply GPT363 patch!"
        exit 1
    fi
else
    echo "⚠ GPT363 patch not found, skipping..."
fi

# Получаем хеш коммита
GITHASH=$(git rev-parse --short HEAD)

# Настраиваем компилятор
mkdir -p "$workdir/bin"
ln -sf "$ndk/clang" "$workdir/bin/cc"
ln -sf "$ndk/clang++" "$workdir/bin/c++"
export PATH="$workdir/bin:$ndk:$PATH"
export CC=clang
export CXX=clang++
export AR=llvm-ar
export RANLIB=llvm-ranlib
export STRIP=llvm-strip
export OBJDUMP=llvm-objdump
export OBJCOPY=llvm-objcopy
export LDFLAGS="-fuse-ld=lld"

# Создаём файлы конфигурации Meson
cat <<EOF >"android-aarch64.txt"
[binaries]
ar = '$ndk/llvm-ar'
c = ['ccache', '$ndk/aarch64-linux-android${sdkver}-clang']
cpp = ['ccache', '$ndk/aarch64-linux-android${sdkver}-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '--start-no-unused-arguments', '-static-libstdc++', '--end-no-unused-arguments']
c_ld = '$ndk/ld.lld'
cpp_ld = '$ndk/ld.lld'
strip = '$ndk/llvm-strip'
pkg-config = ['env', 'PKG_CONFIG_LIBDIR=$ndk/pkg-config', '/usr/bin/pkg-config']

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

cat <<EOF >"native.txt"
[binaries]
c = ['ccache', 'clang']
cpp = ['ccache', 'clang++']
ar = 'llvm-ar'
strip = 'llvm-strip'
c_ld = 'ld.lld'
cpp_ld = 'ld.lld'

[build_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

# Конфигурируем сборку
echo "Configuring build..."
meson setup build-android-aarch64 \
    --cross-file "android-aarch64.txt" \
    --native-file "native.txt" \
    --prefix /tmp/turnip \
    -Dbuildtype=release \
    -Dstrip=true \
    -Dplatforms=android \
    -Dvideo-codecs= \
    -Dplatform-sdk-version="$sdkver" \
    -Dandroid-stub=true \
    -Dgallium-drivers= \
    -Dvulkan-drivers=freedreno \
    -Dvulkan-beta=true \
    -Dfreedreno-kmds=kgsl \
    -Degl=disabled \
    -Dandroid-libbacktrace=disabled \
    --reconfigure

# Компилируем
echo "Compiling..."
ninja -C build-android-aarch64 install

# Проверяем результат
if [ ! -f /tmp/turnip/lib/libvulkan_freedreno.so ]; then
    echo -e "$red Build failed! $nocolor"
    exit 1
fi

# Создаём архив
echo "Creating archive..."
cd /tmp/turnip/lib

cat <<EOF >"meta.json"
{
  "schemaVersion": 1,
  "name": "Mesa Turnip v$BUILD_VERSION-$GITHASH",
  "description": "Mesa Turnip for Adreno 810 with custom patches",
  "author": " Whitebelyash / DVD",
  "packageVersion": "1",
  "vendor": "Mesa",
  "driverVersion": "Vulkan 1.4.335",
  "minApi": 28,
  "libraryName": "libvulkan_freedreno.so"
}
EOF

zip "/tmp/mesa-turnip-V$BUILD_VERSION.zip" libvulkan_freedreno.so meta.json

cd "$workdir"

if [ -f "/tmp/mesa-turnip-V$BUILD_VERSION.zip" ]; then
    echo -e "$green Build successful! Archive: /tmp/mesa-turnip-V$BUILD_VERSION.zip $nocolor"
else
    echo -e "$red Failed to create archive! $nocolor"
    exit 1
fi
