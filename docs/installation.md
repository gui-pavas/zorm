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
const dep = b.dependency("zorm", .{
    .target = target,
    .optimize = optimize,
});
b.root_module.addImport("zorm", dep.module("zorm"));

const zorm = @import("zorm");
```

Add the dependency with:

```bash
zig fetch --save https://github.com/gui-pavas/zorm/archive/refs/tags/v0.1.0.tar.gz
```

## Next

Read [DRM (Driver Runtime Model)](drm.md).
