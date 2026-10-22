import Foundation

struct CoverageExport: Decodable {
  struct Entry: Decodable {
    struct File: Decodable {
      struct Summary: Decodable {
        struct Lines: Decodable {
          let count: Int
          let covered: Int
        }
        let lines: Lines
      }
      let filename: String
      let summary: Summary
    }
    let files: [File]
  }
  let data: [Entry]
}

func run() throws {
  guard CommandLine.arguments.count == 5 else {
    throw NSError(domain: "Coverage", code: 1, userInfo: [NSLocalizedDescriptionKey:
      "Usage: swift check-coverage.swift coverage.json repository thresholds.json summary.md"])
  }
  let arguments = CommandLine.arguments
  let root = URL(fileURLWithPath: arguments[2]).standardizedFileURL.path + "/"
  let export = try JSONDecoder().decode(CoverageExport.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
  let thresholds = try JSONDecoder().decode([String: Double].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[3])))
  let modules = ["ApiKit", "ApiKit-OAuth", "ApiKit-Google"]
  var files: [String: CoverageExport.Entry.File.Summary.Lines] = [:]
  for file in export.data.flatMap(\.files) where file.filename.hasPrefix(root) {
    let relative = String(file.filename.dropFirst(root.count))
    if modules.contains(where: { relative.hasPrefix($0 + "/Sources/") }) {
      files[relative] = file.summary.lines
    }
  }

  var report = "## Code coverage\n\nLibrary source lines only; tests and dependencies are excluded.\n\n"
  report += "| Module | Covered / executable lines | Coverage |\n| --- | ---: | ---: |\n"
  var failures: [String] = []
  for module in modules {
    let lines = files.filter { $0.key.hasPrefix(module + "/Sources/") }.map(\.value)
    let covered = lines.reduce(0) { $0 + $1.covered }
    let count = lines.reduce(0) { $0 + $1.count }
    guard count > 0 else {
      failures.append("No coverage data found for \(module)")
      continue
    }
    report += "| \(module) | \(covered) / \(count) | \(String(format: "%.2f", 100 * Double(covered) / Double(count)))% |\n"
  }

  report += "\n### Required coverage\n\n| File | Coverage | Minimum |\n| --- | ---: | ---: |\n"
  for (file, minimum) in thresholds.sorted(by: { $0.key < $1.key }) {
    guard minimum.isFinite, (0 ... 100).contains(minimum),
          let lines = files[file], lines.count > 0 else {
      failures.append("Missing coverage data or invalid threshold for \(file)")
      continue
    }
    let percent = 100 * Double(lines.covered) / Double(lines.count)
    report += "| \(file) | \(String(format: "%.2f", percent))% | \(minimum)% |\n"
    if percent < minimum {
      failures.append("\(file): \(String(format: "%.2f", percent))% is below \(minimum)%")
    }
  }
  if thresholds.isEmpty { failures.append("No coverage thresholds configured") }
  if !failures.isEmpty {
    report += "\n### Failed checks\n\n" + failures.map { "- " + $0 }.joined(separator: "\n") + "\n"
  }
  try report.write(toFile: arguments[4], atomically: true, encoding: .utf8)
  print(report)
  if !failures.isEmpty { exit(1) }
}

do { try run() } catch {
  FileHandle.standardError.write(Data("Coverage error: \(error.localizedDescription)\n".utf8))
  exit(1)
}
