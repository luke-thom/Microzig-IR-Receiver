const std = @import("std");
const microzig = @import("microzig");
const gpio_irq = @import("gpio_irq.zig");

const hal = microzig.hal;
const time = hal.time;

const Absolote = microzig.drivers.time.Absolute;
const Duration = microzig.drivers.time.Duration;

pub const IrCommand = struct {address: u16, command: u8};

// Timeings for parsing the transmission in nano seconds
const transmission_time = 80000;
const first_pulse_time = 9000;
const first_empty_command_time = 4500;
const first_empty_repeat_time = 2550;
const pulse_time = 560;
const empty_0_time = 560;
const empty_1_time = 1690;

var ticks: [256]Absolote = undefined;
var tick_index: usize = 0;

const FnSetAlarm = *const fn (target: Absolote) void;

// alarm must be a pointer to the alarm from the timer struct
pub fn onPin(setAlarm: FnSetAlarm) void {
    logTick(setAlarm);
}

pub fn onTimer() !IrCommand {
    return decode();
}

fn isAround(duration: Duration, target: u64) bool {
    const tolerance = 100; 
    const us = duration.to_us();
    return target - tolerance < us and us < target + tolerance;
}

fn logTick(setAlarm: FnSetAlarm) void {
    const now = time.get_time_since_boot();
    const is_first = now.diff(ticks[0]).to_us() > transmission_time;
    if (is_first) {
        setAlarm(now.add_duration(.from_us(transmission_time)));
        tick_index = 0;
    }
    if (tick_index > ticks.len) return;
    ticks[tick_index] = now;
    tick_index += 1;
}

fn decode() !IrCommand {
    const first_pulse = ticks[1].diff(ticks[0]);
    const first_empty = ticks[2].diff(ticks[1]);

    // std.log.debug("{} {}", .{first_pulse, first_empty});
    if (isAround(first_empty, first_empty_repeat_time)) {
        return error.Repeat;
    }
    if (!isAround(first_pulse, first_pulse_time)) {
        return error.BadHeader;
    }
    if (!isAround(first_empty, first_empty_command_time)) {
        return error.BadHeader;
    }

    var address: u16 = 0;
    var address_high: u16 = 0; 
    var command: u8 = 0;
    var command_inverse: u8 = 0;
    for (3..tick_index) |index| {
        const diff = ticks[index].diff(ticks[index-1]);
        if (index % 2 == 1) { // pule
            if (!isAround(diff, pulse_time)) return error.BadData;
        } else { // empty
            const bit: u8 = if (isAround(diff, empty_0_time)) 0 
                else if (isAround(diff, empty_1_time)) 1
                else return error.BadData;
            const current_bits = (index-3)/2;
            const shift: u3 = @intCast(current_bits % 8);
            switch (current_bits / 8) {
                0 => address|= bit << shift,
                1 => address_high |= bit << shift,
                2 => command |= bit << shift,
                3 => command_inverse |= bit << shift,
                else => return error.BigPacket,
            }
        }
    }
    if (command != ~command_inverse) {
        std.log.debug("Bad command", .{});
        return error.BadData;
    }
    if (address != ~address_high) address |= address_high << 8;
    return .{.address = address, .command = command};
}

