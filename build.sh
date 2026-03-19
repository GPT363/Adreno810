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

# Какой патч Беляша использовать?
WHITEBELYASH_PATCH="tu8_kgsl.patch"  # Можно изменить на другой

echo "====== Begin building TU V$BUILD_VERSION for Adreno 810 ======"
echo "Using whitebelyash patch: $WHITEBELYASH_PATCH"

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

# Клонируем чистый Mesa
if [ ! -d "$srcfolder" ]; then
    echo "Cloning Mesa main..."
    git clone $mesasrc --depth=1 -b main $srcfolder
fi

cd $srcfolder

# Сбрасываем изменения
git reset --hard HEAD
git clean -fd

# ===== ПРИМЕНЯЕМ ПАТЧ БЕЛЯША =====
echo "Applying whitebelyash patch: $WHITEBELYASH_PATCH"

if [ -f "../../patches/whitebelyash/$WHITEBELYASH_PATCH" ]; then
    cp "../../patches/whitebelyash/$WHITEBELYASH_PATCH" ./
    
    echo "Trying to apply $WHITEBELYASH_PATCH..."
    if git apply --check "$WHITEBELYASH_PATCH" 2>/dev/null; then
        git apply "$WHITEBELYASH_PATCH"
        echo "✓ whitebelyash patch applied successfully"
    else
        echo "⚠ Patch failed, trying with -3 (3-way merge)..."
        if git apply -3 --check "$WHITEBELYASH_PATCH" 2>/dev/null; then
            git apply -3 "$WHITEBELYASH_PATCH"
            echo "✓ whitebelyash patch applied with 3-way merge"
        else
            echo "✗ Failed to apply $WHITEBELYASH_PATCH!"
            echo "Trying alternative patches..."
            
            # Пробуем другие патчи по очереди
            for alt_patch in tu_gen8_kgsl_android.patch tu_gen8.patch tu8_kgsl_26.patch; do
                if [ -f "../../patches/whitebelyash/$alt_patch" ]; then
                    echo "Trying $alt_patch..."
                    cp "../../patches/whitebelyash/$alt_patch" ./
                    if git apply --check "$alt_patch" 2>/dev/null; then
                        git apply "$alt_patch"
                        echo "✓ Using $alt_patch instead"
                        WHITEBELYASH_PATCH="$alt_patch"
                        break
                    fi
                fi
            done
            
            # Если ни один не подошёл
            if [ $? -ne 0 ]; then
                echo "✗ No compatible whitebelyash patch found!"
                exit 1
            fi
        fi
    fi
else
    echo "✗ Whitebelyash patch not found at ../../patches/whitebelyash/$WHITEBELYASH_PATCH"
    echo "Available patches should be in patches/whitebelyash/"
    exit 1
fi

# ===== ПРИМЕНЯЕМ ВАШИ ПАТЧИ =====
echo "Applying GPT363 optimizations for Adreno 810..."

if [ -f "../../patches/gpt363/a810-all-changes.patch" ]; then
    echo "Applying a810-all-changes.patch..."
    cp "../../patches/gpt363/a810-all-changes.patch" ./
    
    if git apply --check a810-all-changes.patch; then
        git apply a810-all-changes.patch
        echo "✓ GPT363 patch applied successfully"
    else
        echo "✗ Failed to apply GPT363 patch!"
        echo "Your patch may be incompatible with whitebelyash's base"
        exit 1
    fi
else
    echo "✗ GPT363 patch not found at ../../patches/gpt363/a810-all-changes.patch"
    exit 1
fi

# Проверяем наличие A810 в коде
echo "Verifying A810 support..."
if grep -q "A810\|gpu_id == 810" $(find src -name "*.c" -o -name "*.cc" -o -name "*.h" 2>/dev/null | head -10); then
    echo "✓ A810 optimizations found"
else
    echo "⚠ WARNING: A810 optimizations may not be present!"
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
  "name": "Mesa Turnip A810 v$BUILD_VERSION-$GITHASH",
  "description": "Mesa Turnip for Adreno 810 (whitebelyash/$WHITEBELYASH_PATCH + GPT363 optimizations)",
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
