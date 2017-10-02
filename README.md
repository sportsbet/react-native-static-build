# React Native Static Build

This repo provides a version (=0.48.4) of React Native statically
compiled using the provided `build.sh` script. There are a number of
advantages to doing this:

* Don't have to compile & analyze(!) React Native every time you clean.
* Faster CI/CD
* Parallelize build in your scheme works again
* No more weird issues with `#import <React/RCT*.h>`

# Building a New Version

Currently only works with **Xcode 8.3.x**. Make sure Xcode 8.3.x is your
default toolchain by using `xcode-select`.

First ensure your environment is clean.

```sh
./build.sh -clean
```

You can now check out the version of React Native you want using NPM/Yarn:

```sh
mkdir -p node_modules && npm install react-native@0.48.4
```

Build against this React Native module:

```sh
./build.sh -build node_modules/react-native
```

If there are any errors they'll appear in `build/xcodebuild.*.log`.

After building, copy the `libReact.debug.a` and `libReact.release.a`, and the
`include` folder into your own project's folder structure. These files are
massive, usually over 100MB, so consider using Git LFS.

# Integrating with Xcode

There's a few ways you can do this, the way I know works is pretty complicated.

`libReact.debug.a` should be used when you're doing debug development builds.
It includes things like the React debugger, the shake gesture menu, and the
CMD+R reload shortcut. Under no circumstances should you link against this for
a production build, or you will almost certainly get rejected for private API
usage.

`libReact.release.a` should be used for production builds. It has profiling
disabled, and doesn't include any private APIs or debugging features.

Xcode doesn't support linking with a different library binary depending on
build configuration out of the box, you can try to manually specify the library
using just build settings, or:

### 1. Create a new build phase

This phase should execute *before* Compile Sources.

Shell: `/bin/bash`

```mkdir -p "$BUILT_PRODUCTS_DIR"
rm -rf "$BUILT_PRODUCTS_DIR/libReact.a"
if [ "$CONFIGURATION" = "Debug" ]; then
    cp "$PROJECT_DIR/[path-to]/libReact.debug.a" "$BUILT_PRODUCTS_DIR/libReact.a"
else
    cp "$PROJECT_DIR/[path-to]/libReact.release.a" "$BUILT_PRODUCTS_DIR/libReact.a"
fi
```

### 2. Build your app

We need your app's derived data for the next step, so run the build and wait
for it to finish.

### 3. Add libReact.a from derived data

Open your app's `$BUILT_PRODUCTS_DIR` in Finder. It's usually something like:

	$HOME/Library/Developer/Xcode/DerivedData/[Target]-[robotbarf]/Build/Products/[BuildConfiguration]-[sdk]/

Then, drag the `libReact.a` file from this folder into your Xcode Project
Navigator, in whichever group you keep your libraries.

**Do not check *copy files if needed*!**

### 4. Edit your .pbxproj

Xcode will include this library with absolute paths, so it won't work between
build configurations, or users. There is no way to change the location for
*libraries* to relative paths, so you'll need to edit the xcodeproj manually.

Open `[YourProject].xcodeproj/project.pbxproj` in your favourite text editor.

Find the `Begin PBXFileReference section`.

In this section, find `/* libReact.a */`. If you don't see `path =` on this
same line, keep looking.

Change the `path =` to just `path = libReact.a;`.

Change `sourceTree =` to `sourceTree = BUILT_PRODUCTS_DIR;`

### 5. Link with libReact.a

In the Project Editor, in your target's General tab, click the `+` and add
`libReact.a`.

### 6. Add `include` to your Header Search Paths

In the Build Settings for your target, find the **Header Search Paths** option,
and add the path to your `include` dir. Should be something like:

	$(PROJECT_DIR)/Libraries/react-native/include


# Adding new React Native Libraries

This build currently bundles the following React Native libraries together:

* ActionSheetIOS
* Geolocation
* Image
* LinkingIOS
* NativeAnimation
* Network
* Settings
* Text
* Vibration
* WebSocket

If you need to add more, make sure it's available in the
`node_modules/react-native/Libraries` folder, then just add it to the list in
`build.sh` starting on line 24.
