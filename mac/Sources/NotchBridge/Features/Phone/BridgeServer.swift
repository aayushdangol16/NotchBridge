import Foundation
import Network

/// WebSocket server on the LAN, advertised over Bonjour as `_notchbridge._tcp`.
/// The phone is the client. Only a client that can encrypt with the paired key is accepted.
final class BridgeServer {
    enum Status: Equatable {
        case starting
        case waiting            // listening, no phone
        case connected(String)  // phone name
        case failed(String)
    }

    static let serviceType = "_notchbridge._tcp"
    static let badKeyCloseCode: UInt16 = 4001

    /// Delivered on the main queue.
    var onStatus: ((Status) -> Void)?
    var onMessage: ((PhoneMessage) -> Void)?

    private let queue = DispatchQueue(label: "notchbridge.server")
    private let pairing = Pairing.shared
    private var listener: NWListener?
    private var phone: NWConnection?
    private var unauthenticated: [ObjectIdentifier: NWConnection] = [:]
    private var status: Status = .starting

    func start() {
        queue.async { self.startListener() }
    }

    /// Drop the current phone (e.g. after the pairing key was reset).
    func disconnectPhone() {
        queue.async {
            self.phone?.cancel()
            self.phone = nil
            self.unauthenticated.values.forEach { $0.cancel() }
            self.unauthenticated.removeAll()
            self.setStatus(.waiting)
        }
    }

    func send(_ command: MacCommand) {
        queue.async {
            guard let phone = self.phone else { return }
            self.send(command, on: phone)
        }
    }

    // MARK: - Listener

    private func startListener() {
        listener?.cancel()

        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        ws.maximumMessageSize = 16 * 1024 * 1024

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)

        do {
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Pairing.port)!)
            let txt = NWTXTRecord(["id": pairing.macId])
            l.service = NWListener.Service(name: pairing.macName, type: Self.serviceType, domain: nil, txtRecord: txt)
            l.stateUpdateHandler = { [weak self] state in self?.listenerState(state) }
            l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            listener = l
            l.start(queue: queue)
        } catch {
            setStatus(.failed("Could not open port \(Pairing.port): \(error.localizedDescription)"))
            retryListener()
        }
    }

    private func listenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if phone == nil { setStatus(.waiting) }
        case .failed(let error):
            setStatus(.failed("Listener failed: \(error.localizedDescription)"))
            retryListener()
        case .waiting(let error):
            setStatus(.failed("Waiting for network: \(error.localizedDescription)"))
        default:
            break
        }
    }

    private func retryListener() {
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in self?.startListener() }
    }

    // MARK: - Connections

    private func accept(_ conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        unauthenticated[id] = conn
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self, let conn else { return }
            switch state {
            case .failed, .cancelled:
                self.unauthenticated.removeValue(forKey: ObjectIdentifier(conn))
                if self.phone === conn {
                    self.phone = nil
                    self.setStatus(.waiting)
                }
            default:
                break
            }
        }
        conn.start(queue: queue)
        receive(on: conn)
        // A client that never authenticates is dropped.
        queue.asyncAfter(deadline: .now() + 15) { [weak self, weak conn] in
            guard let self, let conn, self.unauthenticated[ObjectIdentifier(conn)] != nil else { return }
            conn.cancel()
        }
    }

    private func receive(on conn: NWConnection) {
        conn.receiveMessage { [weak self, weak conn] content, context, _, error in
            guard let self, let conn else { return }
            if let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
               meta.opcode == .close {
                conn.cancel()
                return
            }
            if let content, !content.isEmpty {
                self.handle(content, from: conn)
            }
            if error == nil, conn.state != .cancelled {
                self.receive(on: conn)
            } else {
                conn.cancel()
            }
        }
    }

    private func handle(_ box: Data, from conn: NWConnection) {
        let message: PhoneMessage
        do {
            let plain = try pairing.open(box)
            message = try JSONDecoder().decode(PhoneMessage.self, from: plain)
        } catch {
            // Wrong key (phone paired with an old QR code) or garbage: tell the phone and drop it.
            close(conn, code: Self.badKeyCloseCode)
            return
        }

        let id = ObjectIdentifier(conn)
        if unauthenticated[id] != nil {
            guard message.type == "hello" else { return }
            unauthenticated.removeValue(forKey: id)
            if let old = phone, old !== conn { old.cancel() }
            phone = conn
            let name = message.device ?? "Android phone"
            pairing.pairedDevice = name
            send(MacCommand(type: "welcome", name: pairing.macName), on: conn)
            setStatus(.connected(name))
        }
        guard phone === conn else { return }

        DispatchQueue.main.async { self.onMessage?(message) }
    }

    private func send(_ command: MacCommand, on conn: NWConnection) {
        guard let json = try? JSONEncoder().encode(command),
              let box = try? pairing.seal(json) else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .binary)
        let ctx = NWConnection.ContentContext(identifier: "cmd", metadata: [meta])
        conn.send(content: box, contentContext: ctx, isComplete: true, completion: .contentProcessed { _ in })
    }

    private func close(_ conn: NWConnection, code: UInt16) {
        let meta = NWProtocolWebSocket.Metadata(opcode: .close)
        meta.closeCode = .privateCode(code)
        let ctx = NWConnection.ContentContext(identifier: "close", metadata: [meta])
        conn.send(content: nil, contentContext: ctx, isComplete: true, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    private func setStatus(_ s: Status) {
        guard s != status else { return }
        status = s
        DispatchQueue.main.async { self.onStatus?(s) }
    }
}
