const std = @import("std");
const microzig = @import("microzig");

const MicroBuild = microzig.MicroBuild(.{
    .rp2xxx = true,
});

pub fn build(b: *std.Build) void {
    const mz_dep = b.dependency("microzig", .{});
    const mb = MicroBuild.init(b, mz_dep) orelse return;

    const firmware = mb.add_firmware(.{
        .name = "ir_reciver",
        .target = mb.ports.rp2xxx.boards.raspberrypi.pico,
        .optimize = .ReleaseSmall,
        .root_source_file = b.path("src/main.zig"),
    });

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

    const firmware_get_codes = mb.add_firmware(.{
        .name = "get_codes",
        .target = mb.ports.rp2xxx.boards.raspberrypi.pico,
        .optimize = .ReleaseSmall,
        .root_source_file = b.path("src/get_codes_main.zig"),
    });
    mb.install_firmware(firmware_get_codes, .{});
}
