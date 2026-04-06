#!/usr/bin/env swift

// Test which LED IDs work on Pro Click V2 Vertical
import Foundation
import IOKit
import IOKit.hid

let RAZER_VID: Int = 0x1532
let MOUSE_PID: Int = 0x00C8
let TX_ID: UInt8 = 0x3F

func makePacket(txId: UInt8, cmdClass: UInt8, cmdId: UInt8, args: [UInt8]) -> [UInt8] {
    var pkt = [UInt8](repeating: 0, count: 90)
    pkt[1] = txId; pkt[5] = UInt8(args.count); pkt[6] = cmdClass; pkt[7] = cmdId
    for (i, a) in args.enumerated() where i < 80 { pkt[8 + i] = a }
    var crc: UInt8 = 0; for i in 2...87 { crc ^= pkt[i] }; pkt[88] = crc
    return pkt
}

func send(_ iface: IOHIDDevice, _ pkt: [UInt8]) -> (Bool, UInt8) {
    let r = IOHIDDeviceSetReport(iface, kIOHIDReportTypeFeature, 0, pkt, 90)
    guard r == kIOReturnSuccess else { return (false, 0) }
    usleep(100_000)
    var resp = [UInt8](repeating: 0, count: 90); var len = 90
    let rr = IOHIDDeviceGetReport(iface, kIOHIDReportTypeFeature, 0, &resp, &len)
    guard rr == kIOReturnSuccess else { return (false, 0) }
    return (true, resp[0])
}

let mgr = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey: RAZER_VID, kIOHIDProductIDKey: MOUSE_PID] as CFDictionary)
IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(mgr, 0)

guard let devSet = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> else { print("No mouse"); exit(0) }

// Find working interface (the one that responds to firmware query)
var workIface: IOHIDDevice? = nil
for d in devSet {
    IOHIDDeviceOpen(d, 0)
    let pkt = makePacket(txId: TX_ID, cmdClass: 0x00, cmdId: 0x81, args: [0x00, 0x00])
    let (ok, st) = send(d, pkt)
    if ok && st == 0x02 {
        workIface = d
        let up = IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let u = IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        print("Working interface: UP:\(String(format: "0x%04X", up)) U:\(String(format: "0x%04X", u))")
        break
    }
}

// Also try all txIds if 0x3F didn't work
if workIface == nil {
    print("txId 0x3F didn't work, trying others...")
    for txTry: UInt8 in [0xFF, 0x1F, 0x9F, 0x00] {
        for d in devSet {
            IOHIDDeviceOpen(d, 0)
            let pkt = makePacket(txId: txTry, cmdClass: 0x00, cmdId: 0x81, args: [0x00, 0x00])
            let (ok, st) = send(d, pkt)
            if ok && st == 0x02 {
                workIface = d
                print("Found with txId: 0x\(String(format: "%02X", txTry))")
                break
            }
        }
        if workIface != nil { break }
    }
}

guard let iface = workIface else { print("No working interface found for mouse"); exit(1) }

print()
print("Testing LED IDs with static red (extended protocol):")
print()

// LED IDs to test
let ledIds: [(String, UInt8)] = [
    ("none", 0x00), ("scroll_wheel", 0x01), ("battery", 0x03),
    ("logo", 0x04), ("backlight", 0x05), ("macro", 0x07),
    ("game/left", 0x08), ("right", 0x09), ("underglow", 0x0A),
    ("charging", 0x20), ("fast_charging", 0x21), ("fully_charged", 0x22),
]

for (name, ledId) in ledIds {
    // Extended static: storage=0x01, led=X, effect=0x01(static), params, R,G,B
    let args: [UInt8] = [0x01, ledId, 0x01, 0x00, 0x00, 0x01, 0xFF, 0x00, 0x00]
    let pkt = makePacket(txId: TX_ID, cmdClass: 0x0F, cmdId: 0x02, args: args)
    let (ok, status) = send(iface, pkt)
    let result = ok ? (status == 0x02 ? "✅ SUCCESS" : "status=0x\(String(format: "%02X", status))") : "send failed"
    print("  LED 0x\(String(format: "%02X", ledId)) (\(name)): \(result)")
    if ok && status == 0x02 { sleep(1) }
}

// Also test with storage=0x00 (no store)
print()
print("Testing with storage=0x00 (no store):")
for (name, ledId) in [("scroll_wheel", UInt8(0x01)), ("logo", UInt8(0x04)), ("underglow", UInt8(0x0A))] {
    let args: [UInt8] = [0x00, ledId, 0x01, 0x00, 0x00, 0x01, 0xFF, 0x00, 0x00]
    let pkt = makePacket(txId: TX_ID, cmdClass: 0x0F, cmdId: 0x02, args: args)
    let (ok, status) = send(iface, pkt)
    let result = ok ? (status == 0x02 ? "✅ SUCCESS" : "status=0x\(String(format: "%02X", status))") : "send failed"
    print("  LED 0x\(String(format: "%02X", ledId)) (\(name)): \(result)")
    if ok && status == 0x02 { sleep(1) }
}

// Test mouse-specific extended protocol (class 0x03, cmd 0x0D)
print()
print("Testing mouse extended protocol (class 0x03, cmd 0x0D):")
let mouseEffects: [(String, [UInt8])] = [
    ("Static Red", [0x01, 0x05, 0x01, 0x00, 0x00, 0x01, 0xFF, 0x00, 0x00]),
    ("Static Red (logo)", [0x01, 0x04, 0x01, 0x00, 0x00, 0x01, 0xFF, 0x00, 0x00]),
    ("Spectrum", [0x01, 0x05, 0x04]),
]
for (name, args) in mouseEffects {
    let pkt = makePacket(txId: TX_ID, cmdClass: 0x03, cmdId: 0x0D, args: args)
    let (ok, status) = send(iface, pkt)
    let result = ok ? (status == 0x02 ? "✅ SUCCESS" : "status=0x\(String(format: "%02X", status))") : "send failed"
    print("  \(name): \(result)")
    if ok && status == 0x02 { sleep(1) }
}

IOHIDManagerClose(mgr, 0)
print()
print("Done!")
