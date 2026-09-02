const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("Zephyr", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    // keep GAMEENGINE alias for backward compat
    b.modules.put(b.allocator, "GAMEENGINE", mod) catch {};

    const exe = b.addExecutable(.{
        .name = "Zephyr",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "Zephyr", .module = mod },
                .{ .name = "GAMEENGINE", .module = mod },
            },
        }),
    });

    // Win32 libs for window + GDI + GL + time + audio
    exe.root_module.link_libc = true;
    exe.root_module.linkSystemLibrary("user32", .{});
    exe.root_module.linkSystemLibrary("gdi32", .{});
    exe.root_module.linkSystemLibrary("opengl32", .{});
    exe.root_module.linkSystemLibrary("winmm", .{});
    exe.root_module.linkSystemLibrary("ole32", .{});
    exe.root_module.linkSystemLibrary("ws2_32", .{});
    // headers — add to both exe and lib module so @cImport sees them
    exe.root_module.addIncludePath(b.path("vendor"));
    mod.addIncludePath(b.path("vendor"));
    exe.root_module.addCSourceFile(.{ .file = b.path("src/gfx/stb_image_impl.c"), .flags = &.{} });
    exe.root_module.addCSourceFile(.{ .file = b.path("src/audio/miniaudio_impl.c"), .flags = &.{} });

    // Keep console for debug; switch to Windows subsystem for release if desired
    // exe.subsystem = .Windows;

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    // Table Tennis — Core2D showcase, beats Scratch
    const pong_exe = b.addExecutable(.{
        .name = "TableTennis",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/table_tennis.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "Zephyr", .module = mod },
                .{ .name = "GAMEENGINE", .module = mod },
            },
        }),
    });
    pong_exe.root_module.link_libc = true;
    pong_exe.root_module.linkSystemLibrary("user32", .{});
    pong_exe.root_module.linkSystemLibrary("gdi32", .{});
    pong_exe.root_module.linkSystemLibrary("opengl32", .{});
    pong_exe.root_module.linkSystemLibrary("winmm", .{});
    pong_exe.root_module.linkSystemLibrary("ole32", .{});
    pong_exe.root_module.linkSystemLibrary("ws2_32", .{});
    pong_exe.root_module.addIncludePath(b.path("vendor"));
    pong_exe.root_module.addCSourceFile(.{ .file = b.path("src/gfx/stb_image_impl.c"), .flags = &.{} });
    pong_exe.root_module.addCSourceFile(.{ .file = b.path("src/audio/miniaudio_impl.c"), .flags = &.{} });
    b.installArtifact(pong_exe);
    const pong_run = b.step("pong", "Run Table Tennis");
    const pong_cmd = b.addRunArtifact(pong_exe);
    pong_run.dependOn(&pong_cmd.step);
    pong_cmd.step.dependOn(b.getInstallStep());

    const breakout_exe = b.addExecutable(.{
        .name = "Breakout",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/breakout.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "Zephyr", .module = mod },
                .{ .name = "GAMEENGINE", .module = mod },
            },
        }),
    });
    breakout_exe.root_module.link_libc = true;
    breakout_exe.root_module.linkSystemLibrary("user32", .{});
    breakout_exe.root_module.linkSystemLibrary("gdi32", .{});
    breakout_exe.root_module.linkSystemLibrary("opengl32", .{});
    breakout_exe.root_module.linkSystemLibrary("winmm", .{});
    breakout_exe.root_module.linkSystemLibrary("ole32", .{});
    breakout_exe.root_module.linkSystemLibrary("ws2_32", .{});
    breakout_exe.root_module.addIncludePath(b.path("vendor"));
    breakout_exe.root_module.addCSourceFile(.{ .file = b.path("src/gfx/stb_image_impl.c"), .flags = &.{} });
    breakout_exe.root_module.addCSourceFile(.{ .file = b.path("src/audio/miniaudio_impl.c"), .flags = &.{} });
    b.installArtifact(breakout_exe);
    const breakout_run = b.step("breakout", "Run Breakout");
    const breakout_cmd = b.addRunArtifact(breakout_exe);
    breakout_run.dependOn(&breakout_cmd.step);
    breakout_cmd.step.dependOn(b.getInstallStep());

    const spacewar_exe = b.addExecutable(.{
        .name = "SpaceWar",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/spacewar.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "Zephyr", .module = mod },
                .{ .name = "GAMEENGINE", .module = mod },
            },
        }),
    });
    spacewar_exe.root_module.link_libc = true;
    spacewar_exe.root_module.linkSystemLibrary("user32", .{});
    spacewar_exe.root_module.linkSystemLibrary("gdi32", .{});
    spacewar_exe.root_module.linkSystemLibrary("opengl32", .{});
    spacewar_exe.root_module.linkSystemLibrary("winmm", .{});
    spacewar_exe.root_module.linkSystemLibrary("ole32", .{});
    spacewar_exe.root_module.linkSystemLibrary("ws2_32", .{});
    spacewar_exe.root_module.addIncludePath(b.path("vendor"));
    spacewar_exe.root_module.addCSourceFile(.{ .file = b.path("src/gfx/stb_image_impl.c"), .flags = &.{} });
    spacewar_exe.root_module.addCSourceFile(.{ .file = b.path("src/audio/miniaudio_impl.c"), .flags = &.{} });
    b.installArtifact(spacewar_exe);
    const spacewar_run = b.step("spacewar", "Run Space War");
    const spacewar_cmd = b.addRunArtifact(spacewar_exe);
    spacewar_run.dependOn(&spacewar_cmd.step);
    spacewar_cmd.step.dependOn(b.getInstallStep());

    const starimpact_exe = b.addExecutable(.{
        .name = "StarImpact",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/starimpact.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "Zephyr", .module = mod },
                .{ .name = "GAMEENGINE", .module = mod },
            },
        }),
    });
    starimpact_exe.root_module.link_libc = true;
    starimpact_exe.root_module.linkSystemLibrary("user32", .{});
    starimpact_exe.root_module.linkSystemLibrary("gdi32", .{});
    starimpact_exe.root_module.linkSystemLibrary("opengl32", .{});
    starimpact_exe.root_module.linkSystemLibrary("winmm", .{});
    starimpact_exe.root_module.linkSystemLibrary("ole32", .{});
    starimpact_exe.root_module.linkSystemLibrary("ws2_32", .{});
    starimpact_exe.root_module.addIncludePath(b.path("vendor"));
    starimpact_exe.root_module.addCSourceFile(.{ .file = b.path("src/gfx/stb_image_impl.c"), .flags = &.{} });
    starimpact_exe.root_module.addCSourceFile(.{ .file = b.path("src/audio/miniaudio_impl.c"), .flags = &.{} });
    b.installArtifact(starimpact_exe);
    const starimpact_run = b.step("starimpact", "Run Star Impact");
    const starimpact_cmd = b.addRunArtifact(starimpact_exe);
    starimpact_run.dependOn(&starimpact_cmd.step);
    starimpact_cmd.step.dependOn(b.getInstallStep());

    const mario_exe = b.addExecutable(.{
        .name = "Mario",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/mario.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "Zephyr", .module = mod },
                .{ .name = "GAMEENGINE", .module = mod },
            },
        }),
    });
    mario_exe.root_module.link_libc = true;
    mario_exe.root_module.linkSystemLibrary("user32", .{});
    mario_exe.root_module.linkSystemLibrary("gdi32", .{});
    mario_exe.root_module.linkSystemLibrary("opengl32", .{});
    mario_exe.root_module.linkSystemLibrary("winmm", .{});
    mario_exe.root_module.linkSystemLibrary("ole32", .{});
    mario_exe.root_module.linkSystemLibrary("ws2_32", .{});
    mario_exe.root_module.addIncludePath(b.path("vendor"));
    mario_exe.root_module.addCSourceFile(.{ .file = b.path("src/gfx/stb_image_impl.c"), .flags = &.{} });
    mario_exe.root_module.addCSourceFile(.{ .file = b.path("src/audio/miniaudio_impl.c"), .flags = &.{} });
    b.installArtifact(mario_exe);
    const mario_run = b.step("mario", "Run Mario");
    const mario_cmd = b.addRunArtifact(mario_exe);
    mario_run.dependOn(&mario_cmd.step);
    mario_cmd.step.dependOn(b.getInstallStep());

    const cube_exe = b.addExecutable(.{
        .name = "Cube3D",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cube3d.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "Zephyr", .module = mod },
                .{ .name = "GAMEENGINE", .module = mod },
            },
        }),
    });
    cube_exe.root_module.link_libc = true;
    cube_exe.root_module.linkSystemLibrary("user32", .{});
    cube_exe.root_module.linkSystemLibrary("gdi32", .{});
    cube_exe.root_module.linkSystemLibrary("opengl32", .{});
    cube_exe.root_module.linkSystemLibrary("winmm", .{});
    cube_exe.root_module.linkSystemLibrary("ole32", .{});
    cube_exe.root_module.linkSystemLibrary("ws2_32", .{});
    cube_exe.root_module.addIncludePath(b.path("vendor"));
    cube_exe.root_module.addCSourceFile(.{ .file = b.path("src/gfx/stb_image_impl.c"), .flags = &.{} });
    cube_exe.root_module.addCSourceFile(.{ .file = b.path("src/audio/miniaudio_impl.c"), .flags = &.{} });
    b.installArtifact(cube_exe);
    const cube_run = b.step("cube", "Run 3D Cube — hybrid Batch3D");
    const cube_cmd = b.addRunArtifact(cube_exe);
    cube_run.dependOn(&cube_cmd.step);
    cube_cmd.step.dependOn(b.getInstallStep());

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
