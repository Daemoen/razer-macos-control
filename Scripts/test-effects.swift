#!/usr/bin/env swift

// Test all RGB effects on connected Razer devices
// Run: swift Scripts/test-effects.swift
// Each effect is shown for 2 seconds

import Foundation
import IOKit
import IOKit.hid

let RAZER_VID: Int = 0x1532

func makePacket(txId: UInt8, cmdClass: UInt8, cmdId: UInt8, args: [UInt8]) -> [UInt8] {
    var pkt = [UInt8](repeating: 0, count: 90)
    pkt[1] = txId
    pkt[5] = UInt8(args.count)
    pkt[6] = cmdClass
    pkt[7] = cmdId
    for (i, a) in args.enumerated() where i < 80 { pkt[8 + i] = a }
    var crc: UInt8 = 0
    for i in 2...87 { crc ^= pkt[i] }
    pkt[88] = crc
    return pkt
}

func sendAndCheck(_ iface: IOHIDDevice, _ pkt: [UInt8]) -> (Bool, UInt8) {
    let r = IOHIDDeviceSetReport(iface, kIOHIDReportTypeFeature, 0, pkt, 90)
    guard r == kIOReturnSuccess else { return (false, 0) }
    usleep(100_000)
    var resp = [UInt8](repeating: 0, count: 90)
    var len = 90
    let rr = IOHIDDeviceGetReport(iface, kIOHIDReportTypeFeature, 0, &resp, &len)
    guard rr == kIOReturnSuccess else { return (false, 0) }
    return (true, resp[0])
}

// Setup HID
let mgr = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey: RAZER_VID] as CFDictionary)
IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(mgr, 0)

guard let devSet = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> else {
    print("No devices"); exit(0)
}

// Group interfaces by PID
var byPID: [Int: [(IOHIDDevice, Int, Int)]] = [:] // PID -> [(device, usagePage, usage)]
for d in devSet {
    let pid = IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) as? Int ?? 0
    let up = IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
    let u = IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
    byPID[pid, default: []].append((d, up, u))
}

// Test effects on each device
struct Effect {
    let name: String
    let proto: String  // "std" or "ext"
    let args: [UInt8]
}

let extEffects: [Effect] = [
    Effect(name: "Static Red",      proto: "ext", args: [0x01, 0x05, 0x01, 0x00, 0x00, 0x01, 0xFF, 0x00, 0x00]),
    Effect(name: "Static Green",    proto: "ext", args: [0x01, 0x05, 0x01, 0x00, 0x00, 0x01, 0x00, 0xFF, 0x00]),
    Effect(name: "Static Blue",     proto: "ext", args: [0x01, 0x05, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0xFF]),
    Effect(name: "Breathing Green", proto: "ext", args: [0x01, 0x05, 0x02, 0x01, 0x00, 0x01, 0x00, 0xFF, 0x00]),
    Effect(name: "Spectrum",        proto: "ext", args: [0x01, 0x05, 0x03]),
    Effect(name: "Wave →",          proto: "ext", args: [0x01, 0x05, 0x04, 0x00, 0x00, 0x28, 0x01]),
    Effect(name: "Wave ←",          proto: "ext", args: [0x01, 0x05, 0x04, 0x00, 0x00, 0x28, 0x02]),
    Effect(name: "Off",             proto: "ext", args: [0x01, 0x05, 0x00]),
]

let stdEffects: [Effect] = [
    Effect(name: "Static Red",      proto: "std", args: [0x06, 0xFF, 0x00, 0x00]),
    Effect(name: "Wave →",          proto: "std", args: [0x01, 0x01]),
    Effect(name: "Spectrum",        proto: "std", args: [0x04]),
    Effect(name: "Breathing Green", proto: "std", args: [0x03, 0x01, 0x00, 0xFF, 0x00, 0, 0, 0]),
    Effect(name: "Off",             proto: "std", args: [0x00]),
]

let knownDevices: [Int: (String, UInt8)] = [
    0x028D: ("BlackWidow V4 Pro", 0x1F),
    0x00C7: ("Pro Click V2 Vertical (Wired)", 0x3F),
    0x00C8: ("Pro Click V2 Vertical (Wireless)", 0x3F),
]

print("═══════════════════════════════════════════")
print("  RGB Effect Tester")
print("  Each effect shown for 2 seconds")
print("═══════════════════════════════════════════")
print()

for (pid, interfaces) in byPID.sorted(by: { $0.key < $1.key }) {
    let (deviceName, txId) = knownDevices[pid] ?? ("Unknown (0x\(String(format: "%04X", pid)))", 0xFF)
    print("Device: \(deviceName) (\(interfaces.count) interfaces)")

    // Find working interface for this device
    var workingIface: IOHIDDevice? = nil
    var workingDesc = ""

    for (iface, up, u) in interfaces {
        IOHIDDeviceOpen(iface, 0)
        // Test with firmware query
        let pkt = makePacket(txId: txId, cmdClass: 0x00, cmdId: 0x81, args: [0x00, 0x00])
        let (ok, status) = sendAndCheck(iface, pkt)
        if ok && status == 0x02 {
            workingIface = iface
            workingDesc = "UP:\(String(format: "0x%04X", up)) U:\(String(format: "0x%04X", u))"
            break
        }
    }

    // If firmware query didn't find one, try all with a simple static command
    if workingIface == nil {
        for (iface, up, u) in interfaces {
            IOHIDDeviceOpen(iface, 0)
            // Try extended static
            let pkt = makePacket(txId: txId, cmdClass: 0x0F, cmdId: 0x02,
                                 args: [0x01, 0x05, 0x01, 0x00, 0x00, 0x01, 0xFF, 0x00, 0x00])
            let (ok, status) = sendAndCheck(iface, pkt)
            if ok && status == 0x02 {
                workingIface = iface
                workingDesc = "UP:\(String(format: "0x%04X", up)) U:\(String(format: "0x%04X", u))"
                break
            }
            // Try standard static
            let pkt2 = makePacket(txId: txId, cmdClass: 0x03, cmdId: 0x0A, args: [0x06, 0xFF, 0x00, 0x00])
            let (ok2, status2) = sendAndCheck(iface, pkt2)
            if ok2 && status2 == 0x02 {
                workingIface = iface
                workingDesc = "UP:\(String(format: "0x%04X", up)) U:\(String(format: "0x%04X", u))"
                break
            }
        }
    }

    guard let iface = workingIface else {
        print("  ❌ No working interface found\n")
        // Try all txIds on all interfaces
        print("  Trying all txId combos...")
        for txTry: UInt8 in [0x1F, 0xFF, 0x3F, 0x9F, 0x00] {
            for (ifaceTry, up, u) in interfaces {
                IOHIDDeviceOpen(ifaceTry, 0)
                let pkt = makePacket(txId: txTry, cmdClass: 0x0F, cmdId: 0x02,
                                     args: [0x01, 0x05, 0x01, 0x00, 0x00, 0x01, 0xFF, 0x00, 0x00])
                let (ok, status) = sendAndCheck(ifaceTry, pkt)
                if ok && status == 0x02 {
                    print("  ✅ FOUND: txId=0x\(String(format: "%02X", txTry)) [UP:\(String(format: "0x%04X", up)) U:\(String(format: "0x%04X", u))]")
                }
                let pkt2 = makePacket(txId: txTry, cmdClass: 0x03, cmdId: 0x0A, args: [0x06, 0xFF, 0x00, 0x00])
                let (ok2, status2) = sendAndCheck(ifaceTry, pkt2)
                if ok2 && status2 == 0x02 {
                    print("  ✅ FOUND (std): txId=0x\(String(format: "%02X", txTry)) [UP:\(String(format: "0x%04X", up)) U:\(String(format: "0x%04X", u))]")
                }
            }
        }
        print()
        continue
    }

    print("  Working interface: \(workingDesc)")
    print()

    // Test extended effects
    print("  Extended protocol (class 0x0F, cmd 0x02):")
    for effect in extEffects {
        let pkt = makePacket(txId: txId, cmdClass: 0x0F, cmdId: 0x02, args: effect.args)
        let (ok, status) = sendAndCheck(iface, pkt)
        let result = ok ? (status == 0x02 ? "✅" : "⚠️  status=0x\(String(format: "%02X", status))") : "❌ send failed"
        print("    \(effect.name): \(result)")
        if ok && status == 0x02 { sleep(2) }
    }

    // Test standard effects
    print("  Standard protocol (class 0x03, cmd 0x0A):")
    for effect in stdEffects {
        let pkt = makePacket(txId: txId, cmdClass: 0x03, cmdId: 0x0A, args: effect.args)
        let (ok, status) = sendAndCheck(iface, pkt)
        let result = ok ? (status == 0x02 ? "✅" : "⚠️  status=0x\(String(format: "%02X", status))") : "❌ send failed"
        print("    \(effect.name): \(result)")
        if ok && status == 0x02 { sleep(2) }
    }

    print()
}

IOHIDManagerClose(mgr, 0)
print("Done! Check your devices for color changes.")
