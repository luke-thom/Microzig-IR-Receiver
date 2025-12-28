const std = @import("std");
const microzig = @import("microzig");
// const usb_logger = @import("usb_logging.zig");
const gpio_irq = @import("gpio_irq.zig");

const hal = microzig.hal;
const time = hal.time;
const gpio = hal.gpio;

const Absolote = microzig.drivers.time.Absolute;
const Duration = microzig.drivers.time.Duration;

pub fn dummyLog(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype
) void {
    _ = .{level, scope, format, args};
}

pub const microzig_options = microzig.Options{
    .log_level = .debug,
    .logFn = dummyLog,
    .interrupts = .{
        .IO_IRQ_BANK0 = .{.c = irqGPIO},
        .TIMER_IRQ_0 = .{.c = irqTimer},
    },
};

// Timeings for parsing the transmission
const transmission_time = std.time.us_per_ms * 80;
const first_pulse_time = 9000;
const first_empty_command_time = 4500;
const first_empty_repeat_time = 2550;
const pulse_time = 560;
const empty_0_time = 560;
const empty_1_time = 1690;

const timer = microzig.chip.peripherals.TIMER;

const led = gpio.num(25);
const button = gpio.num(28);


fn irqGPIO() linksection(".ram_text") callconv(.c) void {
    _ = getIrqTrigger(); // Clear event 
    logTick();
}

fn getIrqTrigger() ?gpio_irq.IrqTrigger {
    var iter = gpio_irq.IrqEventIter{};
    return iter.next();
}

fn irqTimer() callconv(.c) void {
    const cs = microzig.interrupt.enter_critical_section();
    defer cs.leave();
    timer.INTR.modify(.{.ALARM_0 = 1});
    //    parseTicks();
    if (decode()) |data| {
        std.log.info("{}", .{data});
    } else |_| {}
}

fn setAlarm(target: Absolote) void {
    timer.ALARM0.write_raw(@intCast(target.to_us() & std.math.maxInt(u32)));
}

fn isAround(duration: Duration, target: u64) bool {
    const tolerance = 100; 
    const us = duration.to_us();
    return target - tolerance < us and us < target + tolerance;
}

var ticks: [256]Absolote = undefined;
var tick_index: usize = 0;
fn logTick() void {
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

fn decode() !struct {address: u16, command: u8} {
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

pub fn main() !void {
    // Setup LED for blinking
    led.set_function(.sio);
    led.set_direction(.out);
    led.put(1);

    // Enable GPIO button & interrupt
    button.set_function(.sio);
    button.set_direction(.in);
    button.set_pull(.up);
    gpio_irq.set_irq_enabled(
        button,
        gpio_irq.IrqEvents{ .fall = 1, .rise = 1 },
        true
    );
    microzig.interrupt.enable(.IO_IRQ_BANK0);

    // Enable timer interrupts
    microzig.interrupt.enable(.TIMER_IRQ_0);
    timer.INTE.toggle(.{.ALARM_0 = 1});

    // Setup USB

    // Initialize the loop
    var next_time = time.get_time_since_boot().add_duration(.from_ms(500));
    while (true) {
        // Todo task usb
        if (next_time.is_reached_by(time.get_time_since_boot())) {
            next_time = time.get_time_since_boot().add_duration(.from_ms(500));
            led.toggle();
        }
    }
}
