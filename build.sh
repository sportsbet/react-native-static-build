#!/bin/bash

# Immediately quit on error
set -e

SCRIPTPATH=$( cd "$(dirname "$0")" ; pwd -P ) 
OUT_BUILD_DIR="$SCRIPTPATH/build"
PROJECT_ROOT="$2"
SCRIPTNAME="$0"

# Parameters:
# 1. Name - The name of this script
print_usage () {
	local _underline=`tput smul`
	local _nounderline=`tput rmul`
	echo "USAGE"
	echo "$0 -build ${_underline}reactnodemodulepath${_nounderline}"
	echo ""
	echo "$0 -build-deps ${_underline}hydranodemodulepath${_nounderline}"
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
	PushNotificationIOS
)

# Update these to include the community libs you use and want to precompile
REACT_COMMUNITY_LIBS=(
	react-native-webview
	react-native-gesture-handler
	@react-native-community/netinfo
)

REJECT_ARCHIVES=(
	libdouble-conversion.a
	libjsi.a
	libjsiexecutor.a
	libthird-party.a
	libcxxreact.a
	libyoga.a
	libfishhook.a
	libjsinspector.a
)

# Parameters:
# 1. debug/release
# 2. simulator/device
# 3. Xcodeproj
# 4. Should override includes
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
			local archs="i386 x86_64"
			local sdk="iphonesimulator"
			;;

		device)
			local archs="armv7 arm64"
			local sdk="iphoneos"
			;;

		*)
			print_usage "$SCRIPTNAME"
	esac
	local xcodeproj="$3"
	local target=$(basename "$xcodeproj" .xcodeproj)
	local header_search_paths='$(inherited)'
	if [ "$4" = true ] ; then
		header_search_paths=\"$SCRIPTPATH/include\"
	fi


	local xcargs=(-project "$xcodeproj"
		-UseModernBuildSystem=NO
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
		OTHER_CFLAGS='$(inherited) -fembed-bitcode'
		HEADER_SEARCH_PATHS="$header_search_paths"
		GCC_GENERATE_DEBUGGING_SYMBOLS=no
	)
	echo "xcodebuild ${xcargs[@]}"
	xcodebuild "${xcargs[@]}" > "$OUT_BUILD_DIR/xcodebuild.$configuration.$2.log"
}

# Parameters
# 1. Xcodeproj
# 2. Needs includes override
build_all_variants () {
	local xcodeproj="$1"
	local includes="$2"
	build "debug" "simulator" "$xcodeproj" "$includes"
	build "release" "simulator" "$xcodeproj" "$includes"
	build "debug" "device" "$xcodeproj" "$includes"
	build "release" "device" "$xcodeproj" "$includes"
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
		local reject_lib_path="$build_dir/${reject_lib}"
		if [ -f "$reject_lib_path" ]; then
			 echo "Deleting $reject_lib_path"
   			 rm "$build_dir/${reject_lib}"
		fi
	done

	local universal_binary_name="$3"

	# Link all of React Native's .a files into a single .a file:
	pushd "$build_dir" > /dev/null
	echo "$PWD"
	echo "libtool -static -o \"$universal_binary_name.$configuration.a\" *.a"
	find . -name '*.a' -depth 1 -print0 | xargs -0 libtool -static -o "$universal_binary_name.$1.a" >> "$OUT_BUILD_DIR/xcodebuild.$configuration.$dest.log" 2>&1
	popd > /dev/null
}

# Parameters
# 1. debug/release
# 2. ex. libReact/libReactCommunity
pack_universal_binary () {
	local configuration="$1"
	local universal_binary_name="$2"
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

	join_libraries "$configuration" "simulator" "$universal_binary_name"
	join_libraries "$configuration" "device" "$universal_binary_name"

	# Join the device / simular .a files into a fat .a file:
	local xcrun_args=(
		-sdk iphoneos
		lipo -create
		-output "$OUT_BUILD_DIR/$universal_binary_name.a"
		"$device_build_dir/$universal_binary_name.$configuration.a"
		"$sim_build_dir/$universal_binary_name.$configuration.a"
	)
	echo "xcrun ${xcrun_args[@]}"
	xcrun "${xcrun_args[@]}"
	strip -Sx "$OUT_BUILD_DIR/$universal_binary_name.a"
	pushd "$OUT_BUILD_DIR"
	zip "$universal_binary_name.$configuration.a.zip" "$universal_binary_name.a"
	rm "$universal_binary_name.a"
	popd
}

case "$1" in
	-build)
		mkdir -p "$OUT_BUILD_DIR"

		if [ -z "$PROJECT_ROOT" ] || [ ! -e "$PROJECT_ROOT" ] ; then
			print_usage $0
		fi

		build_all_variants "$PROJECT_ROOT/React/React.xcodeproj" false

		for react_lib in "${REACT_LIBS[@]}"; do
			libdir="$PROJECT_ROOT/Libraries/$react_lib"
			xcodeproj=$(find "$libdir" -name '*.xcodeproj' | head -n 1)
			build_all_variants "$xcodeproj" false
		done

		pack_universal_binary "debug" "libReact"
		pack_universal_binary "release" "libReact"
		rm -rf libReact.release.a libReact.debug.a include
		cp "$OUT_BUILD_DIR/libReact.debug.a.zip" "$OUT_BUILD_DIR/libReact.release.a.zip" .
		cp -R "$OUT_BUILD_DIR/Products/Release-iphoneos/include" .
		;;
	
	-build-deps)
		if [ ! -d "$SCRIPTPATH/include" ]; then
			# Fail early if the react native headers are not available in React Native folder.
  			print_usage "$SCRIPTNAME"
		fi

		if [ -z "$PROJECT_ROOT" ] || [ ! -e "$PROJECT_ROOT" ] ; then
			print_usage $0
		fi

		mkdir -p "$OUT_BUILD_DIR"
		
		for react_lib in "${REACT_COMMUNITY_LIBS[@]}"; do
			libdir="$PROJECT_ROOT/$react_lib"
			xcodeproj=$(find "$libdir" -name '*.xcodeproj' | head -n 1)
			build_all_variants "$xcodeproj" true
		done
		
		pack_universal_binary "debug" "libReactCommunity"
		pack_universal_binary "release" "libReactCommunity"
		rm -rf libReactCommunity.release.a libReactCommunity.debug.a
		cp "$OUT_BUILD_DIR/libReactCommunity.debug.a.zip" "$OUT_BUILD_DIR/libReactCommunity.release.a.zip" .
		;;
	
	-clean)
		rm -rf "$OUT_BUILD_DIR"
		;;

	*)
		print_usage "$0"
esac
