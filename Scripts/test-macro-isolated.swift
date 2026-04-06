#!/usr/bin/env swift

// Isolated macro key diagnostic
// Listens ONLY on vendor-specific interfaces (UsagePage 0x0059)
// Filters out Command Dial noise, shows only unique events
//
// Run: swift Scripts/test-macro-isolated.swift

import Foundation
import IOKit
import IOKit.hid
import CoreGraphics
import ApplicationServices

let RAZER_VID: Int = 0x1532
let BW_PID: Int = 0x028D

print("═══════════════════════════════════════════")
print("  MACRO KEY DIAGNOSTIC (isolated 0x0059)")
print("═══════════════════════════════════════════")

// Setup
let mgr = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey: RAZER_VID, kIOHIDProductIDKey: BW_PID] as CFDictionary)
IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(mgr, 0)

guard let devSet = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> else {
    print("No devices found"); exit(1)
}

// Step 1: Send driver mode init on the working interface (0x0001, Usage 0x0000)
print("\n1. Sending driver mode init...")
for d in devSet {
    let up = IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
    let u = IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
    guard up == 0x0001 && u == 0x0000 else { continue }
    IOHIDDeviceOpen(d, 0)

    var pkt = [UInt8](repeating: 0, count: 90)
    pkt[1] = 0x1F; pkt[5] = 0x02; pkt[6] = 0x00; pkt[7] = 0x04
    pkt[8] = 0x03; pkt[9] = 0x00 // driver mode
    var crc: UInt8 = 0; for i in 2...87 { crc ^= pkt[i] }; pkt[88] = crc

    let r = IOHIDDeviceSetReport(d, kIOHIDReportTypeFeature, 0, pkt, 90)
    usleep(200_000)
    if r == kIOReturnSuccess {
        var resp = [UInt8](repeating: 0, count: 90); var l = 90
        IOHIDDeviceGetReport(d, kIOHIDReportTypeFeature, 0, &resp, &l)
        print("   Driver mode: status=0x\(String(format: "%02X", resp[0]))")
    }
}

// Step 2: Collect ONLY vendor-specific interfaces (0x0059)
var vendorInterfaces: [(IOHIDDevice, Int)] = [] // (device, usage)
print("\n2. Vendor interfaces (UsagePage 0x0059):")
for d in devSet {
    let up = IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
    let u = IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
    if up == 0x0059 {
        vendorInterfaces.append((d, u))
        print("   [UP:0x0059 U:\(String(format: "0x%04X", u))]")
    }
}

// Also collect ALL other interfaces for comparison
var otherInterfaces: [(IOHIDDevice, Int, Int)] = []
for d in devSet {
    let up = IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
    let u = IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
    if up != 0x0059 {
        otherInterfaces.append((d, up, u))
    }
}

if vendorInterfaces.isEmpty {
    print("   ❌ No vendor-specific interfaces found!")
    exit(1)
}

// Step 3: Record baseline (silence) then macro key presses
// Collect raw events with timestamps
var events: [(Double, Int, Int, Int)] = [] // (time, usagePage, usage, value)
let startTime = Date()

let callback: IOHIDValueCallback = { context, result, sender, value in
    let element = IOHIDValueGetElement(value)
    let usagePage = Int(IOHIDElementGetUsagePage(element))
    let usage = Int(IOHIDElementGetUsage(element))
    let intValue = IOHIDValueGetIntegerValue(value)
    let elapsed = Date().timeIntervalSince(Date(timeIntervalSinceReferenceDate: 0))

    // Print ALL events with raw details
    let reportID = IOHIDElementGetReportID(element)
    let reportSize = IOHIDElementGetReportSize(element)
    let type = IOHIDElementGetType(element)

    print("  t=\(String(format: "%.1f", Date().timeIntervalSinceNow + 100))s page=\(String(format: "0x%04X", usagePage)) usage=\(String(format: "0x%08X", usage)) val=\(intValue) reportID=\(reportID) bits=\(reportSize) type=\(type.rawValue)")
}

// Register ONLY on vendor interfaces
print("\n3. Registering input callbacks on vendor interfaces ONLY...")
for (d, _) in vendorInterfaces {
    IOHIDDeviceOpen(d, 0)
    IOHIDDeviceRegisterInputValueCallback(d, callback, nil)
    IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
}

print("\n4. BASELINE: Hands OFF keyboard for 3 seconds...")
CFRunLoopRunInMode(.defaultMode, 3, false)

print("\n5. Press M1 ONE time and release (3 seconds)...")
CFRunLoopRunInMode(.defaultMode, 3, false)

print("\n6. Press M2 ONE time and release (3 seconds)...")
CFRunLoopRunInMode(.defaultMode, 3, false)

print("\n7. Press M3 ONE time and release (3 seconds)...")
CFRunLoopRunInMode(.defaultMode, 3, false)

print("\n8. Press a NORMAL key (like 'A') for comparison (3 seconds)...")
CFRunLoopRunInMode(.defaultMode, 3, false)

// Reset to normal mode
print("\n9. Resetting to normal mode...")
for d in devSet {
    let up = IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
    let u = IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
    if up == 0x0001 && u == 0x0000 {
        var pkt = [UInt8](repeating: 0, count: 90)
        pkt[1] = 0x1F; pkt[5] = 0x02; pkt[6] = 0x00; pkt[7] = 0x04
        pkt[8] = 0x00; pkt[9] = 0x00
        var crc: UInt8 = 0; for i in 2...87 { crc ^= pkt[i] }; pkt[88] = crc
        IOHIDDeviceSetReport(d, kIOHIDReportTypeFeature, 0, pkt, 90)
    }
}

IOHIDManagerClose(mgr, 0)
print("\nDone!")
