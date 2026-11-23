import SwiftUI
import ExternalAccessory

@main
struct NoodoeProbeDeepApp: App {
    @StateObject private var workspace = ProbeWorkspace()

    var body: some Scene {
        WindowGroup {
            TabView {
                EAProbePage(probe: workspace.ea, log: workspace.log)
                    .tabItem { Label("iAP 深度測試", systemImage: "cable.connector") }
                BLEProbePage(probe: workspace.ble)
                    .tabItem { Label("BLE 服務", systemImage: "antenna.radiowaves.left.and.right") }
                LogPage(log: workspace.log)
                    .tabItem { Label("原始日誌", systemImage: "doc.text") }
            }
        }
    }
}

struct EAProbePage: View {
    @ObservedObject var probe: DeepEAProbe
    @ObservedObject var log: ProbeLog
    @State private var hexText: String = ""
    @State private var txProtocol: String = "sunray.control"
    @State private var enableManualWrite = false
    @State private var confirmActive = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("已由系統連接的配件（不使用配件選擇器）")) {
                    Button("重新查詢 connectedAccessories") { probe.refresh() }
                    if probe.accessories.isEmpty {
                        Text("EA 清單為空：即使在 iOS 設定中看到藍牙名稱，這裡仍可能沒有 EASession 權限。")
                            .font(.footnote)
                    }
                    ForEach(probe.accessories, id: \.connectionID) { accessory in
                        Button {
                            probe.closeAll()
                            probe.selectedConnectionID = accessory.connectionID
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(accessory.name).bold()
                                    if probe.selectedConnectionID == accessory.connectionID {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                }
                                Text("廠商：\(accessory.manufacturer)  型號：\(accessory.modelNumber)")
                                Text("FW: \(accessory.firmwareRevision)  HW: \(accessory.hardwareRevision)")
                                Text("連線：\(accessory.isConnected ? "是" : "否")  ID: \(accessory.connectionID)")
                                Text("Protocols: \(accessory.protocolStrings.joined(separator: ", "))")
                            }
                            .font(.footnote)
                            .foregroundColor(.primary)
                        }
                    }
                }
                Section(header: Text("EASession / NSStream 雙通道")) {
                    Text("只開啟串流、不自動發送握手。先單獨測 control，再測 data；也能兩條一起開測。").font(.footnote)
                    ForEach(probe.supportedProtocols, id: \.self) { proto in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(proto).font(.headline)
                            Text(probe.info[proto] ?? "未測試")
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            HStack {
                                Button("開啟監聽") { probe.begin(proto) }
                                    .disabled(probe.selected == nil)
                                Spacer()
                                Button("關閉通道") { probe.close(proto) }
                            }
                        }
                    }
                    Button("全部關閉") { probe.closeAll() }
                }
                Section(header: Text("手動 TX（預設禁止）")) {
                    Text("只有在已確認封包用途後才啟用。原廠 SR1.5 指令與 NewDoe NDCP 不可混用；此工具沒有內建任何 OTA/刷寫指令。")
                        .font(.footnote)
                    Toggle("我了解發送未知指令可能造成異常", isOn: $enableManualWrite)
                    Picker("通道", selection: $txProtocol) {
                        ForEach(probe.supportedProtocols, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("手動輸入 Hex，例如 AA 55", text: $hexText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                    Button("準備傳送（再次確認）") { confirmActive = true }
                        .disabled(!enableManualWrite || HexCodec.parse(hexText) == nil)
                        .alert("確認主動寫入", isPresented: $confirmActive) {
                            Button("取消", role: .cancel) { }
                            Button("確定發送") { probe.sendHex(hexText, to: txProtocol) }
                        } message: {
                            Text("此操作會向儀表的 \(txProtocol) 寫入 \(HexCodec.parse(hexText)?.count ?? 0) bytes。只有確認是安全測試指令時才發送。")
                        }
                }
            }
            .navigationTitle("Noodoe iAP 診斷")
        }
    }
}

struct BLEProbePage: View {
    @ObservedObject var probe: DeepBLEProbe

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("BLE 掃描與探索")) {
                    Text(probe.status)
                    HStack {
                        Button("開始掃描") { probe.scan() }
                        Spacer()
                        Button("停止掃描") { probe.stopScan() }
                    }
                    Text("只掃描目前正在廣播的 BLE 裝置。Classic SPP 裝置不會因為支援藍牙而出現在這裡。").font(.footnote)
                }
                Section(header: Text("附近 BLE 裝置")) {
                    ForEach(probe.entries) { entry in
                        Button {
                            probe.stopScan()
                            probe.connect(entry.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name).bold()
                                Text("RSSI \(entry.rssi) dBm / \(entry.id.uuidString)")
                                Text(entry.advertising)
                            }
                            .font(.footnote)
                            .foregroundColor(.primary)
                        }
                    }
                }
                Section(header: Text("GATT 服務 / 特徵值")) {
                    Button("讀取所有標記為可讀的特徵值") { probe.readReadableCharacteristics() }
                    Button("斷開 BLE") { probe.disconnect() }
                    ForEach(probe.serviceLines, id: \.self) { line in
                        Text(line).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Noodoe BLE 診斷")
        }
    }
}

struct LogPage: View {
    @ObservedObject var log: ProbeLog

    var body: some View {
        NavigationView {
            VStack(spacing: 8) {
                HStack {
                    Text("\(log.lines.count) 筆（畫面保留最近 1,000 筆）")
                    Spacer()
                    ShareLink(item: log.fileURL) { Label("分享完整 Log", systemImage: "square.and.arrow.up") }
                }.font(.footnote).padding(.horizontal)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(log.lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }.padding()
                }
            }
            .navigationTitle("測試日誌")
        }
    }
}
