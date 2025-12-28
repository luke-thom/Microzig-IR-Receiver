const std = @import("std");
const microzig = @import("microzig");

const MicroBuild = microzig.MicroBuild(.{
    .rp2xxx = true,
});

pub fn build(b: *std.Build) void {
    const mz_dep = b.dependency("microzig", .{});
    const mb = MicroBuild.init(b, mz_dep) orelse return;

    const firmware = mb.add_firmware(.{
        .name = "blinky",
        .target = mb.ports.rp2xxx.boards.raspberrypi.pico,
        .optimize = .ReleaseSmall,
        .root_source_file = b.path("src/main.zig"),
    });

    // We call this twice to demonstrate that the default binary output for
    // RP2040 is UF2, but we can also output other formats easily
    const firmware_install = mb.add_install_firmware(firmware, .{ });
    b.getInstallStep().dependOn(&firmware_install.step);
    
    const flash_step = b.step("flash", "copy the firmware to the device");
    const mount_run = b.addSystemCommand(&.{"udisksctl", "mount","-b", "/dev/disk/by-label/RPI-RP2"});
    const copy_run = b.addSystemCommand(&.{"cp"});
    copy_run.addFileArg(firmware_install.source);
    copy_run.addArg("/run/media/lucas/RPI-RP2/");
    flash_step.dependOn(&copy_run.step);
    copy_run.step.dependOn(&mount_run.step);
    mount_run.step.dependOn(&firmware_install.step);
}
