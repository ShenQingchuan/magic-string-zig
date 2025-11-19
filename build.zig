const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const target_result = target.result;

    const os_name = switch (target_result.os.tag) {
        .macos => "darwin",
        .windows => "win32",
        .linux => "linux",
        else => @tagName(target_result.os.tag),
    };

    const arch_name = switch (target_result.cpu.arch) {
        .aarch64 => "arm64",
        .x86_64 => "x64",
        else => @tagName(target_result.cpu.arch),
    };

    // 基础库名
    const lib_name = b.fmt("magic-string.{s}-{s}", .{ os_name, arch_name });

    const lib = b.addSharedLibrary(.{
        .name = lib_name,
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const dep_napi = b.dependency("napi", .{});
    lib.root_module.addImport("napi", dep_napi.module("napi"));

    lib.linker_allow_shlib_undefined = true;

    // 最终文件名：magic-string.darwin-arm64.node
    const node_filename = b.fmt("{s}.node", .{lib_name});

    // 直接安装改名后的文件到 zig-out/lib
    // 这样只会生成 .node 文件，不会保留 .dylib/.so
    const install_node = b.addInstallFile(lib.getEmittedBin(), b.pathJoin(&.{ "lib", node_filename }));

    b.getInstallStep().dependOn(&install_node.step);
}
