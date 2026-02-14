# GSKit

GSKit is a macOS 26 experiment for viewing Gaussian splats through a RealityKit-native render path. The repo contains a Swift package with the loader, mesh baking, material, and GPU sorting pipeline, plus a small demo app with fly-through navigation for opening `.ply` captures.

This is intentionally an experiment, not a polished product. The codebase is optimized for clarity around the rendering approach rather than API breadth, portability, or backwards compatibility.

## What It Does

- Parses binary `.ply` data for point clouds and Gaussian splats.
- Bakes splats into `LowLevelMesh` quad geometry that RealityKit can own directly.
- Shades splats with a single RealityKit `CustomMaterial` surface shader.
- Reorders indices on the GPU to improve transparent blending for dense splat clouds.
- Ships a minimal macOS demo app for opening a file and exploring it with fly controls.

## Repository Layout

- `GSKitPackage/`: Swift package that implements parsing, mesh generation, material setup, and GPU sorting.
- `DemoApp/`: macOS app target that hosts the viewer and file-import workflow.

## Requirements

- macOS 26
- Xcode 26

## Running The Demo

1. Open `DemoApp/GSKit.xcodeproj` in Xcode.
2. Build and run the `GSKitDemo` scheme on macOS.
3. Import a binary `.ply` file from the sidebar.

## Navigation

- Right mouse drag: look around
- `W` / `S`: move forward and backward
- `A` / `D`: move down and right
- `Q` / `E`: move left and up
- Arrow keys: yaw left and right

The keyboard mappings intentionally support both QWERTY and AZERTY forward movement.

## Rendering Notes

The active render path stays inside RealityKit:

1. Parse `.ply` attributes from the source capture.
2. Decode splat attributes into renderable quad data.
3. Build a `LowLevelMesh` with baked positions, gaussian UVs, and premultiplied color.
4. Render splats through a single unlit `CustomMaterial` surface shader.
5. Reorder the mesh indices on the GPU based on camera-relative depth.

## License

This project is licensed under the MIT License. See [LICENSE](./LICENSE).
