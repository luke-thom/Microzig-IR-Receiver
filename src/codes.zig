const ir = @import("ir.zig");

pub const MediaKeyCode = enum (u16) {
    eject = 184,
    fast_forward = 179,
    rewind,
    scan_next_track,
    scan_previouse_track,
    stop,
    play_pause = 205,
};

pub fn toKeyCode(command: ir.IrCommand) ?MediaKeyCode {
    return switch (command.address) {
        696 => switch (command.command) {
            4 => .stop,
            0 => .scan_previouse_track,
            1 => .scan_next_track,
            else => null,
        },
        952 => switch (command.command) {
            6 => .play_pause,
            else => null,
        },
        else => null,
    };
}
