const std = @import("std");
const microzig = @import("microzig");
// const usb_logger = @import("usb_logging.zig");
const gpio_irq = @import("gpio_irq.zig");
const ir = @import("ir.zig");

const hal = microzig.hal;
const time = hal.time;
const gpio = hal.gpio;

const timer = microzig.chip.peripherals.TIMER;

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


fn irqGPIO() linksection(".ram_text") callconv(.c) void {
    _ = getIrqTrigger(); // Clear event 
    ir.onPin(setAlarm);
}
fn getIrqTrigger() ?gpio_irq.IrqTrigger {
    var iter = gpio_irq.IrqEventIter{};
    return iter.next();
}

fn irqTimer() callconv(.c) void {
    timer.INTR.modify(.{.ALARM_0 = 1});
    _ = ir.onTimer() catch null;
}
fn setAlarm(target: microzig.drivers.time.Absolute) void {
    timer.ALARM0.write_raw(@intCast(target.to_us() & std.math.maxInt(u32)));
}

pub fn main() !void {
    const led = gpio.num(25);
    const ir_sensor = gpio.num(28);

    // Setup LED for blinking
    led.set_function(.sio);
    led.set_direction(.out);
    led.put(1);

    // Enable ir sensor interrupt
    ir_sensor.set_function(.sio);
    ir_sensor.set_direction(.in);
    ir_sensor.set_pull(.up);
    gpio_irq.set_irq_enabled(
        ir_sensor,
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
