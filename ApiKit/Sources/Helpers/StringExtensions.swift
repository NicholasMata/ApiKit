//
//  StringExtensions.swift
//
//
//  Created by Nicholas Mata on 6/14/22.
//

import Foundation

extension String {
  func repeating(count: Int) -> String {
    return String(repeating: self, count: count)
  }

  func boxed(top: String? = "=", bottom: String? = "=", largestLine: Int? = nil, centered: Bool = false) -> String {
    let lines = split(separator: "\n")
    guard let largestLine = largestLine ?? lines.max(by: { $0.count < $1.count })?.count else {
      return ""
    }
    var largestLineCount = largestLine + 2
    let remainder = largestLineCount % 2
    if remainder != 0 {
      largestLineCount += remainder
    }
    var boxedText = ""
    if let topLine = top?.repeating(count: largestLineCount) {
      boxedText += topLine + "\n"
    }
    lines.forEach { line in
      if centered {
        let padding = (largestLineCount - line.count) / 2
        let paddingText = " ".repeating(count: padding)
        let lineWithPadding = "\(paddingText)\(line)\(paddingText)"
        boxedText += lineWithPadding + "\n"
      } else {
        boxedText += " " + line + "\n"
      }
    }
    if let bottomLine = bottom?.repeating(count: largestLineCount) {
      boxedText += bottomLine
    }
    return boxedText
  }
}
