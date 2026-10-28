import SwiftUI
import AppKit
import UniformTypeIdentifiers
import IOKit.hid

@MainActor final class Editor: ObservableObject {
    @Published var profile = Profile() { didSet { saveLocal() } }
    @Published var selected = 116
    @Published var status = KeyboardHID.status()
    @Published var message = "点击键帽，选择它的新功能。"
    @Published var busy = false
    @Published var review = false

    private var cache: URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("WKB603Configurator/profile.json")
    }

    init() {
        if FileManager.default.fileExists(atPath:cache.path) {
            do { profile = try Profile.load(Data(contentsOf:cache)); message = "已载入上次的本地方案。" }
            catch { message = "本地方案读取失败：\(error.localizedDescription)" }
        }
    }

    func saveLocal() {
        do {
            try FileManager.default.createDirectory(at:cache.deletingLastPathComponent(),withIntermediateDirectories:true)
            try profile.encoded().write(to:cache,options:.atomic)
        } catch { message = "保存本地方案失败：\(error.localizedDescription)" }
    }

    func importProfile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard size <= 128*1024 else { throw ConfigError.invalid("方案文件过大。") }
            profile = try Profile.load(Data(contentsOf:url)); message = "已导入本地方案，尚未写入键盘。"
        } catch { message = "导入失败：\(error.localizedDescription)" }
    }

    func exportProfile() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "wkb603-profile.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try profile.encoded().write(to:url,options:.atomic); message = "方案已导出。" }
        catch { message = "导出失败：\(error.localizedDescription)" }
    }

    func requestPermission() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        if let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
        message = "请为 WKB603 Configurator 开启输入监控；按系统提示重新打开应用。测试结束可关闭权限并退出应用。"
    }

    func write() {
        let snapshot = profile
        busy = true; message = "正在写入，请保持 USB 连接…"
        Task {
            let error: String? = await Task.detached {
                do { try KeyboardHID.write(snapshot); return nil }
                catch { return error.localizedDescription }
            }.value
            busy = false
            message = error.map { "写入未完成：\($0)" }
                ?? "键盘已确认接收。请测试修改的按键，并在拔线重插后复测；确认响应不等于功能验证。"
            status = KeyboardHID.status()
        }
    }
}

struct ContentView: View {
    @StateObject private var editor = Editor()
    private let timer = Timer.publish(every:3,on:.main,in:.common).autoconnect()
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack(spacing:12) {
                Image(systemName:"keyboard.fill").font(.system(size:30)).foregroundStyle(.orange)
                VStack(alignment:.leading,spacing:3) {
                    Text("WKB603 Configurator").font(.title2.bold())
                    Text("点选按键，为你的键盘换一个用途").foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(editor.status.count == 1 ? Color.green : Color.gray).frame(width:8,height:8)
                Text(editor.status.text).font(.callout)
            }
            HStack(alignment:.top,spacing:18) {
                VStack(alignment:.leading,spacing:14) {
                    HStack {
                        Text("键盘布局").font(.headline)
                        Spacer()
                        Label("蓝色：已修改",systemImage:"circle.fill").font(.caption).foregroundStyle(.blue)
                    }
                    KeyboardView(editor:editor).frame(height:310)
                    HStack {
                        Label("普通层",systemImage:"square.stack.3d.up")
                        Spacer()
                        Text("Fn 由键盘内部处理").foregroundStyle(.secondary)
                    }.font(.caption)
                    Divider()
                    HStack {
                        VStack(alignment:.leading,spacing:4) {
                            Text(editor.profile.name).font(.headline)
                            Text("本地方案 · \(editor.profile.mappings.count) 个自定义按键").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("导入…",action:editor.importProfile).accessibilityLabel("导入方案")
                        Button("导出…",action:editor.exportProfile).accessibilityLabel("导出方案")
                    }
                    Text("这里显示本地方案，无法读取键盘中已保存的完整配置。写入会替换整张普通层改键表，未列出的按键恢复默认。").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    HStack {
                        Button("载入三键示例") {
                            editor.profile = .example
                            editor.message = "已载入 Insert、Cal 和 Pause 示例，尚未写入键盘。"
                        }.accessibilityLabel("载入三键示例")
                        Button("清空本地改键") {
                            editor.profile = Profile()
                            editor.message = "本地方案已清空，键盘尚未改变。"
                        }.accessibilityLabel("清空本地改键")
                        Spacer()
                    }
                }.padding(20).background(.background,in:RoundedRectangle(cornerRadius:16))
                KeyEditor(editor:editor).id(editor.selected).frame(width:270)
            }.disabled(editor.busy)
            HStack(alignment:.center,spacing:14) {
                if editor.busy { ProgressView().controlSize(.small) }
                Text(editor.message).font(.callout).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                if !editor.status.permission {
                    Button("设置权限…",action:editor.requestPermission).disabled(editor.busy)
                }
                Button("检查并写入键盘…") { editor.review = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(editor.busy)
                    .accessibilityLabel("检查并写入键盘")
            }
            Text("USB 有线配置 · 白光 WKB603 / JZ990 · 无需常驻 · 无按键监听").font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(minWidth:1140,minHeight:700)
        .background(Color(nsColor:.windowBackgroundColor)).tint(.orange)
        .onReceive(timer) { _ in
            if !editor.busy {
                let next = KeyboardHID.status()
                if next != editor.status { editor.status = next }
            }
        }
        .sheet(isPresented:$editor.review) { WriteReview(editor:editor) }
    }
}

struct KeyboardView: View {
    @ObservedObject var editor: Editor
    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 820
            ZStack(alignment:.topLeading) {
                RoundedRectangle(cornerRadius:14).fill(Color(nsColor:.controlBackgroundColor))
                ForEach(Layout.keys.filter { !$0.isRotary }) { key in
                    let action = editor.profile.mappings[key.id]
                    let selected = editor.selected == key.id
                    Button { editor.selected = key.id } label: {
                        VStack(spacing:2) {
                            Text(key.label).font(.system(size:10*scale,weight:.medium)).lineLimit(1).minimumScaleFactor(0.5)
                                .foregroundStyle(action == nil ? Color.primary : Color.secondary)
                            if let action { Text(action.label).font(.system(size:9*scale,weight:.bold)).lineLimit(1).minimumScaleFactor(0.5) }
                        }
                        .frame(width:key.width*scale,height:key.height*scale)
                        .background(action == nil ? Color(nsColor:.textBackgroundColor) : Color.blue.opacity(0.12),in:RoundedRectangle(cornerRadius:5))
                        .overlay(RoundedRectangle(cornerRadius:5).stroke(selected ? Color.orange : Color.gray.opacity(0.22),lineWidth:selected ? 2 : 1))
                    }
                    .buttonStyle(.plain).disabled(!key.editable)
                    .help(key.editable ? "\(key.label) → \(action?.label ?? "默认功能")" : "Fn 暂不支持修改")
                    .accessibilityLabel("\(key.label)，\(action?.label ?? "默认功能")")
                    .position(x:(key.x+key.width/2)*scale,y:(key.y+key.height/2)*scale)
                }
                RotaryView(editor:editor,scale:scale)
                    .position(x:759*scale,y:48*scale)
            }.frame(height:280*scale)
        }
    }
}

struct RotaryView: View {
    @ObservedObject var editor: Editor
    let scale: Double
    var selected: Bool { Layout.byID[editor.selected]?.isRotary == true }
    var modified: Bool { [14,15,16].contains { editor.profile.mappings[$0] != nil } }
    var body: some View {
        Menu {
            ForEach([16,15,14],id:\.self) { id in
                Button {
                    editor.selected = id
                } label: {
                    Text("\(Layout.byID[id]!.label) → \(editor.profile.mappings[id]?.label ?? [14:"音量 +",15:"音量 −",16:"静音"][id]!)")
                }
            }
        } label: {
            ZStack {
                HStack {
                    Image(systemName:"arrow.counterclockwise")
                    Spacer()
                    Image(systemName:"arrow.clockwise")
                }.font(.system(size:11*scale)).foregroundStyle(.secondary)
                Circle()
                    .fill(LinearGradient(colors:[Color(nsColor:.textBackgroundColor),Color(nsColor:.controlColor)],startPoint:.topLeading,endPoint:.bottomTrailing))
                    .frame(width:36*scale,height:36*scale)
                    .overlay(Circle().stroke(selected ? Color.orange : (modified ? Color.blue : Color.gray.opacity(0.5)),lineWidth:selected ? 2 : 1))
                ForEach(0..<16,id:\.self) { tick in
                    Capsule().fill(Color.secondary.opacity(0.35))
                        .frame(width:scale,height:3*scale)
                        .offset(y:-14*scale).rotationEffect(.degrees(Double(tick)*22.5))
                }
                Circle().fill(modified ? Color.blue.opacity(0.15) : Color(nsColor:.controlBackgroundColor))
                    .frame(width:22*scale,height:22*scale)
                Image(systemName:"speaker.slash.fill").font(.system(size:10*scale)).foregroundStyle(.secondary)
            }.frame(width:76*scale,height:46*scale)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("点击旋钮，选择按压、顺时针或逆时针操作")
        .accessibilityLabel("旋钮，选择按压、顺时针或逆时针操作")
    }
}

struct KeyEditor: View {
    @ObservedObject var editor: Editor
    @State private var kind: ActionKind = .key
    @State private var target = 4
    @State private var modifiers = 0
    var key: PhysicalKey { Layout.byID[editor.selected]! }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("修改按键").font(.headline)
            Text(key.label).font(.system(size:key.isRotary ? 24 : 32,weight:.semibold,design:.rounded))
            Text("当前方案：\(editor.profile.mappings[key.id]?.label ?? "默认功能")").foregroundStyle(.secondary)
            Picker("功能类型",selection:$kind) {
                Text("按键 / 组合键").tag(ActionKind.key)
                Text("媒体功能").tag(ActionKind.media)
            }.pickerStyle(.segmented).labelsHidden()
            if kind == .key {
                Picker("目标按键",selection:$target) {
                    ForEach(Catalog.keyboard) { Text($0.name).tag($0.id) }
                }
                VStack(alignment:.leading,spacing:10) {
                    Text("组合键修饰键").font(.caption).foregroundStyle(.secondary)
                    ForEach([1,2,4,8],id:\.self) { bit in
                        Toggle([1:"⌃ Control",2:"⇧ Shift",4:"⌥ Option",8:"⌘ Command"][bit]!,isOn:Binding(
                            get:{ modifiers & bit != 0 },
                            set:{ if $0 { modifiers |= bit } else { modifiers &= ~bit } }))
                            .accessibilityLabel([1:"Control",2:"Shift",4:"Option",8:"Command"][bit]!)
                    }
                }
            } else {
                Picker("媒体操作",selection:$target) {
                    ForEach(Catalog.media) { Text($0.name).tag($0.id) }
                }
            }
            Divider()
            Text("预览：\(KeyAction(kind:kind,usage:target,modifiers:kind == .key ? modifiers : 0).label)").font(.headline)
            Button("添加到方案") {
                editor.profile.mappings[key.id] = KeyAction(kind:kind,usage:target,modifiers:kind == .key ? modifiers : 0)
                editor.message = "\(key.label) 已加入本地方案；点击“检查并写入键盘”才会生效。"
            }.buttonStyle(.borderedProminent).frame(maxWidth:.infinity).accessibilityLabel("添加到方案")
            Button("恢复此键默认功能") {
                editor.profile.mappings.removeValue(forKey:key.id)
                editor.message = "已从本地方案移除 \(key.label) 的改键，尚未写入键盘。"
            }.accessibilityLabel("恢复此键默认功能")
            Text("⌘ / ⌥ 按 Mac 命名；换到其他系统时，组合键的用途可能不同。").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength:0)
        }.padding(20).frame(maxHeight:.infinity,alignment:.topLeading)
        .background(.background,in:RoundedRectangle(cornerRadius:16))
        .onAppear { loadSelection() }
        .onChange(of:editor.profile) { _ in loadSelection() }
        .onChange(of:kind) { newValue in
            if newValue == .media, !Catalog.media.contains(where:{$0.id == target}) { target = 0xcd }
            if newValue == .key, !Catalog.keyboard.contains(where:{$0.id == target}) { target = 4 }
        }
    }
    private func loadSelection() {
        if let action = editor.profile.mappings[key.id] {
            kind = action.kind; target = action.usage; modifiers = action.modifiers
        } else if key.isRotary {
            kind = .media; target = [14:0xe9,15:0xea,16:0xe2][key.id]!; modifiers = 0
        } else {
            kind = .key; target = Catalog.keyboard.contains(where:{$0.id == key.usage}) ? key.usage : 4; modifiers = 0
        }
    }
}

struct WriteReview: View {
    @ObservedObject var editor: Editor
    @Environment(\.dismiss) private var dismiss
    @State private var accepted = false
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("检查完整方案").font(.title2.bold())
            Text("以下改键将一起保存到键盘，其他普通层改键恢复默认。Fn 层和灯效配置不会发送。")
            ScrollView {
                VStack(spacing:10) {
                    if editor.profile.mappings.isEmpty { Text("没有自定义按键：普通层全部恢复默认。") }
                    ForEach(editor.profile.mappings.keys.sorted(),id:\.self) { key in
                        HStack {
                            Text(Layout.byID[key]?.label ?? "?").fontWeight(.semibold)
                            Spacer(); Image(systemName:"arrow.right"); Spacer()
                            Text(editor.profile.mappings[key]!.label)
                        }
                    }
                }.padding(14)
            }.frame(maxHeight:230).background(Color.secondary.opacity(0.07),in:RoundedRectangle(cornerRadius:10))
            Toggle("我确认这是完整方案，未列出的普通按键恢复默认",isOn:$accepted)
                .accessibilityLabel("确认完整方案覆盖普通层")
            if editor.status.count != 1 || !editor.status.permission {
                Text(editor.status.text).font(.callout).foregroundStyle(.orange)
            }
            Text("请保持有线连接。完成后测试按键，并拔线重插验证保留效果。首次尝试的新键位或组合需要实测。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("写入键盘") { dismiss(); editor.write() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!accepted || editor.status.count != 1 || !editor.status.permission)
            }
        }.padding(24).frame(width:530).tint(.orange)
    }
}

@main struct ConfiguratorApp: App {
    init() {
        if CommandLine.arguments.contains("--self-test") {
            do { try runSelfTests(); exit(0) }
            catch { fputs("Self-test failed: \(error)\n",stderr); exit(1) }
        }
    }
    var body: some Scene {
        WindowGroup { ContentView() }
            .windowStyle(.titleBar)
            .defaultSize(width:1240,height:740)
            .commands { CommandGroup(replacing:.newItem) {} }
    }
}
