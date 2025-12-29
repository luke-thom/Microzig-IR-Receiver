const std = @import("std");
const microzig = @import("microzig");

const hal = microzig.hal;
const usb = hal.usb;

pub fn Logger(usb_dev: type) type {
    return struct {
        const UsbSerial = usb.cdc.CdcClassDriver(usb_dev);

        const usb_config_len = usb.templates.config_descriptor_len + usb.templates.cdc_descriptor_len;
        const usb_config_descriptor =
            usb.templates.config_descriptor(1, 2, 0, usb_config_len, 0xc0, 100) ++
            usb.templates.cdc_descriptor(0, 4, usb.Endpoint.to_address(1, .In), 8, usb.Endpoint.to_address(2, .Out), usb.Endpoint.to_address(2, .In), 64);

        var driver_cdc: usb.cdc.CdcClassDriver(usb_dev) = .{};
        var drivers = [_]usb.types.UsbClassDriver{driver_cdc.driver()};

        pub var DEVICE_CONFIGURATION: usb.DeviceConfiguration = .{
            .device_descriptor = &.{
                .descriptor_type = usb.types.DescType.Device,
                .bcd_usb = 0x0200,
                .device_class = 0xEF,
                .device_subclass = 2,
                .device_protocol = 1,
                .max_packet_size0 = 64,
                .vendor = 0x2E8A,
                .product = 0x000a,
                .bcd_device = 0x0100,
                .manufacturer_s = 1,
                .product_s = 2,
                .serial_s = 0,
                .num_configurations = 1,
            },
            .config_descriptor = &usb_config_descriptor,
            .lang_descriptor = "\x04\x03\x09\x04", // length || string descriptor (0x03) || Engl (0x0409)
            .descriptor_strings = &.{
                &usb.utils.utf8_to_utf16_le("Raspberry Pi"),
                &usb.utils.utf8_to_utf16_le("Pico Test Device"),
                &usb.utils.utf8_to_utf16_le("Display IR commands"),
                &usb.utils.utf8_to_utf16_le("Board CDC"),
            },
            .drivers = &drivers,
        };

        pub fn log(
            comptime level: std.log.Level,
            comptime scope: @Type(.enum_literal),
            comptime format: []const u8,
            args: anytype
        ) void {
            const serial = &driver_cdc;
            const level_txt = comptime level.asText();
            const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
            var buffer: [4096]u8 = undefined;
            var writer = std.Io.Writer.fixed(&buffer);
            nosuspend writer.print(level_txt ++ prefix2 ++ format ++ "\r\n", args) catch return;
            var toWrite: []const u8 = writer.buffered();
            while (toWrite.len > 0) {
                toWrite = serial.write(toWrite);
                _ = serial.write_flush();
                hal.time.sleep_ms(100);
                usb_dev.task(false) catch unreachable;
                hal.time.sleep_ms(100);
            }
        }
    };
}

