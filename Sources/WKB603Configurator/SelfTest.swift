import Foundation

func runSelfTests() throws {
    func require(_ passed: Bool, _ message: String) throws {
        if !passed { throw ConfigError.invalid(message) }
    }
    let reports = try Profile.example.reports()
    // Captured from the native writer already verified on physical hardware.
    try require(packetDigest(reports) == "96248dde27fd5f4c32313985e11013c101b801ab7297c3577242f2ce4ff51c07", "Hardware-verified packet fixture changed")
    try require(try Profile.load(Profile.example.encoded()) == .example,"Profile round trip")
    try require(Set(Layout.keys.map(\.id)).count == Layout.keys.count,"Duplicate key positions")
    try require(Set(Catalog.keyboard.map(\.id)).count == Catalog.keyboard.count,"Duplicate target keys")
    for bad in [Profile(mappings:[96:KeyAction(kind:.key,usage:4)]),
                Profile(mappings:[999:KeyAction(kind:.key,usage:4)]),
                Profile(mappings:[116:KeyAction(kind:.key,usage:999)]),
                Profile(mappings:[116:KeyAction(kind:.key,usage:4,modifiers:256)]),
                Profile(mappings:[115:KeyAction(kind:.media,usage:0xcd,modifiers:8)])] {
        do { _ = try bad.reports(); throw ConfigError.invalid("Invalid profile accepted") }
        catch ConfigError.invalid(let text) where text != "Invalid profile accepted" { }
    }
    try require(KeyboardHID.matches(product:"WKB603",transport:"USB",vendor:0x05ac,productID:0x024f,page:1,usage:6,feature:64),"Exact match rejected")
    for (name,transport,page,feature) in [("Apple Keyboard","USB",1,64),("WKB603","Bluetooth",1,64),("WKB603","USB",12,1)] {
        try require(!KeyboardHID.matches(product:name,transport:transport,vendor:0x05ac,productID:0x024f,page:page,usage:6,feature:feature),"Wrong interface accepted")
    }
    var sent = 0; var received = 0; var last = [UInt8]()
    try KeyboardHID.transmit(reports,send:{ sent += 1; last = $0 },receive:{ received += 1; var ack=last; ack[3]=1; return ack })
    try require(sent == 13 && received == 4,"Wrong report/ACK counts")
    // A failed ACK must stop before remap initialization or table transmission.
    sent = 0
    do {
        try KeyboardHID.transmit(reports,send:{ _ in sent += 1 },receive:{ [UInt8](repeating:0,count:64) })
        throw ConfigError.invalid("Bad ACK accepted")
    } catch ConfigError.invalid(let message) where message != "Bad ACK accepted" { }
    try require(sent == 1,"Continued after failed ACK")
    // A data-transfer failure must not send apply/finalize commands.
    sent = 0
    do {
        try KeyboardHID.transmit(reports,send:{ packet in
            sent += 1; last=packet
            if sent == 5 { throw ConfigError.invalid("Injected write failure") }
        },receive:{ var ack=last; ack[3]=1; return ack })
        throw ConfigError.invalid("Write failure ignored")
    } catch ConfigError.invalid(let message) where message == "Injected write failure" { }
    try require(sent == 5,"Continued after failed data transfer")
    print("PASS: hardware packet fixture, profile validation/round-trip, device targeting, ACK sequence and stop-on-failure. No hardware writes.")
}
