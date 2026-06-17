#!/bin/bash -e

# ============================================
# Название: A8XX-Y Build Script
# Автор: whitebelyash / DVD
# Описание: Сборка Vulkan драйвера Turnip для A8XX
# Версия: 1.0
# ============================================

#Define variables
green='\033[0;32m'
red='\033[0;31m'
yellow='\033[1;33m'
nocolor='\033[0m'
deps="git meson ninja patchelf unzip curl pip flex bison zip glslang glslangValidator"
workdir="$(pwd)/turnip_workdir"
ndkver="android-ndk-r29"
ndk="$workdir/$ndkver/toolchains/llvm/prebuilt/linux-x86_64/bin"
sdkver="34"
mesasrc="https://github.com/DiskDVD/A8XX-Y"
srcfolder="A8XX"
driver_name="A8XX-Y"

# Проверка наличия BUILD_VERSION
if [ -z "$BUILD_VERSION" ]; then
    echo -e "${red}Ошибка: переменная BUILD_VERSION не установлена!${nocolor}"
    echo "Пример: export BUILD_VERSION=1.0.0"
    exit 1
fi

clear

# Функция вывода баннера
show_banner(){
    echo -e "${green}╔══════════════════════════════════════════════════════════╗${nocolor}"
    echo -e "${green}║         A8XX-Y Vulkan Driver Builder v${BUILD_VERSION}          ║${nocolor}"
    echo -e "${green}╚══════════════════════════════════════════════════════════╝${nocolor}"
    echo ""
}

run_all(){
    show_banner
    echo -e "${yellow}====== Начало сборки ${driver_name} v${BUILD_VERSION}! ======${nocolor}"
    echo "Текущая директория: $(pwd)"
    echo ""
    check_deps
    prepare_workdir
    build_lib_for_android A8XX
}

check_deps(){
    echo -e "${yellow}Проверка системных зависимостей...${nocolor}"
    deps_missing=0
    
    for deps_chk in $deps; do
        sleep 0.15
        if command -v "$deps_chk" >/dev/null 2>&1 ; then
            echo -e "$green ✓ $deps_chk найдено $nocolor"
        else
            echo -e "$red ✗ $deps_chk не найдено! $nocolor"
            deps_missing=1
        fi
    done

    if [ "$deps_missing" == "1" ]; then
        echo -e "${red}Пожалуйста, установите недостающие зависимости${nocolor}"
        echo "Для Ubuntu/Debian: sudo apt install git meson ninja-build patchelf unzip curl python3-pip flex bison zip glslang-tools"
        exit 1
    fi

    echo -e "${green}Установка Python зависимости Mako...${nocolor}"
    pip install mako &> /dev/null || echo -e "${yellow}Предупреждение: не удалось установить mako через pip${nocolor}"
    echo ""
}

prepare_workdir(){
    echo -e "${yellow}Подготовка рабочей директории...${nocolor}"
    mkdir -p "$workdir" && cd "$_"

    echo -e "${yellow}Загрузка Android NDK...${nocolor}"
    if [ ! -f "$ndkver-linux.zip" ]; then
        curl -# https://dl.google.com/android/repository/"$ndkver"-linux.zip --output "$ndkver"-linux.zip
    else
        echo -e "${green}NDK уже загружен${nocolor}"
    fi
    
    echo -e "${yellow}Распаковка Android NDK...${nocolor}"
    if [ ! -d "$ndkver" ]; then
        unzip -q "$ndkver"-linux.zip
    else
        echo -e "${green}NDK уже распакован${nocolor}"
    fi

    echo -e "${yellow}Загрузка исходников Mesa...${nocolor}"
    if [ ! -d "$srcfolder" ]; then
        git clone $mesasrc --depth=1 --no-single-branch $srcfolder
    else
        echo -e "${green}Исходники уже загружены${nocolor}"
        cd $srcfolder
        git fetch --all
        cd ..
    fi
    cd $srcfolder
    
    echo -e "${green}Установка версии драйвера...${nocolor}"
    echo "#define TUGEN8_DRV_VERSION \"v$BUILD_VERSION\"" > ./src/freedreno/vulkan/tu_version.h
    echo ""
}

build_lib_for_android(){
    echo -e "${yellow}==== Сборка Mesa на ветке $1 ====${nocolor}"
    git checkout --force origin/$1
    
    # Проверяем, что мы на правильной ветке
    current_branch=$(git branch --show-current)
    echo -e "${green}Текущая ветка: $current_branch${nocolor}"
    
    # Настройка путей для компиляции
    mkdir -p "$workdir/bin"
    ln -sf "$ndk/clang" "$workdir/bin/cc" 2>/dev/null || true
    ln -sf "$ndk/clang++" "$workdir/bin/c++" 2>/dev/null || true
    export PATH="$workdir/bin:$ndk:$PATH"
    export CC=clang
    export CXX=clang++
    export AR=llvm-ar
    export RANLIB=llvm-ranlib
    export STRIP=llvm-strip
    export OBJDUMP=llvm-objdump
    export OBJCOPY=llvm-objcopy
    export LDFLAGS="-fuse-ld=lld"

    echo -e "${yellow}Генерация файлов сборки...${nocolor}"
    cat <<EOF >"android-aarch64.txt"
[binaries]
ar = '$ndk/llvm-ar'
c = ['ccache', '$ndk/aarch64-linux-android$sdkver-clang']
cpp = ['ccache', '$ndk/aarch64-linux-android$sdkver-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '--start-no-unused-arguments', '-static-libstdc++', '--end-no-unused-arguments']
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
[build_machine]
c = ['ccache', 'clang']
cpp = ['ccache', 'clang++']
ar = 'llvm-ar'
strip = 'llvm-strip'
c_ld = 'ld.lld'
cpp_ld = 'ld.lld'
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

    # Очищаем старую сборку, если есть
    rm -rf build-android-aarch64

    echo -e "${yellow}Настройка Meson...${nocolor}"
    meson setup build-android-aarch64 \
        --cross-file "android-aarch64.txt" \
        --native-file "native.txt" \
        --prefix /tmp/turnip-$1 \
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
        -Dplatform-sdk-version=36 \
        -Dandroid-libbacktrace=disabled

    echo -e "${yellow}Компиляция...${nocolor}"
    ninja -C build-android-aarch64 install

    if [ ! -f /tmp/turnip-$1/lib/libvulkan_freedreno.so ]; then
        echo -e "${red}❌ Сборка не удалась!${nocolor}"
        exit 1
    fi
    
    echo -e "${green}✅ Сборка успешно завершена!${nocolor}"
    
    echo -e "${yellow}Создание ZIP архива...${nocolor}"
    cd /tmp/turnip-$1/lib
    
    cat <<EOF >"meta.json"
{
  "schemaVersion": 1,
  "name": "${driver_name} v${BUILD_VERSION}",
  "description": "A8XX Vulkan Driver для Android",
  "author": "whitebelyash / DVD",
  "packageVersion": "1",
  "vendor": "Mesa",
  "driverVersion": "Vulkan 1.4.335",
  "minApi": 28,
  "libraryName": "libvulkan_freedreno.so"
}
EOF

    ZIP_NAME="/tmp/${driver_name}-v${BUILD_VERSION}.zip"
    zip -q "$ZIP_NAME" libvulkan_freedreno.so meta.json
    
    echo -e "${green}✅ Архив создан: $ZIP_NAME${nocolor}"
    ls -lh "$ZIP_NAME"
    
    # Копируем архив в рабочую директорию
    cp "$ZIP_NAME" "$workdir/"
    echo -e "${green}✅ Архив скопирован в: $workdir/${driver_name}-v${BUILD_VERSION}.zip${nocolor}"
    
    cd -
    
    if [ ! -f "$ZIP_NAME" ]; then
        echo -e "${red}❌ Не удалось создать архив!${nocolor}"
        exit 1
    fi
    
    echo ""
    echo -e "${green}╔══════════════════════════════════════════════════════════╗${nocolor}"
    echo -e "${green}║              СБОРКА УСПЕШНО ЗАВЕРШЕНА!                  ║${nocolor}"
    echo -e "${green}╚══════════════════════════════════════════════════════════╝${nocolor}"
    echo -e "${yellow}Файл драйвера:${nocolor} $ZIP_NAME"
    echo -e "${yellow}Размер:${nocolor} $(du -h "$ZIP_NAME" | cut -f1)"
    echo ""
}

run_all
