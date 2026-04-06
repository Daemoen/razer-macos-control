import Testing
@testable import RazerControl

@Suite("DeviceDatabase")
struct DeviceDatabaseTests {

    @Test("BlackWidow V4 Pro is in database")
    func blackwidowV4Pro() {
        let device = DeviceDatabase.shared.lookup(pid: 0x028D)
        #expect(device != nil)
        #expect(device?.name == "BlackWidow V4 Pro")
        #expect(device?.type == .keyboard)
        #expect(device?.protocolVersion == .extended)
        #expect(device?.transactionId == 0x1F)
        #expect(device?.macroKeyCount == 8)
        #expect(device?.hasDial == true)
        #expect(device?.hasRoller == true)
    }

    @Test("Pro Click V2 Vertical wired is in database")
    func proClickV2Wired() {
        let device = DeviceDatabase.shared.lookup(pid: 0x00C7)
        #expect(device != nil)
        #expect(device?.name == "Pro Click V2 Vertical Edition")
        #expect(device?.type == .mouse)
        #expect(device?.dpiMax == 35000)
        #expect(device?.buttonCount == 6)
    }

    @Test("Pro Click V2 Vertical wireless is in database")
    func proClickV2Wireless() {
        let device = DeviceDatabase.shared.lookup(pid: 0x00C8)
        #expect(device != nil)
        #expect(device?.name.contains("Wireless") == true)
        #expect(device?.type == .mouse)
    }

    @Test("Unknown PID returns nil")
    func unknownPID() {
        let device = DeviceDatabase.shared.lookup(pid: 0xFFFF)
        #expect(device == nil)
    }

    @Test("All devices have Razer vendor ID implied")
    func allDevicesValid() {
        let all = DeviceDatabase.shared.allDevices()
        #expect(all.count >= 39)

        for device in all {
            #expect(device.pid != 0, "Device \(device.name) has PID 0")
            #expect(!device.name.isEmpty, "Device has empty name")
            #expect(device.transactionId != 0, "Device \(device.name) has txId 0")
        }
    }

    @Test("Keyboards have matrix dimensions")
    func keyboardsHaveMatrix() {
        let keyboards = DeviceDatabase.shared.devices(ofType: .keyboard)
        #expect(keyboards.count >= 20)

        for kb in keyboards {
            #expect(kb.matrixDims != nil, "\(kb.name) missing matrix dims")
            if let dims = kb.matrixDims {
                #expect(dims.rows > 0 && dims.cols > 0, "\(kb.name) has invalid matrix: \(dims)")
            }
        }
    }

    @Test("Mice with DPI have valid max DPI")
    func miceHaveDPI() {
        let mice = DeviceDatabase.shared.devices(ofType: .mouse)
        #expect(mice.count >= 10)

        for mouse in mice {
            if mouse.features.contains(.dpiControl) {
                #expect(mouse.dpiMax != nil, "\(mouse.name) has DPI control but no dpiMax")
                if let max = mouse.dpiMax {
                    #expect(max >= 800 && max <= 50000, "\(mouse.name) dpiMax \(max) out of range")
                }
            }
        }
    }

    @Test("Devices with macro keys have count > 0")
    func macroKeyCount() {
        let all = DeviceDatabase.shared.allDevices()
        for device in all {
            if device.features.contains(.macroKeys) {
                #expect(device.macroKeyCount > 0, "\(device.name) has macroKeys feature but count=0")
            }
        }
    }

    @Test("Filter by type returns correct types")
    func filterByType() {
        let keyboards = DeviceDatabase.shared.devices(ofType: .keyboard)
        let mice = DeviceDatabase.shared.devices(ofType: .mouse)
        let accessories = DeviceDatabase.shared.devices(ofType: .accessory)

        for kb in keyboards { #expect(kb.type == .keyboard) }
        for m in mice { #expect(m.type == .mouse) }
        for a in accessories { #expect(a.type == .accessory) }

        #expect(keyboards.count + mice.count + accessories.count == DeviceDatabase.shared.allDevices().count)
    }

    @Test("No duplicate PIDs")
    func noDuplicatePIDs() {
        let all = DeviceDatabase.shared.allDevices()
        let pids = all.map { $0.pid }
        let uniquePids = Set(pids)
        #expect(pids.count == uniquePids.count, "Found duplicate PIDs in database")
    }

    @Test("Devices with zones have valid LED IDs")
    func zonesValid() {
        let all = DeviceDatabase.shared.allDevices()
        for device in all {
            for zone in device.zones {
                #expect(!zone.label.isEmpty, "\(device.name) has zone with empty label")
            }
        }
    }
}
