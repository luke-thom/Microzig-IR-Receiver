const std = @import("std");
const microzig = @import("microzig");
const hal = microzig.hal;

const time = hal.time;
const gpio = hal.gpio;

const Absolute = microzig.drivers.time.Absolute;

pub const microzig_options = microzig.Options{
    .log_level = .debug,
    .logFn = hal.uart.log,
    .interrupts = .{.IO_IRQ_BANK0 = .{.c = irqCallbackTest}},
};

const uart = hal.uart.instance.num(0);

const uart_tx = gpio.num(0);
const led = gpio.num(25);
const ir = gpio.num(28);

var edges: [256]Absolute = undefined;
var edgeIndex: usize = 0;
fn irqCallback() linksection("._ram_text") callconv(.c) void {
    const now = time.get_time_since_boot();
    if (edgeIndex >= edges.len) return;
    edges[edgeIndex] = now;
    edgeIndex += 1;
}
// var last: Absolute = .from_us(0);
var shouldLog: bool = false;
fn irqCallbackTest() linksection("._ram_text") callconv(.c) void {
    //const now = time.get_time_since_boot();
    //last = now;
    //if (last.diff(now).to_us() < std.time.us_per_ms * 100) return;
    shouldLog = true;
    return;
}

pub fn main() !void {
    // init irq
    ir.set_function(.sio);
    ir.set_direction(.in);
    ir.set_pull(.up);
    ir.set_irq_enabled(.{ .rise =  1, .fall = 1}, true);
    microzig.interrupt.enable(.IO_IRQ_BANK0);

    // init uart
    uart_tx.set_function(.uart);
    uart.apply(.{.clock_config = hal.clock_config});
    hal.uart.init_logger(uart);

    //init led 
    led.set_direction(.out);
    led.set_function(.sio);

    // send list after 10 seconds
    //time.sleep_ms(1000 * 10);
    //var buffer: [16 * edges.len]u8 = undefined;
    //var writer = std.io.Writer.fixed(&buffer);
    //for (edges) |i| {
    //    writer.print("{}, ", .{i.to_us()}) catch {};
    //}
    //std.log.info("Begin list", .{});
    //std.log.info("{s}", .{writer.buffered()});

    while (true) {
        time.sleep_ms(250);
        led.toggle();
        if (shouldLog) {
            std.log.info("interrupt", .{});
            shouldLog = false;
        }
    }
}
