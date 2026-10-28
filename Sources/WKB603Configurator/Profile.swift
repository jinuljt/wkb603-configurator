import Foundation
import CryptoKit

struct Choice: Identifiable {
    let id: Int
    let name: String
}

enum Catalog {
    static let keyboard: [Choice] = {
        var result = (0..<26).map { Choice(id: 4 + $0, name: String(UnicodeScalar(65 + $0)!)) }
        result += (1...9).map { Choice(id: 29 + $0, name: String($0)) }
        result.append(Choice(id: 39, name: "0"))
        result += [(40,"Enter"),(41,"Esc"),(42,"Backspace"),(43,"Tab"),(44,"Space"),
                   (45,"−"),(46,"="),(47,"["),(48,"]"),(49,"\\"),(51,";"),(52,"'"),
                   (53,"`"),(54,","),(55,"."),(56,"/"),(57,"Caps Lock")].map { Choice(id:$0.0,name:$0.1) }
        result += (1...24).map { Choice(id: $0 <= 12 ? 57 + $0 : 91 + $0, name: "F\($0)") }
        result += [(70,"Print Screen"),(71,"Scroll Lock"),(72,"Pause"),(73,"Insert"),
                   (74,"Home"),(75,"Page Up"),(76,"Delete"),(77,"End"),(78,"Page Down"),
                   (79,"→"),(80,"←"),(81,"↓"),(82,"↑"),(83,"Num Lock"),
                   (84,"Num /"),(85,"Num *"),(86,"Num −"),(87,"Num +"),(88,"Num Enter"),
                   (98,"Num 0"),(99,"Num ."),(101,"Menu")].map { Choice(id:$0.0,name:$0.1) }
        result += (1...9).map { Choice(id: 88 + $0, name: "Num \($0)") }
        return result
    }()
    static let media = [(0xcd,"播放 / 暂停"),(0xb7,"停止"),(0xb6,"上一曲"),(0xb5,"下一曲"),
                        (0xe9,"音量 +"),(0xea,"音量 −"),(0xe2,"静音")].map { Choice(id:$0.0,name:$0.1) }
}

enum ActionKind: String, Codable, CaseIterable { case key, media }

struct KeyAction: Codable, Equatable, Sendable {
    var kind: ActionKind
    var usage: Int
    var modifiers: Int = 0

    var label: String {
        if kind == .media { return Catalog.media.first { $0.id == usage }?.name ?? "?" }
        let prefix = [(1,"⌃"),(2,"⇧"),(4,"⌥"),(8,"⌘")].filter { modifiers & $0.0 != 0 }.map { $0.1 }.joined()
        return prefix + (Catalog.keyboard.first { $0.id == usage }?.name ?? "?")
    }

    func validate() throws {
        let choices = kind == .key ? Catalog.keyboard : Catalog.media
        guard choices.contains(where: { $0.id == usage }), (0...15).contains(modifiers),
              kind != .media || modifiers == 0 else { throw ConfigError.invalid("不支持的目标键或修饰键。") }
    }
}

struct Profile: Codable, Equatable, Sendable {
    var version = 1
    var name = "我的方案"
    var mappings: [Int: KeyAction] = [:]

    static let example = Profile(name: "Mac 三键示例", mappings: [
        109: KeyAction(kind:.key,usage:44,modifiers:8),
        115: KeyAction(kind:.media,usage:0xcd),
        116: KeyAction(kind:.key,usage:31,modifiers:10)
    ])

    func validate() throws {
        guard version == 1, !name.isEmpty, name.count <= 120 else { throw ConfigError.invalid("方案名称或版本无效。") }
        for (index, action) in mappings {
            guard Layout.byID[index]?.editable == true else { throw ConfigError.invalid("方案包含不支持的物理键位：\(index)。") }
            try action.validate()
        }
    }

    func reports() throws -> [[UInt8]] {
        try validate()
        var table = [UInt8](repeating:0,count:576)
        for (index, action) in mappings {
            let bytes: [UInt8] = action.kind == .key
                ? [2, UInt8(action.modifiers), UInt8(action.usage), 0]
                : [3, UInt8(action.usage), 0, 0]
            table.replaceSubrange(index*4..<index*4+4, with:bytes)
        }
        table[574] = 0xaa; table[575] = 0x55
        func command(_ opcode: UInt8) -> [UInt8] {
            var report = [UInt8](repeating:0,count:64)
            report[0] = 4; report[1] = opcode
            if opcode == 0x11 { report[8] = 9 }
            return report
        }
        let chunks = stride(from:0,to:576,by:64).map { Array(table[$0..<$0+64]) }
        return [command(0x18),command(0x11)] + chunks + [command(2),command(0xf0)]
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        return try encoder.encode(self)
    }

    static func load(_ data: Data) throws -> Profile {
        guard data.count <= 128*1024 else { throw ConfigError.invalid("方案文件过大。") }
        let value = try JSONDecoder().decode(Profile.self,from:data)
        try value.validate()
        return value
    }
}

enum ConfigError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let text): return text } }
}

func packetDigest(_ reports: [[UInt8]]) -> String {
    SHA256.hash(data:Data(reports.flatMap { $0 })).map { String(format:"%02x",$0) }.joined()
}
