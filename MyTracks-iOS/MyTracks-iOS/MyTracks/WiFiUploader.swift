import Foundation
import Network
import SwiftUI

// MARK: - Local Wi-Fi Address Helper

private func getLocalWiFiAddress() -> String? {
    var address: String?
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
    defer { freeifaddrs(ifaddr) }

    for ptr in sequence(first: firstAddr, by: { $0.pointee.ifa_next }) {
        let interface = ptr.pointee
        let addrFamily = interface.ifa_addr.pointee.sa_family
        if addrFamily == UInt8(AF_INET) {
            let name = String(cString: interface.ifa_name)
            // en0 is primary Wi-Fi interface on iOS devices
            if name == "en0" || name == "en1" {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(
                    interface.ifa_addr,
                    socklen_t(interface.ifa_addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    socklen_t(0),
                    NI_NUMERICHOST
                )
                address = String(cString: hostname)
                if name == "en0" { break }
            }
        }
    }
    return address
}

// MARK: - Wi-Fi Uploader Server

final class WiFiUploader: ObservableObject {
    @Published var isRunning = false
    @Published var ipAddress: String?
    @Published var port: UInt16 = 8080
    @Published var uploadedSongs: [String] = []
    @Published var errorMessage: String?

    var serverURL: String? {
        guard let ip = ipAddress else { return nil }
        return "http://\(ip):\(port)"
    }

    private var listener: NWListener?
    weak var library: Library?

    func start() {
        stop()
        guard let ip = getLocalWiFiAddress() else {
            errorMessage = "Please connect your iPhone to a Wi-Fi network first."
            return
        }
        ipAddress = ip
        errorMessage = nil

        do {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
            let l = try NWListener(using: .tcp, on: nwPort)

            l.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                    case .failed(let err):
                        self?.errorMessage = err.localizedDescription
                        self?.stop()
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }

            l.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            l.start(queue: .global(qos: .userInitiated))
            listener = l
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    deinit {
        stop()
    }

    // MARK: - Connection & HTTP Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))

        var buffer = Data()
        var headersParsed = false
        var isUpload = false
        var targetFileName: String?
        var originalSongName: String?
        var contentLength = 0
        var bytesWritten = 0
        var fileHandle: FileHandle?

        func cleanUp() {
            try? fileHandle?.close()
            fileHandle = nil
            connection.cancel()
        }

        func sendResponse(status: String, contentType: String, body: Data) {
            let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
            var respData = Data(header.utf8)
            respData.append(body)
            connection.send(content: respData, completion: .contentProcessed { _ in
                cleanUp()
            })
        }

        func receiveNext() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
                guard let self = self else { cleanUp(); return }
                if error != nil {
                    cleanUp()
                    return
                }

                if let data = data, !data.isEmpty {
                    if !headersParsed {
                        buffer.append(data)
                        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])
                        if let range = buffer.range(of: separator) {
                            headersParsed = true
                            let headerData = buffer.subdata(in: 0..<range.lowerBound)
                            let bodyData = buffer.subdata(in: range.upperBound..<buffer.count)

                            guard let headerString = String(data: headerData, encoding: .utf8) else {
                                sendResponse(status: "400 Bad Request", contentType: "text/plain", body: Data("Bad Request".utf8))
                                return
                            }

                            let lines = headerString.components(separatedBy: "\r\n")
                            guard let requestLine = lines.first else {
                                sendResponse(status: "400 Bad Request", contentType: "text/plain", body: Data("Bad Request".utf8))
                                return
                            }

                            let parts = requestLine.components(separatedBy: " ")
                            guard parts.count >= 2 else {
                                sendResponse(status: "400 Bad Request", contentType: "text/plain", body: Data("Bad Request".utf8))
                                return
                            }

                            let method = parts[0].uppercased()
                            let rawPath = parts[1]

                            if method == "GET" && (rawPath == "/" || rawPath == "/index.html") {
                                let html = self.htmlPage()
                                sendResponse(status: "200 OK", contentType: "text/html; charset=utf-8", body: Data(html.utf8))
                                return
                            } else if method == "POST" && rawPath.starts(with: "/upload") {
                                isUpload = true

                                // Parse query param name
                                var rawName = "Uploaded Song.mp3"
                                if let urlComponents = URLComponents(string: rawPath),
                                   let qName = urlComponents.queryItems?.first(where: { $0.name == "name" })?.value,
                                   !qName.isEmpty {
                                    rawName = qName.removingPercentEncoding ?? qName
                                }

                                let cleanName = (rawName as NSString).deletingPathExtension
                                originalSongName = cleanName.isEmpty ? "Song" : cleanName
                                let ext = (rawName as NSString).pathExtension.lowercased()
                                let fileExt = ext.isEmpty ? "mp3" : ext
                                let stored = UUID().uuidString + "." + fileExt
                                targetFileName = stored

                                // Extract Content-Length
                                for line in lines {
                                    let lower = line.lowercased()
                                    if lower.starts(with: "content-length:") {
                                        let val = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                                        contentLength = Int(val) ?? 0
                                    }
                                }

                                // Create destination file in Documents directory
                                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                                let destURL = docs.appendingPathComponent(stored)
                                FileManager.default.createFile(atPath: destURL.path, contents: nil, attributes: nil)
                                fileHandle = try? FileHandle(forWritingTo: destURL)

                                if !bodyData.isEmpty {
                                    try? fileHandle?.write(contentsOf: bodyData)
                                    bytesWritten += bodyData.count
                                }

                                if bytesWritten >= contentLength && contentLength > 0 {
                                    self.finishUpload(name: originalSongName ?? "Song", stored: stored)
                                    sendResponse(status: "200 OK", contentType: "application/json", body: Data("{\"status\":\"ok\"}".utf8))
                                    return
                                }
                            } else {
                                sendResponse(status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8))
                                return
                            }
                        }
                    } else if isUpload {
                        try? fileHandle?.write(contentsOf: data)
                        bytesWritten += data.count
                        if bytesWritten >= contentLength && contentLength > 0 {
                            self.finishUpload(name: originalSongName ?? "Song", stored: targetFileName ?? "song.mp3")
                            sendResponse(status: "200 OK", contentType: "application/json", body: Data("{\"status\":\"ok\"}".utf8))
                            return
                        }
                    }
                }

                if isComplete {
                    if isUpload && bytesWritten > 0, let fn = targetFileName {
                        self.finishUpload(name: originalSongName ?? "Song", stored: fn)
                        sendResponse(status: "200 OK", contentType: "application/json", body: Data("{\"status\":\"ok\"}".utf8))
                    } else {
                        cleanUp()
                    }
                    return
                }

                receiveNext()
            }
        }

        receiveNext()
    }

    private func finishUpload(name: String, stored: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.uploadedSongs.insert(name, at: 0)
            self.library?.addSong(name: name, fileName: stored)
        }
    }

    // MARK: - HTML Page Served to Laptop Browser

    private func htmlPage() -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>MyTracks Wi-Fi Transfer</title>
          <style>
            :root {
              --bg: #121216;
              --card: #1e1e24;
              --accent: #6366f1;
              --accent-hover: #4f46e5;
              --text: #f3f4f6;
              --muted: #9ca3af;
              --border: #2e2e38;
              --success: #10b981;
            }
            * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
            body {
              background: var(--bg);
              color: var(--text);
              display: flex;
              justify-content: center;
              align-items: center;
              min-height: 100vh;
              padding: 24px;
            }
            .container {
              width: 100%;
              max-width: 580px;
              background: var(--card);
              border: 1px solid var(--border);
              border-radius: 20px;
              padding: 36px 32px;
              box-shadow: 0 20px 40px rgba(0,0,0,0.4);
            }
            .header {
              text-align: center;
              margin-bottom: 28px;
            }
            .icon {
              font-size: 48px;
              margin-bottom: 12px;
            }
            h1 {
              font-size: 24px;
              font-weight: 700;
              margin-bottom: 8px;
              background: linear-gradient(135deg, #a5b4fc, #818cf8);
              -webkit-background-clip: text;
              -webkit-text-fill-color: transparent;
            }
            p.sub {
              color: var(--muted);
              font-size: 14px;
              line-height: 1.5;
            }
            .dropzone {
              border: 2px dashed var(--border);
              border-radius: 16px;
              padding: 40px 20px;
              text-align: center;
              background: rgba(255, 255, 255, 0.02);
              cursor: pointer;
              transition: all 0.2s ease;
            }
            .dropzone.hover {
              border-color: var(--accent);
              background: rgba(99, 102, 241, 0.08);
            }
            .drop-icon {
              font-size: 36px;
              margin-bottom: 12px;
            }
            .drop-text {
              font-size: 16px;
              font-weight: 600;
              margin-bottom: 6px;
            }
            .drop-sub {
              font-size: 13px;
              color: var(--muted);
              margin-bottom: 18px;
            }
            .btn {
              display: inline-block;
              background: var(--accent);
              color: #fff;
              font-weight: 600;
              padding: 10px 24px;
              border-radius: 999px;
              font-size: 14px;
              cursor: pointer;
              border: none;
              transition: background 0.2s;
            }
            .btn:hover { background: var(--accent-hover); }
            input[type="file"] { display: none; }
            .progress-container {
              margin-top: 24px;
              display: none;
            }
            .progress-bar {
              height: 8px;
              width: 100%;
              background: var(--border);
              border-radius: 999px;
              overflow: hidden;
              margin-bottom: 8px;
            }
            .progress-fill {
              height: 100%;
              width: 0%;
              background: linear-gradient(90deg, #6366f1, #10b981);
              transition: width 0.2s ease;
            }
            .progress-label {
              font-size: 13px;
              color: var(--muted);
              text-align: center;
            }
            .file-list {
              margin-top: 28px;
              border-top: 1px solid var(--border);
              padding-top: 20px;
              display: none;
            }
            .file-list h3 {
              font-size: 14px;
              color: var(--muted);
              text-transform: uppercase;
              letter-spacing: 0.05em;
              margin-bottom: 12px;
            }
            .file-item {
              display: flex;
              align-items: center;
              justify-content: space-between;
              padding: 10px 14px;
              background: rgba(255,255,255,0.03);
              border-radius: 10px;
              margin-bottom: 8px;
              font-size: 14px;
            }
            .file-item .check {
              color: var(--success);
              font-weight: bold;
              font-size: 16px;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">
              <div class="icon">🎵</div>
              <h1>MyTracks Wi-Fi Transfer</h1>
              <p class="sub">Upload MP3 and audio files from your laptop directly to your iPhone</p>
            </div>

            <div class="dropzone" id="dropzone">
              <div class="drop-icon">📥</div>
              <div class="drop-text">Drag & drop audio files here</div>
              <div class="drop-sub">Supports MP3, M4A, WAV, AAC, FLAC</div>
              <label class="btn" for="fileInput">Choose Files</label>
              <input type="file" id="fileInput" multiple accept="audio/*,.mp3,.m4a,.wav,.aac,.flac">
            </div>

            <div class="progress-container" id="progressContainer">
              <div class="progress-bar">
                <div class="progress-fill" id="progressFill"></div>
              </div>
              <div class="progress-label" id="progressLabel">Uploading...</div>
            </div>

            <div class="file-list" id="fileList">
              <h3>Uploaded Songs</h3>
              <div id="fileItems"></div>
            </div>
          </div>

          <script>
            const dropzone = document.getElementById('dropzone');
            const fileInput = document.getElementById('fileInput');
            const progressContainer = document.getElementById('progressContainer');
            const progressFill = document.getElementById('progressFill');
            const progressLabel = document.getElementById('progressLabel');
            const fileList = document.getElementById('fileList');
            const fileItems = document.getElementById('fileItems');

            ['dragenter', 'dragover'].forEach(name => {
              dropzone.addEventListener(name, (e) => {
                e.preventDefault();
                e.stopPropagation();
                dropzone.classList.add('hover');
              });
            });

            ['dragleave', 'drop'].forEach(name => {
              dropzone.addEventListener(name, (e) => {
                e.preventDefault();
                e.stopPropagation();
                dropzone.classList.remove('hover');
              });
            });

            dropzone.addEventListener('drop', (e) => {
              const files = e.dataTransfer.files;
              if (files.length > 0) handleFiles(files);
            });

            fileInput.addEventListener('change', () => {
              if (fileInput.files.length > 0) handleFiles(fileInput.files);
            });

            async function handleFiles(files) {
              progressContainer.style.display = 'block';
              fileList.style.display = 'block';

              const total = files.length;
              for (let i = 0; i < total; i++) {
                const file = files[i];
                progressLabel.textContent = `Uploading ${i + 1} of ${total}: ${file.name}`;
                progressFill.style.width = `${Math.round(((i) / total) * 100)}%`;

                try {
                  const url = '/upload?name=' + encodeURIComponent(file.name);
                  await fetch(url, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/octet-stream' },
                    body: file
                  });

                  const item = document.createElement('div');
                  item.className = 'file-item';
                  item.innerHTML = `<span>🎵 ${file.name}</span><span class="check">✓</span>`;
                  fileItems.prepend(item);
                } catch (err) {
                  console.error(err);
                }
              }

              progressFill.style.width = '100%';
              progressLabel.textContent = `Successfully uploaded ${total} song(s)!`;
              fileInput.value = '';
            }
          </script>
        </body>
        </html>
        """
    }
}
