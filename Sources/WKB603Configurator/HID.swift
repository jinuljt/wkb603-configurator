import Foundation
import IOKit.hid

struct DeviceStatus: Equatable {
    let count: Int
    let permission: Bool
    var text: String {
        if count == 0 { return "未连接 WKB603 · 请使用 USB 数据线" }
        if count > 1 { return "检测到多把键盘 · 请只连接一把" }
        return permission ? "WKB603 已连接 · 可以写入" : "WKB603 已连接 · 需要输入监控权限"
    }
}

enum KeyboardHID {
    static func matches(product: String, transport: String, vendor: Int, productID: Int,
                        page: Int, usage: Int, feature: Int) -> Bool {
        product == "WKB603" && transport == "USB" && vendor == 0x05ac && productID == 0x024f
            && page == 1 && usage == 6 && feature == 64
    }

    private static func devices() -> [IOHIDDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault,0)
        IOHIDManagerSetDeviceMatching(manager,["Product":"WKB603","Transport":"USB",
            "VendorID":0x05ac,"ProductID":0x024f] as CFDictionary)
        return Array((IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []).filter { device in
            func str(_ key: String) -> String { IOHIDDeviceGetProperty(device,key as CFString) as? String ?? "" }
            func num(_ key: String) -> Int { (IOHIDDeviceGetProperty(device,key as CFString) as? NSNumber)?.intValue ?? 0 }
            return matches(product:str("Product"),transport:str("Transport"),vendor:num("VendorID"),
                productID:num("ProductID"),page:num("PrimaryUsagePage"),usage:num("PrimaryUsage"),feature:num("MaxFeatureReportSize"))
        }
    }

    static func status() -> DeviceStatus {
        DeviceStatus(count:devices().count,permission:IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted)
    }

    static func validAck(_ response: [UInt8], for request: [UInt8]) -> Bool {
        response.count == 64 && response[0] == request[0] && response[1] == request[1] && response[3] == 1
    }

    // Kept separate from IOKit so failure/stop behavior can be tested without a keyboard.
    static func transmit(_ reports: [[UInt8]], send: ([UInt8]) throws -> Void,
                         receive: () throws -> [UInt8]) throws {
        guard reports.count == 13, reports.allSatisfy({ $0.count == 64 }) else {
            throw ConfigError.invalid("无效的数据包，已停止。")
        }
        for (index, report) in reports.enumerated() {
            try send(report)
            if [0,1,11,12].contains(index), !validAck(try receive(),for:report) {
                throw ConfigError.invalid("第 \(index+1) 个报告未收到有效确认。部分命令可能已发送，请先拔线重插再重试。")
            }
        }
    }

    static func write(_ profile: Profile) throws {
        let reports = try profile.reports()
        guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else {
            throw ConfigError.invalid("请先为 WKB603 Configurator 开启输入监控权限，然后重新打开应用。")
        }
        let candidates = devices()
        guard candidates.count == 1 else { throw ConfigError.invalid("请只连接一把 USB WKB603。") }
        let device = candidates[0]
        func check(_ status: IOReturn) throws {
            guard status == kIOReturnSuccess else {
                throw ConfigError.invalid(String(format:"USB 通信失败（0x%08x）。如果已经开始写入，请先拔线重插再重试。",UInt32(bitPattern:status)))
            }
        }
        try check(IOHIDDeviceOpen(device,0)) // Nonexclusive, never seize the keyboard.
        defer { IOHIDDeviceClose(device,0) }
        try transmit(reports, send: { report in
            Thread.sleep(forTimeInterval:0.02)
            try check(report.withUnsafeBufferPointer { IOHIDDeviceSetReport(device,kIOHIDReportTypeFeature,0,$0.baseAddress!,$0.count) })
        }, receive: {
            Thread.sleep(forTimeInterval:0.02)
            var bytes = [UInt8](repeating:0,count:64); var size = 64
            try check(bytes.withUnsafeMutableBufferPointer { IOHIDDeviceGetReport(device,kIOHIDReportTypeFeature,0,$0.baseAddress!,&size) })
            return Array(bytes.prefix(max(0,min(size,64))))
        })
    }
}
