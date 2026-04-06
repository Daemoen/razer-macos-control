#!/usr/bin/env swift

// RazerControl Hardware Diagnostic
// Run: swift Scripts/diagnose.swift
//
// Tests IOKit device discovery, USB communication, and permissions
// without needing the full app. Connect your Razer device via USB first.

import Foundation
import IOKit
import IOKit.hid
import CoreGraphics
import ApplicationServices

let RAZER_VENDOR_ID: Int = 0x1532

print("═══════════════════════════════════════════════")
print("  RazerControl Hardware Diagnostic")
print("═══════════════════════════════════════════════")
print()

// MARK: - Step 1: Find Razer devices

print("1. Scanning for Razer USB devices...")
print()

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matchDict: [String: Any] = [kIOHIDVendorIDKey: RAZER_VENDOR_ID]
IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
guard openResult == kIOReturnSuccess else {
    print("   ❌ Failed to open HID Manager: \(String(format: "0x%08X", openResult))")
    print("   This usually means a permissions issue.")
    exit(1)
}

guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
    print("   ⚠️  No Razer devices found.")
    print("   Make sure your device is connected via USB (not Bluetooth).")
    exit(0)
}

print("   ✅ Found \(deviceSet.count) Razer USB interface(s)")
print()

// MARK: - Step 2: List devices

print("2. Device details:")
print()

var primaryDevice: IOHIDDevice? = nil

for device in deviceSet {
    let vid = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
    let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
    let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
    let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String ?? ""
    let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
    let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0

    print("   Device: \(name)")
    print("   VID: \(String(format: "0x%04X", vid))  PID: \(String(format: "0x%04X", pid))")
    print("   Serial: \(serial.isEmpty ? "(none)" : serial)")
    print("   Usage Page: \(String(format: "0x%04X", usagePage))  Usage: \(String(format: "0x%04X", usage))")

    // Known device check
    let knownDevices: [Int: String] = [
        0x028D: "BlackWidow V4 Pro",
        0x028E: "BlackWidow V4 75%",
        0x028C: "BlackWidow V4",
        0x00C7: "Pro Click V2 Vertical (Wired)",
        0x00C8: "Pro Click V2 Vertical (Wireless)",
    ]
    if let known = knownDevices[pid] {
        print("   ✅ Known device: \(known)")
    } else {
        print("   ⚠️  Unknown PID — may need to add to DeviceDatabase")
    }
    print()

    // Use the first device with generic desktop usage page for testing
    if usagePage == 0x01 && (usage == 0x06 || usage == 0x02) {
        primaryDevice = device
    }
}

// MARK: - Step 3: Test each BlackWidow interface with firmware query

print("3. Testing firmware query on each BlackWidow V4 Pro interface...")
print()

let txIds: [(String, UInt8)] = [("0x1F (V4 KB)", 0x1F), ("0xFF (std)", 0xFF), ("0x3F (mouse)", 0x3F)]
var foundFirmware = false

for device in deviceSet {
    let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
    let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
    let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
    let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "?"

    let openRes = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openRes == kIOReturnSuccess else { continue }

    for (txLabel, txId) in txIds {
        var packet = [UInt8](repeating: 0, count: 90)
        packet[1] = txId
        packet[5] = 0x02
        packet[6] = 0x00  // device class
        packet[7] = 0x81  // get firmware version

        var crc: UInt8 = 0
        for i in 2...87 { crc ^= packet[i] }
        packet[88] = crc

        let sendRes = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, packet, 90)
        guard sendRes == kIOReturnSuccess else { continue }

        usleep(100_000)

        var response = [UInt8](repeating: 0, count: 90)
        var responseLen = 90
        let readRes = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, &response, &responseLen)
        guard readRes == kIOReturnSuccess else { continue }

        let status = response[0]
        if status == 0x02 {
            let major = response[9]
            let minor = response[10]
            print("   ✅ \(name) [UP:\(String(format: "0x%04X", usagePage)) U:\(String(format: "0x%04X", usage))] txId=\(txLabel)")
            print("      Firmware: v\(major).\(minor)")
            foundFirmware = true
        }
    }

    IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
}

if !foundFirmware {
    print("   ⚠️  No interface returned firmware version. This is normal for some interfaces.")
    print("   The device still responds to SetReport/GetReport on most interfaces.")
}

// MARK: - Step 4: Test RGB (static green) on BlackWidow

print()
print("4. Testing RGB command (static green) on BlackWidow V4 Pro...")
print("   (Your keyboard should flash green briefly)")
print()

for device in deviceSet {
    let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
    guard pid == 0x028D else { continue }

    let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
    let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0

    let openRes = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openRes == kIOReturnSuccess else { continue }

    // Extended static green: class=0x0F, cmd=0x02
    for txId: UInt8 in [0x1F, 0xFF] {
        var pkt = [UInt8](repeating: 0, count: 90)
        pkt[1] = txId
        pkt[5] = 0x09                // data size
        pkt[6] = 0x0F                // extended class
        pkt[7] = 0x02                // set effect
        pkt[8] = 0x01                // variable store
        pkt[9] = 0x05                // backlight LED
        pkt[10] = 0x01               // static effect
        pkt[11] = 0x00; pkt[12] = 0x00; pkt[13] = 0x01 // params
        pkt[14] = 0x00               // R
        pkt[15] = 0xFF               // G
        pkt[16] = 0x00               // B

        var crc2: UInt8 = 0
        for i in 2...87 { crc2 ^= pkt[i] }
        pkt[88] = crc2

        let res = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, pkt, 90)
        if res == kIOReturnSuccess {
            usleep(100_000)
            var resp = [UInt8](repeating: 0, count: 90)
            var respLen = 90
            let rr = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, &resp, &respLen)
            let st = resp[0]
            print("   Interface [UP:\(String(format: "0x%04X", usagePage)) U:\(String(format: "0x%04X", usage))] txId=\(String(format: "0x%02X", txId)): send=OK read=\(rr == kIOReturnSuccess ? "OK" : "FAIL") status=\(String(format: "0x%02X", st))\(st == 0x02 ? " ✅ SUCCESS" : "")")
            if st == 0x02 {
                break // found working combo
            }
        }
    }

    IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
}

// MARK: - Step 5: Check permissions

print()
print("5. Permission check...")
print()

// Accessibility
let axTrusted = AXIsProcessTrusted()
print("   Accessibility: \(axTrusted ? "✅ Granted" : "❌ Not granted (needed for key remapping)")")

// Input Monitoring
if #available(macOS 10.15, *) {
    let imAccess = CGPreflightListenEventAccess()
    print("   Input Monitoring: \(imAccess ? "✅ Granted" : "❌ Not granted (needed for key capture)")")
}

print("   RGB Lighting: ✅ No permission needed")

// Close
IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))

print()
print("═══════════════════════════════════════════════")
print("  Diagnostic complete")
print("═══════════════════════════════════════════════")
print()
print("Next steps:")
print("  1. If device found → run:  swift run RazerControl")
print("  2. If permissions missing → grant in System Settings")
print("  3. If SetReport failed → open a GitHub issue with this output")
