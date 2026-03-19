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
BUILD_VERSION=${1:-"custom"}

echo "====== Begin building TU V$BUILD_VERSION for Adreno 810 ======"

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

# Клонируем свежий Mesa
if [ ! -d "$srcfolder" ]; then
    echo "Cloning Mesa main..."
    git clone $mesasrc --depth=1 -b main $srcfolder
fi

cd $srcfolder

# Сбрасываем изменения
git reset --hard HEAD
git clean -fd

# ===== ПРИМЕНЯЕМ ВЕСЬ ПАТЧ =====
echo "Applying complete A810 patch..."

if [ -f "../../patches/a810-all-changes.patch" ]; then
    cp "../../patches/a810-all-changes.patch" ./
    
    # Пробуем применить через git am (лучший способ для format-patch)
    echo "Trying git am..."
    if git am a810-all-changes.patch; then
        echo "✓ Patch applied with git am!"
    else
        echo "git am failed, aborting..."
        git am --abort
        
        # Пробуем git apply с reject файлами
        echo "Trying git apply with reject files..."
        if git apply --reject a810-all-changes.patch; then
            echo "✓ Patch applied with git apply"
        else
            echo "git apply failed, checking reject files..."
            
            # Показываем что не наложилось
            find . -name "*.rej" | head -5 || echo "No reject files found"
            
            # Пробуем patch command как последний шанс
            echo "Trying patch command..."
            if patch -p1 -i a810-all-changes.patch -N -t; then
                echo "✓ Patch applied with patch command!"
            else
                echo "✗ Failed to apply patch!"
                exit 1
            fi
        fi
    fi
else
    echo "✗ Patch not found at ../../patches/a810-all-changes.patch"
    exit 1
fi

# Проверяем, что патч наложился
echo "Verifying patch application..."
if grep -q "A810\|810" $(find src -name "*.c" -o -name "*.h" -o -name "*.py" 2>/dev/null | head -5); then
    echo "✓ A810 code found in source"
else
    echo "⚠ WARNING: A810 code not found, patch may have failed!"
fi

# Получаем хеш коммита
GITHASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

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
  "name": "Mesa Turnip A810 v$BUILD_VERSION-$GITHASH",
  "description": "Mesa Turnip with full A810 support (387 patches + GPT363)",
  "author": "whitebelyash / DVD",
  "packageVersion": "1",
  "vendor": "Mesa",
  "driverVersion": "Vulkan 1.4.335",
  "minApi": 28,
  "libraryName": "libvulkan_freedreno.so"
}
EOF

zip "/tmp/mesa-turnip-A810-v$BUILD_VERSION.zip" libvulkan_freedreno.so meta.json

cd "$workdir"

if [ -f "/tmp/mesa-turnip-A810-v$BUILD_VERSION.zip" ]; then
    echo -e "$green Build successful! Archive: /tmp/mesa-turnip-A810-v$BUILD_VERSION.zip $nocolor"
    ls -lh /tmp/mesa-turnip-A810-v$BUILD_VERSION.zip
else
    echo -e "$red Failed to create archive! $nocolor"
    exit 1
fi
