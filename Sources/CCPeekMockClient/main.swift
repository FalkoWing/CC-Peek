import Foundation
import CCPeekCore

// CLI mock iPhone 客户端. 用途: 在没有真机时验证 Transport 协议联调.
//
// 使用:
//   swift run CCPeekMockClient
// 之后在 stdin 输入:
//   snapshot                  -> 重发 snapshot_request
//   switch <process_id>       -> 发 switch_to
//   quit | exit               -> 退出

let displayName = ProcessInfo.processInfo.environment["CCPEEK_MOCK_NAME"]
    ?? "MockiPhone-\(Int.random(in: 1000...9999))"

print("[mock] starting as '\(displayName)' (role=client, service=\(TransportServiceType.mvp))")
print("[mock] commands: snapshot | switch <process_id> | quit")

let transport = MPCTransport(displayName: displayName, role: .client)

// 主队列状态. MPC 回调全在主队列, 这里读写不需要锁.
var currentHost: TransportPeer?

transport.onPeerDiscovered = { peer in
    print("[mock] discovered: \(peer.displayName)")
}

transport.onPeerConnected = { peer in
    print("[mock] connected: \(peer.displayName)")
    currentHost = peer
    do {
        try transport.send(.snapshotRequest, to: peer)
        print("[mock] -> snapshot_request")
    } catch {
        print("[mock] failed to request snapshot: \(error)")
    }
}

transport.onPeerDisconnected = { peer in
    print("[mock] disconnected: \(peer.displayName)")
    if currentHost?.id == peer.id { currentHost = nil }
}

transport.onPeerLost = { peer in
    print("[mock] lost: \(peer.displayName)")
}

transport.onReceive = { message, peer in
    print("[mock] <- from \(peer.displayName):")
    if let pretty = prettyJSON(message) {
        print(pretty)
    } else {
        print("  (\(message))")
    }
}

func prettyJSON(_ message: TransportMessage) -> String? {
    guard let data = try? TransportCoding.encode(message),
          let obj = try? JSONSerialization.jsonObject(with: data),
          let pretty = try? JSONSerialization.data(
              withJSONObject: obj,
              options: [.prettyPrinted, .sortedKeys]
          )
    else { return nil }
    return String(data: pretty, encoding: .utf8)
}

transport.start()

// stdin 命令循环 (后台线程, 不阻塞 RunLoop).
DispatchQueue.global(qos: .userInitiated).async {
    while let line = readLine() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { continue }
        DispatchQueue.main.async { handleCommand(trimmed) }
    }
}

func handleCommand(_ cmd: String) {
    if cmd == "quit" || cmd == "exit" {
        print("[mock] bye")
        transport.stop()
        exit(0)
    }
    if cmd == "snapshot" {
        guard let host = currentHost else {
            print("[mock] not connected to any host")
            return
        }
        do {
            try transport.send(.snapshotRequest, to: host)
            print("[mock] -> snapshot_request")
        } catch {
            print("[mock] send failed: \(error)")
        }
        return
    }
    if cmd.hasPrefix("switch ") {
        let pid = String(cmd.dropFirst("switch ".count)).trimmingCharacters(in: .whitespaces)
        guard !pid.isEmpty else {
            print("[mock] usage: switch <process_id>")
            return
        }
        guard let host = currentHost else {
            print("[mock] not connected to any host")
            return
        }
        do {
            try transport.send(.switchTo(.init(processId: pid)), to: host)
            print("[mock] -> switch_to(\(pid))")
        } catch {
            print("[mock] send failed: \(error)")
        }
        return
    }
    print("[mock] unknown command: \(cmd)")
}

signal(SIGINT) { _ in
    print("\n[mock] interrupted, exiting")
    exit(0)
}

RunLoop.main.run()
