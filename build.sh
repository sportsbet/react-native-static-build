#!/bin/bash

# Immediately quit on error
set -e

SCRIPTPATH=$( cd "$(dirname "$0")" ; pwd -P ) 
OUT_BUILD_DIR="$SCRIPTPATH/build"
REACT_ROOT="$2"
SCRIPTNAME="$0"

# Parameters:
# 1. Name - The name of this script
print_usage () {
	local _underline=`tput smul`
	local _nounderline=`tput rmul`
	echo "USAGE"
	echo "$0 -build ${_underline}reactnodemodulepath${_nounderline}"
	echo ""
	echo "$0 -clean"
	echo ""
	exit 1
}

REACT_LIBS=(
	ActionSheetIOS
	Geolocation
	Image
	LinkingIOS
	NativeAnimation
	Network
	Settings
	Text
	Vibration
	WebSocket
)

REJECT_ARCHIVES=(
	libdouble-conversion.a
	libjschelpers.a
	libthird-party.a
	libcxxreact.a
	libyoga.a
)

# Parameters:
# 1. debug/release
# 2. simulator/device
# 3. Xcodeproj
build () {
	case "$1" in
		debug)
			local configuration="Debug"
			;;
		
		release)
			local configuration="Release"
			;;

		*)
			print_usage "$SCRIPTNAME"
	esac

	case "$2" in
		simulator)
			local archs="x86_64"
			local sdk="iphonesimulator10.3"
			;;

		device)
			local archs="armv7 arm64"
			local sdk="iphoneos10.3"
			;;

		*)
			print_usage "$SCRIPTNAME"
	esac
	local xcodeproj="$3"
	local target=$(basename "$xcodeproj" .xcodeproj)

	local xcargs=(-project "$xcodeproj"
		-target "$target"
		-sdk "$sdk"
		-configuration "$configuration"
		build
		RCT_NO_LAUNCH_PACKAGER=yes
		RUN_CLANG_STATIC_ANALYZER=no
		ARCHS="$archs"
		ONLY_ACTIVE_ARCH=no
		MODULE_CACHE_DIR="$OUT_BUILD_DIR/DerivedData/ModuleCache"
		OBJROOT="$OUT_BUILD_DIR/Intermediates"
		SHARED_PRECOMPS_DIR="$OUT_BUILD_DIR/Intermediates/PrecompiledHeaders"
		SYMROOT="$OUT_BUILD_DIR/Products"
	)
	echo "xcodebuild ${xcargs[@]}"
	xcodebuild "${xcargs[@]}" > "$OUT_BUILD_DIR/xcodebuild.$configuration.$2.log"
}

# Parameters
# 1. Xcodeproj
build_all_variants () {
	local xcodeproj="$1"
	build "debug" "simulator" "$xcodeproj"
	build "release" "simulator" "$xcodeproj"
	build "debug" "device" "$xcodeproj"
	build "release" "device" "$xcodeproj"
}

# Parameters:
# 1. debug/release
# 2. simulator/device
join_libraries () {
	case "$1" in
		debug)
			local configuration="Debug"
			;;
		
		release)
			local configuration="Release"
			;;

		*)
			print_usage "$SCRIPTNAME"
	esac

	local dest="$2"
	case "$dest" in
		simulator)
			local build_dir="$OUT_BUILD_DIR/Products/$configuration-iphonesimulator"
			;;

		device)
			local build_dir="$OUT_BUILD_DIR/Products/$configuration-iphoneos"
			;;

		*)
			print_usage "$SCRIPTNAME"
	esac

	# Delete archives that we don't need
	for reject_lib in "${REJECT_ARCHIVES[@]}"; do
		echo "Deleting $build_dir/${reject_lib}"
		rm "$build_dir/${reject_lib}"
	done

	# Link all of React Native's .a files into a single .a file:
	pushd "$build_dir" > /dev/null
	echo "$PWD"
	echo "libtool -static -o \"libReact.$configuration.a\" *.a"
	find . -name '*.a' -depth 1 -print0 | xargs -0 libtool -static -o "libReact.$1.a" >> "$OUT_BUILD_DIR/xcodebuild.$configuration.$dest.log" 2>&1
	popd > /dev/null
}

# Parameters
# 1. debug/release
pack_universal_binary () {
	local configuration="$1"
	case "$1" in
		debug)
			local device_build_dir="$OUT_BUILD_DIR/Products/Debug-iphonesimulator"
			local sim_build_dir="$OUT_BUILD_DIR/Products/Debug-iphoneos"
			;;
		
		release)
			local device_build_dir="$OUT_BUILD_DIR/Products/Release-iphonesimulator"
			local sim_build_dir="$OUT_BUILD_DIR/Products/Release-iphoneos"
			;;

		*)
			print_usage "$SCRIPTNAME"
	esac
	
	join_libraries "$configuration" "simulator"
	join_libraries "$configuration" "device"	

	# Join the device / simulator .a files into a fat .a file:
	local xcrun_args=(
		-sdk iphoneos 
		lipo -create 
		-output "$OUT_BUILD_DIR/libReact.$configuration.a"
		"$device_build_dir/libReact.$configuration.a"
		"$sim_build_dir/libReact.$configuration.a"
	)
	echo "xcrun ${xcrun_args[@]}"
	xcrun "${xcrun_args[@]}"
}

case "$1" in
	-build)
		mkdir -p "$OUT_BUILD_DIR"

		if [ -z "$REACT_ROOT" ] || [ ! -e "$REACT_ROOT" ] ; then
			print_usage $0
		fi

		build_all_variants "$REACT_ROOT/React/React.xcodeproj"

		for react_lib in "${REACT_LIBS[@]}"; do
			libdir="$REACT_ROOT/Libraries/$react_lib"
			xcodeproj=$(find "$libdir" -name '*.xcodeproj' | head -n 1)
			build_all_variants "$xcodeproj"
		done

		pack_universal_binary "debug"
		pack_universal_binary "release"
		rm -rf libReact.release.a libReact.debug.a include
		cp "$OUT_BUILD_DIR/libReact.debug.a" "$OUT_BUILD_DIR/libReact.release.a" .
		cp -R "$OUT_BUILD_DIR/Products/Release-iphoneos/include" .
		;;

	-clean)
		rm -rf "$OUT_BUILD_DIR"
		;;

	*)
		print_usage "$0"
esac

