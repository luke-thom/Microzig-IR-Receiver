const std = @import("std");
const microzig = @import("microzig");
const usb_logger = @import("usb_logging.zig");

const hal = microzig.hal;
const time = hal.time;
const gpio = hal.gpio;

const Absolote = microzig.drivers.time.Absolute;
const Duration = microzig.drivers.time.Duration;

pub const microzig_options = microzig.Options{
    .log_level = .debug,
    .logFn = usb_logger.log,
    .interrupts = .{
        .IO_IRQ_BANK0 = .{.c = irqGPIO},
        .TIMER_IRQ_0 = .{.c = irqTimer},
    },
};

// Timeings for parsing the transmission
const transmission_time = std.time.us_per_ms * 80;
const preabmle1_time = 9000;
const preabmle2_time = 4500;
const pulse_time = 560;
const empty_0_time = 560;
const empty_1_time = 1690;

const system_timer = hal.system_timer.num(0);

const led = gpio.num(25);
const button = gpio.num(28);


fn irqGPIO() linksection(".ram_text") callconv(.c) void {
    _ = getIrqTrigger(); // Clear event 
    logTick();
}

fn getIrqTrigger() ?gpio.IrqTrigger {
    var iter = gpio.IrqEventIter{};
    return iter.next();
}

fn irqTimer() callconv(.c) void {
    const cs = microzig.interrupt.enter_critical_section();
    defer cs.leave();
    system_timer.clear_interrupt(.alarm0);
    //    parseTicks();
    std.log.info("{!}", .{decode()});
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
        system_timer.schedule_alarm(
            .alarm0,
            system_timer.read_low() +% transmission_time,
        );
        tick_index = 0;
    }
    if (tick_index > ticks.len) return;
    ticks[tick_index] = now;
    tick_index += 1;
}

fn parseTicks() void {
    var buffer: [8 * ticks.len]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    for (ticks[0..tick_index], 0..) |t, i| {
        writer.print("({}, {}), ", .{i, @intFromEnum(t)}) catch {};
    }
    std.log.debug("{s}", .{writer.buffered()});
    std.log.debug("Counted {} ticks", .{tick_index});
}

fn decode() !struct {address: u16, command: u8} {
    const preabmle1 = ticks[1].diff(ticks[0]);
    const preabmle2 = ticks[2].diff(ticks[1]);
    if (
        !isAround(preabmle1, preabmle1_time)
        or !isAround(preabmle2, preabmle2_time)
    ) {
        return error.BadHeader;
    }

    var address_low: u8 = 0;
    var address_high: u8 = 0; 
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
                0 => address_low |= bit << shift,
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
    const address = if (
        address_low == ~address_high
    ) address_low
    else (@as(u16, address_high) << 8) | address_low;
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
    button.set_irq_enabled(gpio.IrqEvents{ .fall = 1, .rise = 1 }, true);
    microzig.interrupt.enable(.IO_IRQ_BANK0);

    // Enable timer interrupts
    microzig.interrupt.enable(.TIMER_IRQ_0);
    system_timer.set_interrupt_enabled(.alarm0, true);

    // Setup USB
    usb_logger.init();

    // Initialize the loop
    var next_time = time.get_time_since_boot().add_duration(.from_ms(500));
    while (true) {
        usb_logger.poll();
        if (next_time.is_reached_by(time.get_time_since_boot())) {
            next_time = time.get_time_since_boot().add_duration(.from_ms(500));
            led.toggle();
        }
    }
}
