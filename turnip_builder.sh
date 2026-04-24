#!/bin/bash -e

green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'

deps="git meson ninja patchelf unzip curl pip flex bison zip glslang glslangValidator"

workdir="$GITHUB_WORKSPACE/turnip_workdir"
outputdir="$GITHUB_WORKSPACE/output"

ndkver="android-ndk-r29"
ndk="$workdir/$ndkver/toolchains/llvm/prebuilt/linux-x86_64/bin"

sdkver="34"
mesasrc="https://github.com/DiskDVD/mesa-tu8"
srcfolder="A8XX"

run_all(){
	echo "====== Begin building TU V$BUILD_VERSION! ======"
	check_deps
	prepare_workdir
	build_lib_for_android A8XX
}

check_deps(){
	echo "Checking dependencies..."

	for deps_chk in $deps; do
		if command -v "$deps_chk" >/dev/null 2>&1 ; then
			echo -e "$green - $deps_chk found $nocolor"
		else
			echo -e "$red - $deps_chk NOT FOUND $nocolor"
			exit 1
		fi
	done

	pip install mako &> /dev/null
}

prepare_workdir(){
	mkdir -p "$workdir" "$outputdir"
	cd "$workdir"

	echo "Downloading NDK..."
	curl -L https://dl.google.com/android/repository/"$ndkver"-linux.zip -o ndk.zip
	unzip -q ndk.zip

	echo "Cloning mesa..."
	git clone $mesasrc --depth=1 $srcfolder
	cd $srcfolder

	echo "#define TUGEN8_DRV_VERSION \"v$BUILD_VERSION\"" > ./src/freedreno/vulkan/tu_version.h
}

build_lib_for_android(){
	echo "==== Building for $1 ===="
	git checkout origin/$1

	mkdir -p "$workdir/bin"
	ln -sf "$ndk/clang" "$workdir/bin/cc"
	ln -sf "$ndk/clang++" "$workdir/bin/c++"

	export PATH="$workdir/bin:$ndk:$PATH"
	export CC=clang
	export CXX=clang++

	cat <<EOF > android-aarch64.txt
[binaries]
ar = '$ndk/llvm-ar'
c = ['$ndk/aarch64-linux-android$sdkver-clang']
cpp = ['$ndk/aarch64-linux-android$sdkver-clang++']
strip = '$ndk/llvm-strip'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

	meson setup build \
		--cross-file android-aarch64.txt \
		--prefix /tmp/turnip \
		-Dbuildtype=release \
		-Dstrip=true \
		-Dplatforms=android \
		-Dvulkan-drivers=freedreno \
		-Dfreedreno-kmds=kgsl \
		-Dplatform-sdk-version=$sdkver

	ninja -C build install

	if ! [ -f /tmp/turnip/lib/libvulkan_freedreno.so ]; then
		echo -e "$red Build failed $nocolor"
		exit 1
	fi

	cd /tmp/turnip/lib

	# Явно проверяем, что meta.json создан
	cat <<EOF > meta.json
{
  "schemaVersion": 1,
  "name": "A8XX_Y$BUILD_VERSION",
  "description": "A8xx support",
  "author": "whitebelyash / DVD",
  "packageVersion": "1",
  "vendor": "Mesa",
  "driverVersion": "Vulkan",
  "minApi": 28,
  "libraryName": "libvulkan_freedreno.so"
}
EOF

	if [ ! -f meta.json ]; then
		echo -e "$red meta.json was not created $nocolor"
		exit 1
	fi

	echo "Packing..."
	zip "$outputdir/A8XX_Y$BUILD_VERSION.zip" libvulkan_freedreno.so meta.json

	if ! [ -f "$outputdir/A8XX_Y$BUILD_VERSION.zip" ]; then
		echo -e "$red ZIP FAILED $nocolor"
		exit 1
	fi

	# Дополнительная проверка: что архив не пустой и содержит нужные файлы
	if ! unzip -l "$outputdir/A8XX_Y$BUILD_VERSION.zip" | grep -q "libvulkan_freedreno.so"; then
		echo -e "$red ZIP archive does not contain libvulkan_freedreno.so $nocolor"
		exit 1
	fi
}

run_all
