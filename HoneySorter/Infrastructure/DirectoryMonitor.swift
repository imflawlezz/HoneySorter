import Darwin
import Foundation

final class DirectoryMonitor {
    private var monitorSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    func start(url: URL, onEvent: @escaping () -> Void) {
        stop()
        let fd = open(url.path(percentEncoded: false), O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename], queue: .main
        )
        source.setEventHandler { onEvent() }
        source.setCancelHandler { [fd] in close(fd) }
        source.resume()
        monitorSource = source
    }

    func stop() {
        monitorSource?.cancel()
        monitorSource = nil
        fileDescriptor = -1
    }

    deinit { stop() }
}
