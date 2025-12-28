// Pi Pico GPIO IRQ impllementation not pressent in the 0.15.0

const microzig = @import("microzig");
const peripherals= microzig.chip.peripherals;
const gpio_ns = microzig.hal.gpio;
const hw = struct { // from hw.zig
    const clear_bits = @as(u32, 0x3) << 12;
    const set_bits = @as(u32, 0x2) << 12;
    /// Returns a base register offset by 0x3000 for its atomic clear on write equivalent address
    pub fn clear_alias_raw(ptr: anytype) *volatile u32 {
        return @ptrFromInt(@intFromPtr(ptr) | clear_bits);
    }

    /// Returns a base register offset by 0x2000 for its atomic set on write equivalent address
    pub fn set_alias_raw(ptr: anytype) *volatile u32 {
        return @ptrFromInt(@intFromPtr(ptr) | set_bits);
    }
};

const Pin = gpio_ns.Pin;

const IO_BANK0 = peripherals.IO_BANK0;
const NUM_BANK0_GPIOS = 30; // Sorry rp2350 incompatible;


/// Set or clear IRQ event enable for the input events
/// if enable=true irqs will be enabled for the events indicated
/// if enable=false irqs will be cleared for the events indicated
/// events not set in IrqEvents will not be changed
pub fn set_irq_enabled(gpio: Pin, events: IrqEvents, enable: bool) void {
    // most of this is adapted from the pico-sdk implementation.
    // Get correct register set (based on calling core)
    const core_num = microzig.hal.get_cpu_id();
    const irq_inte_base: [*]volatile u32 = switch (core_num) {
        0 => @ptrCast(&IO_BANK0.PROC0_INTE0),
        else => @ptrCast(&IO_BANK0.PROC1_INTE0),
    };

    // Clear stale events which might cause immediate spurious handler entry
    acknowledge_irq(gpio, events);

    // Enable or disable interrupts for events on this pin
    const pin_num = @intFromEnum(gpio);
    // Divide pin_num by 8 - 8 GPIOs per register.
    const en_reg: *volatile u32 = &irq_inte_base[pin_num >> 3];
    if (enable) {
        const inte0_set = hw.set_alias_raw(en_reg);
        inte0_set.* = events.get_mask(gpio);
    } else {
        const inte0_clear = hw.clear_alias_raw(en_reg);
        inte0_clear.* = events.get_mask(gpio);
    }
}
/// Acknowledge rise/fall IRQ events - should be called during IRQ callback to avoid re-entry
pub fn acknowledge_irq(gpio: Pin, events: IrqEvents) void {
    const base_intr: [*]volatile u32 = @ptrCast(&IO_BANK0.INTR0);
    const pin_num = @intFromEnum(gpio);
    base_intr[pin_num >> 3] = events.get_mask(gpio);
}

/// Helper intended to help identify the event(s) which triggered the interrupt.
/// If there is only one event enabled or if it doesn't matter which
/// event triggered the interrupt this search should not be needed.
/// Though rise/fall events would still need to be cleared (see `acknowledge_irq`)
/// Default values will ensure a full search, it's not recommended to alter them.
pub const IrqEventIter = struct {
    _base_gpio_num: u9 = 0,
    _allevents: u32 = 0,
    _gpio_num: u9 = 0,
    _events_b: u4 = 0,
    /// return the next IRQ event that triggered.
    /// Attempts to inline to minimize execution overhead during IRQ
    /// Acknowledge rise/fall events which have been triggered - calling acknowledge_irq.
    pub inline fn next(self: *IrqEventIter) ?IrqTrigger {
        const core_num = microzig.hal.get_cpu_id();
        const ints_base: [*]volatile u32 = switch (core_num) {
            0 => @ptrCast(&IO_BANK0.PROC0_INTS0),
            else => @ptrCast(&IO_BANK0.PROC1_INTS0),
        };
        // iterate through all INTS (interrupt status) registers
        while (self._base_gpio_num < NUM_BANK0_GPIOS) : (self._base_gpio_num += 8) {
            self._allevents = ints_base[self._base_gpio_num >> 3];
            self._gpio_num = self._base_gpio_num;
            // Loop through each of the 8 GPIO represented in an INTS register (4 bits at a time)
            while (self._allevents != 0) : (self._gpio_num += 1) {
                self._events_b = @truncate(self._allevents & 0xF);
                self._allevents = self._allevents >> 4;
                if (self._events_b != 0) {
                    acknowledge_irq(
                        gpio_ns.num(self._gpio_num),
                        @bitCast(self._events_b)
                    );
                    return .{
                        .pin = gpio_ns.num(self._gpio_num),
                        .events = @bitCast(self._events_b),
                    };
                }
            }
        }
        return null;
    }
};

/// Return type of the IrqEventIterator represents both the Pin and IrqEvents
pub const IrqTrigger = struct {
    pin: Pin,
    events: IrqEvents,
};

/// Event flags for gpio IRQ events
pub const IrqEvents = packed struct(u4) {
    low: u1 = 0,
    high: u1 = 0,
    fall: u1 = 0,
    rise: u1 = 0,
    /// Returns an appropriately shifted mask of the events represented
    /// This is generally only needed for low level - direct register - access
    pub fn get_mask(events: IrqEvents, pin: Pin) u32 {
        const pin_num = @intFromEnum(pin);
        const shift: u5 = @intCast(4 * (pin_num % 8)); // cannot overflow - max of 7
        const events_b: u4 = @bitCast(events);
        return @as(u32, @intCast(events_b)) << shift;
    }
};
