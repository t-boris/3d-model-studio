import Foundation

// Bind common literal spans directly to the user's words, independently of the
// coordinates and dimension list returned by the provider. Other descriptions
// (e.g. "double its height") go through the provider's reviewed interpretation.
enum ConversationDimensions {
    private static let magnitude = #"([+-]?(?:(?:\d+\s+)?\d+/\d+|(?:\d+(?:\.\d+)?|\.\d+)(?:e[+-]?\d+)?))"#
    private static let number = #"(?<![\w./])"# + magnitude
    private static let unit = #"(microns?|micromet(?:er|re)s?|[µμu]m|millimet(?:er|re)s?|mm|centimet(?:er|re)s?|cm|met(?:er|re)s?|m|inches|inch|in|feet|foot|ft)\b"#
    private static let axis = #"(width|wide|depth|deep|height|high|tall)\b"#
    private static let length = number + #"\s*"# + unit
    private static let afterAxis = expression(#"\b"# + axis + #"\s*(?:(?:of|to|is|at|=|:)\s*)?"# + length)
    private static let beforeAxis = expression(length + #"\s*"# + axis)
    private static let separator = #"\s*[×x]\s*"#
    private static let triple = expression(number + separator + magnitude + separator + magnitude + #"\s*"# + unit)
    private static let unitTriple = expression(length + separator + magnitude + #"\s*"# + unit + separator + magnitude + #"\s*"# + unit)
    private static let cube = expression(length + #"\s+cube\b"#)
    private static let anyLength = expression(length)
    private static let simpleAnswer = expression(#"^\s*"# + length + #"\s*[.!]?\s*$"#)
    private static let questionAxis = expression(#"\b"# + axis)
    private static let unsupported = expression(#"\b(radius|diameter|angle|wall thickness|fillet radius)\s*(?:(?:of|to|is|at|=|:)\s*)?"# + number)
    private static let unsupportedAfter = expression(length + #"\s*(?:in\s+)?(diameter|radius|wall thickness)\b"#)

    private static func expression(_ pattern: String) -> NSRegularExpression {
        // All patterns are source literals.
        try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }

    private static func matches(_ regex: NSRegularExpression, in text: String) -> [[String]] {
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            (0..<match.numberOfRanges).map { source.substring(with: match.range(at: $0)).lowercased() }
        }
    }

    private static func dimension(_ name: String) -> ModelDimension {
        switch name {
        case "wide", "width": .width
        case "deep", "depth": .depth
        default: .height
        }
    }

    private static func meshUnit(_ name: String) -> MeshUnit {
        switch name {
        case "µm", "μm", "um": return .micron
        case "mm": return .millimeter
        case "cm": return .centimeter
        case "in", "inch", "inches": return .inch
        case "ft", "foot", "feet": return .foot
        default:
            if name.hasPrefix("micro") { return .micron }
            if name.hasPrefix("milli") { return .millimeter }
            if name.hasPrefix("centi") { return .centimeter }
            return .meter
        }
    }

    private static func decimal(_ text: String) throws -> Double {
        if let value = Double(text) { return value }
        let parts = text.trimmingCharacters(in: CharacterSet(charactersIn: "+-")).split(whereSeparator: \.isWhitespace)
        let fraction = parts.last?.split(separator: "/") ?? []
        guard fraction.count == 2, let numerator = Double(fraction[0]), let denominator = Double(fraction[1]),
              denominator > 0 else { throw MeshImportError("Invalid length “\(text)”.") }
        let whole = parts.count == 2 ? Double(parts[0]) ?? 0 : 0
        return (text.hasPrefix("-") ? -1 : 1) * (whole + numerator / denominator)
    }

    private static func literalTargets(in text: String, answering question: String?) throws -> [DimensionTarget] {
        if let match = (matches(unsupported, in: text) + matches(unsupportedAfter, in: text)).first {
            throw MeshImportError("Unsupported dimensional constraint: \(match[0]). The studio checks whole-model width, depth and height.")
        }
        var targets: [DimensionTarget] = []
        func append(_ axis: ModelDimension, _ value: String, _ unit: String) throws {
            targets.append(DimensionTarget(dimension: axis, value: try decimal(value), unit: meshUnit(unit)))
        }
        for match in matches(triple, in: text) {
            for axis in ModelDimension.allCases { try append(axis, match[axis.axis + 1], match[4]) }
        }
        for match in matches(unitTriple, in: text) {
            for axis in ModelDimension.allCases { try append(axis, match[2 * axis.axis + 1], match[2 * axis.axis + 2]) }
        }
        for match in matches(cube, in: text) {
            for axis in ModelDimension.allCases { try append(axis, match[1], match[2]) }
        }
        for match in matches(afterAxis, in: text) { try append(dimension(match[1]), match[2], match[3]) }
        for match in matches(beforeAxis, in: text) { try append(dimension(match[3]), match[1], match[2]) }
        if let question, let answer = matches(simpleAnswer, in: text).first {
            let axes = Set(matches(questionAxis, in: question).map { dimension($0[1]) })
            if axes.count == 1, let axis = axes.first { try append(axis, answer[1], answer[2]) }
        }
        return targets
    }

    static func targets(input: ModelingInput, interpreted: [DimensionTarget],
                        original: WorkspaceModel? = nil) throws -> [DimensionTarget] {
        var literal: [ModelDimension: DimensionTarget] = [:]
        func record(_ text: String, question: String?) throws {
            let targets = try literalTargets(in: text, answering: question)
            for target in targets { literal[target.dimension] = target }

            // A recognized length that the provider silently drops must not
            // disappear just because some other dimension was understood.
            var accountedMM = try (targets + interpreted).map { try $0.millimeters() }
            if let original {
                for target in interpreted {
                    let start = original.extents[target.dimension.axis] * original.unit.millimetersPerUnit
                    accountedMM.append(start)
                    accountedMM.append(abs(try target.millimeters() - start))
                }
            }
            for match in matches(anyLength, in: text) {
                let mm = try decimal(match[1]) * meshUnit(match[2]).millimetersPerUnit
                guard accountedMM.contains(where: { DimensionTarget.matches(measuredMM: $0, targetMM: mm) }) else {
                    throw MeshImportError("No checkable span accounts for “\(match[0])”. Specify the final width, depth or height and its unit.")
                }
            }
        }
        try record(input.instruction, question: nil)
        for exchange in input.clarifications { try record(exchange.answer, question: exchange.question) }
        // Keep both checks when the agent supplies a different value. An agent
        // cannot replace a user's literal dimension with its own measurement.
        var result = ModelDimension.allCases.compactMap { literal[$0] }
        for target in interpreted where !result.contains(target) { result.append(target) }
        return result
    }
}
