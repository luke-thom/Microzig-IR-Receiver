const std = @import("std");
const microzig = @import("microzig");

const hal = microzig.hal;
const usb = hal.usb;
const hid = usb.hid;

const Absolute = microzig.drivers.time.Absolute;
const Duration = microzig.drivers.time.Duration;

pub const Reporter = struct {
    keycode: u16 = 0,
    keycode_expirery: Absolute = .from_us(0),
    state: enum {begin_press, pressed, unpressed} = .begin_press,

    pub fn press_key(self: *@This(), keycode: u16, time: Duration) void {
        const now = hal.time.get_time_since_boot();
        self.keycode_expirery = now.add_duration(time);
        self.keycode = keycode;
        self.state = .begin_press;
    }

    pub fn send_report(self: *@This(), usb_dev: type, now: Absolute) void {
        var report: [3]u8 = .{0x03, 0, 0}; // Report ID 3
        switch (self.state) {
            .begin_press => {
                self.state = .pressed;
                const keycodeLe = std.mem.nativeToLittle(u16, self.keycode);
                @memcpy(report[1..], std.mem.asBytes(&keycodeLe));
                usb_dev.callbacks.usb_start_tx(endpoint, &report);
            },
            .pressed => if (self.keycode_expirery.is_reached_by(now)) {
                self.state = .unpressed;
                usb_dev.callbacks.usb_start_tx(endpoint, &report);
            },
            .unpressed => {},
        }
    }
};

pub const endpoint = usb.Endpoint.to_address(1, .In);
const usb_packet_size = 64;

const ReportDescriptor = hid.hid_usage_page(1, .{0x0c}) ++
    hid.hid_usage(1, .{0x01}) ++
    hid.hid_collection(.Application) ++
    [2]u8{0x85, 0x03} ++ // Report ID 3
    hid.hid_usage_min(1, .{0x00}) ++
    hid.hid_usage_max(2, .{0x3c, 0x03}) ++
    hid.hid_logical_min(1, .{0}) ++
    hid.hid_logical_max(2, .{0x3c, 0x03}) ++
    hid.hid_report_count(1, .{0x01}) ++
    hid.hid_report_size(1, .{0x10}) ++
    hid.hid_input(hid.HID_DATA | hid.HID_ARRAY | hid.HID_ABSOLUTE) ++
    hid.hid_collection_end();


const usb_config_len = usb.templates.config_descriptor_len + usb.templates.hid_in_descriptor_len;
const usb_config_descriptor = usb.templates.config_descriptor(1, 1, 0, usb_config_len, 0x80, 500) ++
    (usb.types.InterfaceDescriptor{
        .interface_number = 1,
        .alternate_setting = 0,
        .num_endpoints = 1,
        .interface_class = 3,
        .interface_subclass = 0,
        .interface_protocol = 1,
        .interface_s = 4,
    }).serialize() ++
    (hid.HidDescriptor{
        .bcd_hid = 0x0111,
        .country_code = 0,
        .num_descriptors = 1,
        .report_length = ReportDescriptor.len,
    }).serialize() ++
    (usb.types.EndpointDescriptor{
        .endpoint_address = endpoint,
        .attributes = @intFromEnum(usb.types.TransferType.Interrupt),
        .max_packet_size = usb_packet_size,
        .interval = 10,
    }).serialize();

var driver = usb.hid.HidClassDriver{
    .ep_in = endpoint,
    .report_descriptor = &ReportDescriptor,
};

var drivers = [_]usb.types.UsbClassDriver{driver.driver()};

pub var DEVICE_CONFIGURATION: usb.DeviceConfiguration = .{
    .device_descriptor = &.{
        .descriptor_type = usb.DescType.Device,
        .bcd_usb = 0x0200,
        .device_class = 0,
        .device_subclass = 0,
        .device_protocol = 0,
        .max_packet_size0 = 64,
        .vendor = 0xFAFA,
        .product = 0x00F0,
        .bcd_device = 0x0100,
        // Those are indices to the descriptor strings (starting from 1)
        // Make sure to provide enough string descriptors!
        .manufacturer_s = 1,
        .product_s = 2,
        .serial_s = 3,
        .num_configurations = 1,
    },
    .config_descriptor = &usb_config_descriptor,
    .lang_descriptor = "\x04\x03\x09\x04", // length || string descriptor (0x03) || Engl (0x0409)
    .descriptor_strings = &.{
        &usb.utils.utf8_to_utf16_le("The Calculator"),
        &usb.utils.utf8_to_utf16_le("Pico IR"),
        &usb.utils.utf8_to_utf16_le("00000001"),
        &usb.utils.utf8_to_utf16_le("IR Reciver"),
    },
    .drivers = &drivers,
};
