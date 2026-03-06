# Installation

## Requirements

- Zig `0.16.0-dev.2694+74f361a5c` or compatible

## Build

```bash
zig build
```

## Test

```bash
zig build test
```

## Run CLI

```bash
zig build run -- help
```

## Use as a dependency

Expose the `zorm` module in your Zig build and import with:

```zig
const zorm = @import("zorm");
```

## Next

Read [DRM (Driver Runtime Model)](drm.md).
