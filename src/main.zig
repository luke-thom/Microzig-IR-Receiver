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

const system_timer = hal.system_timer.num(0);

const led = gpio.num(25);
const button = gpio.num(28);

const transmssion_time = std.time.us_per_s;

var ticks: [256]Absolote = undefined;
var tick_index: usize = 0;
fn irqGPIO() linksection(".ram_text") callconv(.c) void {
    _ = getIrqTrigger(); // Clear event 
    const now  = time.get_time_since_boot();
    const is_first = now.diff(ticks[0]).to_us() > transmssion_time;
    if (is_first) {
        system_timer.schedule_alarm(
            .alarm0,
            system_timer.read_low() +% transmssion_time,
        );
        tick_index = 0;
    }
    if (tick_index > ticks.len) return;
    ticks[tick_index] = now;
    tick_index += 1;
}
fn getIrqTrigger() ?gpio.IrqTrigger {
    var iter = gpio.IrqEventIter{};
    return iter.next();
}

fn irqTimer() callconv(.c) void {
    const cs = microzig.interrupt.enter_critical_section();
    defer cs.leave();
    system_timer.clear_interrupt(.alarm0);
    var buffer: [8 * ticks.len]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    for (ticks[0..tick_index], 0..) |t, i| {
        writer.print("({}, {}), ", .{i, @intFromEnum(t)}) catch {};
    }
    std.log.debug("{s}", .{writer.buffered()});
    std.log.debug("Counted {} ticks", .{tick_index});
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
