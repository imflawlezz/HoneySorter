import Foundation

enum FileArchiveService {

  nonisolated static func zipDirectory(
    _ directory: URL,
    archiveDirectory: URL,
    archiveBaseName: String
  ) throws -> URL {
    let fm = FileManager.default
    guard fm.fileExists(atPath: directory.path) else {
      throw RenameError.sourceNotFound(directory.lastPathComponent)
    }

    let sanitized = sanitizeArchiveBaseName(archiveBaseName, fallback: "Sorted")
    var archiveURL = archiveDirectory.appendingPathComponent("\(sanitized).zip")
    archiveURL = uniqueArchiveURL(startingAt: archiveURL, fileManager: fm)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.currentDirectoryURL = directory.deletingLastPathComponent()
    process.arguments = ["-r", "-q", archiveURL.path, directory.lastPathComponent]

    let stderr = Pipe()
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      let errData = stderr.fileHandleForReading.readDataToEndOfFile()
      let message = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
      try? fm.removeItem(at: archiveURL)
      throw RenameError.archiveFailed(message?.isEmpty == false ? message! : "zip exited with code \(process.terminationStatus)")
    }

    guard fm.fileExists(atPath: archiveURL.path) else {
      throw RenameError.archiveFailed("Archive was not created.")
    }

    return archiveURL
  }

  nonisolated private static func sanitizeArchiveBaseName(_ input: String, fallback: String) -> String {
    var name = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty { name = fallback }
    if name.lowercased().hasSuffix(".zip") {
      name = String(name.dropLast(4))
    }
    let invalid = CharacterSet(charactersIn: "/:\\0")
    name = name.components(separatedBy: invalid).joined(separator: "_")
    name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty { name = "Sorted" }
    return name
  }

  nonisolated private static func uniqueArchiveURL(startingAt url: URL, fileManager: FileManager) -> URL {
    guard fileManager.fileExists(atPath: url.path) else { return url }
    let base = url.deletingPathExtension().lastPathComponent
    let parent = url.deletingLastPathComponent()
    var n = 1
    while true {
      let candidate = parent.appendingPathComponent("\(base) (\(n)).zip")
      if !fileManager.fileExists(atPath: candidate.path) { return candidate }
      n += 1
    }
  }
}
