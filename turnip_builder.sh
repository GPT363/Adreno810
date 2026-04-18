#!/bin/bash -e

# Цветовые переменные ля вывода в консоль
green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'

# Список необходимых зависимостей
deps="git meson ninja patchelf unzip curl pip flex bison zip glslang glslangValidator"
workdir="$(pwd)/turnip_workdir"
ndkver="android-ndk-r29"
ndk="$workdir/$ndkver/toolchains/llvm/prebuilt/linux-x86_64/bin"
sdkver="34"
mesasrc="https://github.com/DiskDVD/mesa-tu8.git"
srcfolder="A8XX"

clear

run_all(){
	echo "====== Начало сборки TU V$BUILD_VERSION! ======"
	check_deps
	prepare_workdir
	build_lib_for_android A8XX
}

check_deps(){
	echo "Проверка системных зависимостей..."
	for deps_chk in $deps; do
		sleep 0.1
		if command -v "$deps_chk" >/dev/null 2>&1 ; then
			echo -e "$green - $deps_chk найдено $nocolor"
		else
			echo -e "$red - $deps_chk НЕ найдено, продолжение невозможно. $nocolor"
			deps_missing=1
		fi
	done

	if [ "$deps_missing" == "1" ]; then 
		echo "Пожалуйста, установите недостающие пакеты." && exit 1
	fi

	echo "Установка зависимости python Mako..."
	pip install mako &> /dev/null
}

prepare_workdir(){
	echo "Подготовка рабочей директории..."
	mkdir -p "$workdir" && cd "$workdir"

	echo "Загрузка Android NDK r29..."
	curl -L https://dl.google.com/android/repository/"$ndkver"-linux.zip --output "$ndkver"-linux.zip &> /dev/null
	echo "Распаковка NDK..."
	unzip -q "$ndkver"-linux.zip &> /dev/null

	echo "Клонирование исходного кода Mesa..."
	git clone $mesasrc --depth=1 --no-single-branch $srcfolder
	cd $srcfolder
	
	echo "Запись версии TU..."
	echo "#define TUGEN8_DRV_VERSION \"v$BUILD_VERSION\"" > ./src/freedreno/vulkan/tu_version.h
}

build_lib_for_android(){
	echo "==== Сборка Mesa на ветке $1 ===="
	git checkout origin/$1

	# Настройка окружения для использования Clang из NDK
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

	echo "Генерация файлов кросс-компиляции..."
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

	echo "Настройка Meson (LTO отключен для стабильности)..."
	meson setup build-android-aarch64 \
		--cross-file "android-aarch64.txt" \
		--native-file "native.txt" \
		--prefix /tmp/turnip-$1 \
		-Dbuildtype=release \
		-Db_lto=false \
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
		-Dandroid-libbacktrace=disabled \
		--reconfigure

	echo "Компиляция через Ninja (это займет время)..."
	ninja -C build-android-aarch64 install

	if [ ! -f /tmp/turnip-$1/lib/libvulkan_freedreno.so ]; then
		echo -e "$red Ошибка сборки! Библиотека .so не найдена. $nocolor" && exit 1
	fi

	echo "Создание архива с драйвером..."
	cd /tmp/turnip-$1/lib
	cat <<EOF >"meta.json"
{
  "schemaVersion": 1,
  "name": "A8XX T-$BUILD_VERSION",
  "description": "Сборка для Adreno 8XX. Ветка: $1",
  "author": " Whitebeliash / DerixSpace / DVD_Disk",
  "packageVersion": "1",
  "vendor": "Mesa",
  "driverVersion": "Vulkan 1.4.335",
  "minApi": 28,
  "libraryName": "libvulkan_freedreno.so"
}
EOF
	# ИСПРАВЛЕНО: имя архива совпадает с ожидаемым в YAML
	zip /tmp/A8XX_T-V$BUILD_VERSION.zip libvulkan_freedreno.so meta.json
	cd -
	
	if [ -f /tmp/A8XX_T-V$BUILD_VERSION.zip ]; then
		echo -e "$green Архив успешно создан: /tmp/A8XX_T-V$BUILD_VERSION.zip $nocolor"
	else
		echo -e "$red Не удалось упаковать архив! $nocolor"
	fi
}

run_all
