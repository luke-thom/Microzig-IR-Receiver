const std = @import("std");
const microzig = @import("microzig");

const usb = microzig.core.usb;
const hal = microzig.hal;

const UsbSerial = usb.drivers.cdc.CdcClassDriver(.{.max_packet_size = 64});

pub var usb_dev: hal.usb.Polled(
    usb.Config{
        .device_descriptor = .{
            .bcd_usb = .from(0x0200),
            .device_triple = .{
                .class = .Miscellaneous,
                .subclass = 2,
                .protocol = 1,
            },
            .max_packet_size0 = 64,
            .vendor = .from(0x2E8A),
            .product = .from(0x000A),
            .bcd_device = .from(0x0100),
            .manufacturer_s = 1,
            .product_s = 2,
            .serial_s = 3,
            .num_configurations = 1,
        },
        .string_descriptors = &.{
            .from_lang(.English),
            .from_str("Raspberry Pi"),
            .from_str("Pico Test Device"),
            .from_str("someserial"),
            .from_str("Board CDC"),
        },
        .configurations = &.{.{
            .num = 1,
            .configuration_s = 0,
            .attributes = .{ .self_powered = true },
            .max_current_ma = 100,
            .Drivers = struct { serial: UsbSerial },
        }},
    },
    .{},
) = undefined;

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype
) void {
    const drivers = usb_dev.controller.drivers() orelse return;
    const serial = &drivers.serial;
    const level_txt = comptime level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    nosuspend writer.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
    var toWrite: []const u8 = writer.buffered();
    while (toWrite.len > 0) {
        toWrite = serial.write(toWrite);
        _ = serial.write_flush();
        hal.time.sleep_ms(100);
        usb_dev.poll();
        hal.time.sleep_ms(100);
    }
}

pub fn init() void {
    usb_dev = .init();
    const drivers = usb_dev.controller.drivers() orelse return;
    const serial = &drivers.serial;
    _ = serial.write("=== Begin Log ===\n");
    usb_dev.poll();
}

pub fn poll() void {
    usb_dev.poll();
}
