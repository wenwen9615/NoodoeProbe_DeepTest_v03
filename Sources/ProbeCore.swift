import Foundation
import SwiftUI
import Combine
import ExternalAccessory
import CoreBluetooth

// Independent public-API implementation. No code or binaries from the OEM IPA.
// Everything is passive by default; no automatic handshake or firmware commands.

final class ProbeLog: ObservableObject {
    @Published private(set) var lines: [String] = []
    let fileURL: URL

    init() {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        fileURL = folder.appendingPathComponent("noodoe-deep-probe-\(stamp).log")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        append("START iOS probe / passive by default")
    }

    func append(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)"
        lines.append(line)
        if lines.count > 1000 { lines.removeFirst(lines.count - 1000) }
        if let data = (line + "\n").data(using: .utf8),
           let file = try? FileHandle(forWritingTo: fileURL) {
            file.seekToEndOfFile()
            file.write(data)
            file.closeFile()
        }
    }
}

struct HexCodec {
    static func encode(_ data: Data, limit: Int = 1024) -> String {
        let preview = data.prefix(limit).map { String(format: "%02X", $0) }.joined(separator: " ")
        return data.count > limit ? preview + " … (\(data.count) total bytes)" : preview
    }

    static func parse(_ text: String) -> Data? {
        let compact = text.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .filter { !$0.isWhitespace && $0 != "," && $0 != ":" && $0 != "-" }
        guard !compact.isEmpty, compact.count.isMultiple(of: 2), compact.count <= 2048,
              compact.allSatisfy({ $0.isHexDigit }) else { return nil }
        let chars = Array(compact)
        var bytes: [UInt8] = []
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let value = UInt8(String(chars[i...i+1]), radix: 16) else { return nil }
            bytes.append(value)
        }
        return Data(bytes)
    }
}

final class EAChannel: NSObject, StreamDelegate {
    let name: String
    private let log: ProbeLog
    private var session: EASession?
    private var input: InputStream?
    private var output: OutputStream?
    private var pending: [Data] = []
    private var writeOffset: Int = 0
    private(set) var received: Int = 0
    private(set) var transmitted: Int = 0
    var onUpdate: (() -> Void)?
    private(set) var state: String = "未建立"

    init(name: String, accessory: EAAccessory, log: ProbeLog) {
        self.name = name
        self.log = log
        super.init()
        guard accessory.protocolStrings.contains(name) else {
            state = "配件未宣告此協定"
            log.append("EA \(name) not advertised")
            return
        }
        guard let created = EASession(accessory: accessory, forProtocol: name) else {
            state = "EASession == nil"
            log.append("EA \(name) EASession creation FAILED")
            return
        }
        session = created
        guard let i = created.inputStream, let o = created.outputStream else {
            state = "EASession has missing stream(s)"
            log.append("EA \(name) missing input/output stream")
            return
        }
        input = i
        output = o
        i.delegate = self
        o.delegate = self
        i.schedule(in: .main, forMode: .default)
        o.schedule(in: .main, forMode: .default)
        // Open both streams on the same run loop, without writing any bytes.
        i.open()
        o.open()
        state = "已呼叫 open()，等待 streamEvent"
        log.append("EA \(name) session created; input/output open called")
        onUpdate?()
    }

    func statusDescription() -> String {
        "\(state) | IN=\(input.map { String(describing: $0.streamStatus) } ?? "nil") OUT=\(output.map { String(describing: $0.streamStatus) } ?? "nil") RX=\(received) TX=\(transmitted)"
    }

    func close() {
        for stream in [input as Stream?, output as Stream?].compactMap({ $0 }) {
            stream.delegate = nil
            stream.remove(from: .main, forMode: .default)
            stream.close()
        }
        input = nil
        output = nil
        session = nil
        pending.removeAll()
        writeOffset = 0
        state = "已關閉"
        log.append("EA \(name) closed")
        onUpdate?()
    }

    func enqueueManualTransmission(_ data: Data) {
        guard output != nil else { log.append("EA \(name) cannot TX: no output stream"); return }
        pending.append(data)
        log.append("EA \(name) MANUAL TX queued \(data.count) bytes: \(HexCodec.encode(data))")
        flushWrites()
    }

    private func flushWrites() {
        guard let o = output else { return }
        var loops = 0
        while o.hasSpaceAvailable && !pending.isEmpty && loops < 16 {
            loops += 1
            let data = pending[0]
            let offset = writeOffset
            let amount = data.count - offset
            let n = data.withUnsafeBytes { raw -> Int in
                guard let ptr = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                return o.write(ptr.advanced(by: offset), maxLength: amount)
            }
            if n < 0 {
                state = "寫入錯誤"
                log.append("EA \(name) TX ERROR: \(o.streamError?.localizedDescription ?? "unknown")")
                break
            }
            if n == 0 { break }
            transmitted += n
            writeOffset += n
            if writeOffset == data.count {
                pending.removeFirst()
                writeOffset = 0
            }
        }
        onUpdate?()
    }

    private func drainInput() {
        guard let i = input else { return }
        var loops = 0
        while i.hasBytesAvailable && loops < 64 {
            loops += 1
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = buffer.withUnsafeMutableBufferPointer { ptr -> Int in
                guard let base = ptr.baseAddress else { return 0 }
                return i.read(base, maxLength: ptr.count)
            }
            if count > 0 {
                received += count
                let packet = Data(buffer.prefix(count))
                log.append("EA \(name) RX \(count) bytes: \(HexCodec.encode(packet))")
            } else {
                if count < 0 { log.append("EA \(name) RX ERROR: \(i.streamError?.localizedDescription ?? "unknown")") }
                break
            }
        }
        onUpdate?()
    }

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        let direction = aStream === input ? "IN" : "OUT"
        if eventCode.contains(.openCompleted) {
            log.append("EA \(name) \(direction) openCompleted")
            state = "至少一條串流已開啟"
        }
        if eventCode.contains(.hasSpaceAvailable) {
            log.append("EA \(name) \(direction) hasSpaceAvailable")
            flushWrites()
        }
        if eventCode.contains(.hasBytesAvailable) {
            log.append("EA \(name) \(direction) hasBytesAvailable")
            if aStream === input { drainInput() }
        }
        if eventCode.contains(.endEncountered) {
            log.append("EA \(name) \(direction) endEncountered")
            state = "通道結束"
        }
        if eventCode.contains(.errorOccurred) {
            log.append("EA \(name) \(direction) errorOccurred: \(aStream.streamError?.localizedDescription ?? "unknown")")
            state = "串流錯誤"
        }
        onUpdate?()
    }
}

final class DeepEAProbe: NSObject, ObservableObject {
    @Published private(set) var accessories: [EAAccessory] = []
    @Published var selectedConnectionID: Int?
    @Published private(set) var info: [String: String] = [:]
    private var channels: [String: EAChannel] = [:]
    private let log: ProbeLog
    let supportedProtocols = ["sunray.control", "sunray.data"]

    init(log: ProbeLog) {
        self.log = log
        super.init()
        EAAccessoryManager.shared().registerForLocalNotifications()
        NotificationCenter.default.addObserver(self, selector: #selector(changed),
                                               name: .EAAccessoryDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changed),
                                               name: .EAAccessoryDidDisconnect, object: nil)
        refresh()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func changed(_ notice: Notification) {
        log.append("EA system accessory event: \(notice.name.rawValue)")
        refresh()
    }

    var selected: EAAccessory? {
        accessories.first(where: { $0.connectionID == selectedConnectionID })
    }

    func refresh() {
        let found = EAAccessoryManager.shared().connectedAccessories
        accessories = found
        if selectedConnectionID == nil || !found.contains(where: { $0.connectionID == selectedConnectionID }) {
            selectedConnectionID = found.first?.connectionID
        }
        log.append("EA connectedAccessories count=\(found.count)")
        for a in found {
            log.append("EA name=\(a.name) manufacturer=\(a.manufacturer) model=\(a.modelNumber) serial=\(a.serialNumber) fw=\(a.firmwareRevision) hw=\(a.hardwareRevision) connected=\(a.isConnected) protocols=\(a.protocolStrings.joined(separator: ","))")
        }
    }

    func begin(_ proto: String) {
        guard let a = selected else { log.append("EA no accessory selected"); return }
        channels[proto]?.close()
        let ch = EAChannel(name: proto, accessory: a, log: log)
        ch.onUpdate = { [weak self, weak ch] in
            guard let self = self, let ch = ch else { return }
            self.info[proto] = ch.statusDescription()
        }
        channels[proto] = ch
        info[proto] = ch.statusDescription()
    }

    func close(_ proto: String) {
        channels[proto]?.close()
        channels.removeValue(forKey: proto)
        info[proto] = "已關閉"
    }

    func closeAll() {
        for p in Array(channels.keys) { close(p) }
    }

    func sendHex(_ text: String, to proto: String) {
        guard let bytes = HexCodec.parse(text) else {
            log.append("EA MANUAL TX rejected: invalid hex or >1024 bytes")
            return
        }
        guard let channel = channels[proto] else { log.append("EA MANUAL TX rejected: stream not open"); return }
        channel.enqueueManualTransmission(bytes)
    }
}

struct BLEEntry: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
    var advertising: String
}

final class DeepBLEProbe: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published private(set) var entries: [BLEEntry] = []
    @Published private(set) var status: String = "等待藍牙初始化"
    @Published private(set) var serviceLines: [String] = []
    private var central: CBCentralManager!
    private var devices: [UUID: CBPeripheral] = [:]
    private var chosen: CBPeripheral?
    private let log: ProbeLog

    init(log: ProbeLog) {
        self.log = log
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: status = "藍牙可用"
        case .poweredOff: status = "藍牙關閉"
        case .unauthorized: status = "藍牙權限遭拒"
        case .unsupported: status = "不支援 BLE"
        default: status = "藍牙初始化中 / \(central.state.rawValue)"
        }
        log.append("BLE state=\(status)")
    }

    func scan() {
        guard central.state == .poweredOn else { log.append("BLE scan failed: radio not powered on"); return }
        entries.removeAll()
        devices.removeAll()
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        status = "BLE 掃描中（只會看到正在廣播的裝置）"
        log.append("BLE scanning started")
    }

    func stopScan() {
        central.stopScan()
        status = "BLE 掃描已停止"
        log.append("BLE scanning stopped")
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "(未提供名稱)"
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map { $0.uuidString }.joined(separator: ",")
        let solicited = (advertisementData[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID] ?? [])
            .map { $0.uuidString }.joined(separator: ",")
        let summary = "service=[\(services)] solicited=[\(solicited)] connectable=\(advertisementData[CBAdvertisementDataIsConnectable] ?? "?")"
        devices[peripheral.identifier] = peripheral
        let row = BLEEntry(id: peripheral.identifier, name: name, rssi: RSSI.intValue, advertising: summary)
        if let n = entries.firstIndex(where: { $0.id == row.id }) { entries[n] = row }
        else { entries.append(row) }
        if name.localizedCaseInsensitiveContains("Noodoe") || name.localizedCaseInsensitiveContains("NewDoe") {
            log.append("BLE discovered \(name) uuid=\(peripheral.identifier.uuidString) rssi=\(RSSI) \(summary)")
        }
    }

    func connect(_ id: UUID) {
        guard let p = devices[id] else { return }
        chosen = p
        p.delegate = self
        serviceLines.removeAll()
        central.connect(p, options: nil)
        log.append("BLE connect requested \(p.name ?? p.identifier.uuidString)")
    }

    func disconnect() {
        if let p = chosen { central.cancelPeripheralConnection(p) }
        chosen = nil
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log.append("BLE connected \(peripheral.name ?? peripheral.identifier.uuidString)")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log.append("BLE failed to connect: \(error?.localizedDescription ?? "unknown")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log.append("BLE disconnected: \(error?.localizedDescription ?? "normal")")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let e = error { log.append("BLE service discovery error: \(e.localizedDescription)"); return }
        for s in peripheral.services ?? [] {
            let line = "Service \(s.uuid.uuidString)"
            serviceLines.append(line)
            log.append("BLE \(line)")
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let e = error { log.append("BLE characteristic discovery error: \(e.localizedDescription)"); return }
        for c in service.characteristics ?? [] {
            let line = "Characteristic \(c.uuid.uuidString) props=0x\(String(c.properties.rawValue, radix:16))"
            serviceLines.append(line)
            log.append("BLE \(service.uuid.uuidString) \(line)")
        }
    }

    func readReadableCharacteristics() {
        guard let p = chosen, p.state == .connected else { log.append("BLE read rejected: not connected"); return }
        for s in p.services ?? [] {
            for c in s.characteristics ?? [] where c.properties.contains(.read) {
                p.readValue(for: c)
            }
        }
        log.append("BLE readable characteristics requested (no GATT writes)")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log.append("BLE read \(characteristic.uuid.uuidString) error=\(error.localizedDescription)")
        } else {
            let payload = characteristic.value ?? Data()
            log.append("BLE read \(characteristic.uuid.uuidString) RX \(payload.count) bytes: \(HexCodec.encode(payload))")
        }
    }
}

final class ProbeWorkspace: ObservableObject {
    let log: ProbeLog
    let ea: DeepEAProbe
    let ble: DeepBLEProbe

    init() {
        let l = ProbeLog()
        log = l
        ea = DeepEAProbe(log: l)
        ble = DeepBLEProbe(log: l)
    }
}
