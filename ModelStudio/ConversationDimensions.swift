import Foundation

/// Dimensional statements belong to one operation. Each unbound statement
/// needs its own answer, even when another statement uses the same length.
struct ConversationDimensions {
    static let example = "final span along X is 30 mm"

    private struct Missing {
        let wording: String
        let axis: ModelDimension?
    }

    private var resolved: [ModelDimension: DimensionTarget] = [:]
    private var missing: [Missing] = []
    private var unsupported: String?

    var question: String? {
        guard unsupported == nil, let first = missing.first else { return nil }
        let axis = first.axis.map { ["X", "Y", "Z"][$0.axis] } ?? "X"
        return "Restate “\(first.wording)” as a final whole-model span with its unit, for example “final span along \(axis) is 30 mm”."
    }

    func targets() throws -> [DimensionTarget] {
        if let unsupported { throw MeshImportError(unsupported) }
        if let question { throw MeshImportError(question) }
        return ModelDimension.allCases.compactMap { resolved[$0] }
    }

    // Start each turn from the user's text. The provider never supplies values
    // to this record. A bare length can answer a single-axis provider question.
    mutating func record(_ text: String, answering prompt: String? = nil) {
        let pending = missing.first
        let isRestatement = pending != nil && prompt == question
        var parsed: [DimensionTarget] = []
        var unknown: [Missing] = []
        let separated = Self.clauseBreak.stringByReplacingMatches(in: text, range: Self.range(text), withTemplate: "\n")
        let clauses = separated.components(separatedBy: "\n")
        do {
            for clause in clauses {
                try Self.parse(clause, question: isRestatement ? nil : prompt, into: &parsed, missing: &unknown)
            }
        } catch {
            unsupported = error.localizedDescription
            return
        }

        if !isRestatement, let prompt, let axis = Self.answerAxis(for: prompt), parsed.isEmpty, unknown.isEmpty {
            unknown.append(Missing(wording: text, axis: axis))
        }
        if isRestatement, let pending {
            var answered = Set(parsed.map(\.dimension))
            if let first = parsed.first(where: { pending.axis == nil || $0.dimension == pending.axis }) {
                missing.removeFirst()
                answered.remove(first.dimension)
                // Additional named axes in this answer can settle other named
                // questions. Each answer to an unnamed span serves one slot.
                missing.removeAll { item in
                    guard let axis = item.axis else { return false }
                    return answered.remove(axis) != nil
                }
            } else if parsed.isEmpty, let retry = unknown.first,
                      retry.axis == nil || pending.axis == nil || retry.axis == pending.axis {
                // The attempted replacement still needs an axis and unit. Keep
                // its original prompt and track any additional requests separately.
                unknown.removeFirst()
            }
        }
        for target in parsed {
            if let prior = resolved[target.dimension],
               prior.value * prior.unit.millimetersPerUnit != target.value * target.unit.millimetersPerUnit {
                resolved.removeValue(forKey: target.dimension)
                missing.append(Missing(wording: "conflicting \(target.dimension.label) targets, \(prior.value) \(prior.unit.symbol) and \(target.value) \(target.unit.symbol)", axis: target.dimension))
            } else {
                resolved[target.dimension] = target
            }
        }
        missing.append(contentsOf: unknown)
    }

    private static let magnitude = #"([+-]?(?:(?:\d+\s+)?\d+/\d+|(?:\d+(?:\.\d+)?|\.\d+)(?:e[+-]?\d+)?))"#
    private static let number = #"(?<![\w./])"# + magnitude
    private static let unit = #"(microns?|micromet(?:er|re)s?|[µμu]m|millimet(?:er|re)s?|mm|centimet(?:er|re)s?|cm|met(?:er|re)s?|m|inches|inch|in|feet|foot|ft)\b"#
    private static let axis = #"(width|wide|depth|deep|height|high|tall)\b"#
    private static let length = number + #"\s*"# + unit
    private static let afterAxis = expression(#"\b"# + axis + #"\s*(?:(?:of|to|is|at|=|:)\s*)?"# + length)
    private static let beforeAxis = expression(length + #"\s*"# + axis)
    private static let finalSpan = expression(#"\b(?:final\s+)?span\s+along\s+([xyz])\s*(?:is|=|:)\s*"# + length)
    private static let separator = #"\s*[×x]\s*"#
    private static let triple = expression(number + separator + magnitude + separator + magnitude + #"\s*"# + unit)
    private static let unitTriple = expression(length + separator + magnitude + #"\s*"# + unit + separator + magnitude + #"\s*"# + unit)
    private static let cube = expression(length + #"\s+cube\b"#)
    private static let axisQuestion = expression(#"^\s*what (?:should (?:the )?(?:final )?(?:width|height|depth|span along [xyz]) be|(?:is the )?(?:final )?(?:width|height|depth|span along [xyz])(?: and unit)?(?: should (?:it|the (?:block|model|object|box)) (?:be|have))?)\s*\?\s*$"#)
    private static let simpleAnswer = expression(#"^\s*"# + length + #"\s*[.!]?\s*$"#)
    private static let axisWords = expression(#"\b(width|wide|depth|deep|height|high|tall|[xyz])\b"#)
    private static let clauseBreak = expression(#"[,;!?\n]|\.(?=\s|$)|\b(?:and|with|then|but)\b"#)
    private static let unsupportedFeature = expression(#"\b(?:radius|radii|diameter|circumference|area|volume|angle|thickness|pitch|bore|fillet|degrees?|hole|holes)\b|°"#)
    private static let qualified = expression(#"\b(?:by|from|between|at least|at most|minimum|maximum|approximately|about|more than|less than|increase by|larger|smaller|extra|additional|another|double|triple|twice|half|times)\b|[<>±%]"#)
    private static let wordNumber = #"(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand)"#
    private static let spelled = #"\b"# + wordNumber + #"(?:[ -]"# + wordNumber + #")*\b"#
    private static let countOrID = expression(#"\b(?:faces?|vertices|vertex|edges?|corners?|parts?|objects?)\s+#?\d+\b(?![./]|\s*"# + unit + #")|(?:\b\d+|"# + spelled + #")\s+(?:faces?|vertices|edges?|corners?|holes?|parts?|objects?)\b|\b3d\b"#)
    private static let quantity = expression("(?:" + magnitude + "|" + spelled + #"|[¼½¾⅛⅜⅝⅞])(?:\s*"# + unit + #")?"#)
    private static let allAxes = expression(#"\b(?:all|each|every|three)\s+(?:three\s+)?(?:dimensions?|axes|spans?)\b"#)
    private static let coordinate = expression(#"\b(?:at|coordinate)\s+[xyz]\s*=\s*"# + number)
    private static let dimensionalWords = expression(#"\b(?:width|height|depth|dimensions?|span|length|radius|diameter|thickness|angle|size|long|wide|deep|tall|high|double[ds]?|triple[ds]?|twice|half|halve[ds]?|quarter|third|times|percent|scale factor|millimet(?:er|re)s?|centimet(?:er|re)s?|microns?|inches|inch|feet|foot|met(?:er|re)s?|mm|cm|ft|um)\b"#)
    // Accept a literal as a whole-model span only in an unqualified clause.
    // An unfamiliar modifier or named subpart gets a restatement, even if
    // the words inside that clause happen to match a supported span.
    private static let framing = expression(#"\b(?:3d|a|an|the|it|its|this|my|new|whole|model|block|cube|box|object|part|shape|solid|draft|make|create|build|generate|set|resize|use|give|please|to|be|of|me|is|should|have|has|at|exactly|final)\b|[.\s]"#)

    private static func expression(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }

    private static func range(_ text: String) -> NSRange { NSRange(text.startIndex..., in: text) }

    private static func axes(in text: String) -> Set<ModelDimension> {
        let source = text as NSString
        return Set(axisWords.matches(in: text, range: range(text)).map { dimension(source.substring(with: $0.range)) })
    }

    private static func answerAxis(for prompt: String) -> ModelDimension? {
        guard axisQuestion.firstMatch(in: prompt, range: range(prompt)) != nil else { return nil }
        return axes(in: prompt).first
    }

    private static func dimension(_ name: String) -> ModelDimension {
        switch name.lowercased() {
        case "wide", "width", "x": .width
        case "deep", "depth", "y": .depth
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

    private static func parse(_ clause: String, question: String?, into targets: inout [DimensionTarget],
                              missing: inout [Missing]) throws {
        let source = clause.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        let remainder = NSMutableString(string: source)
        func withoutCounts(_ text: String) -> String {
            countOrID.stringByReplacingMatches(in: text, range: range(text), withTemplate: " ")
        }
        func contains(_ regex: NSRegularExpression, _ text: String) -> Bool {
            regex.firstMatch(in: text, range: range(text)) != nil
        }
        if contains(coordinate, source) || (contains(unsupportedFeature, source) &&
            (contains(quantity, withoutCounts(source)) || contains(dimensionalWords, source))) {
            throw MeshImportError("Unsupported dimensional constraint “\(source)”. The studio measures whole-model width, depth and height.")
        }
        func consume(_ regex: NSRegularExpression, _ body: ([String]) -> Void) {
            let text = remainder as String
            let matches = regex.matches(in: text, range: range(text))
            for match in matches {
                let fields = (0..<match.numberOfRanges).map { (text as NSString).substring(with: match.range(at: $0)).lowercased() }
                body(fields)
            }
            for match in matches.reversed() { remainder.replaceCharacters(in: match.range, with: " ") }
        }
        func append(_ axis: ModelDimension, _ value: String, _ unit: String) {
            do {
                let target = DimensionTarget(dimension: axis, value: try decimal(value), unit: meshUnit(unit))
                _ = try target.millimeters()
                targets.append(target)
            } catch {
                missing.append(Missing(wording: source, axis: axis))
            }
        }
        let start = targets.count
        if !contains(qualified, source) {
            consume(unitTriple) { m in
                for a in ModelDimension.allCases { append(a, m[2 * a.axis + 1], m[2 * a.axis + 2]) }
            }
            consume(triple) { m in
                for a in ModelDimension.allCases { append(a, m[a.axis + 1], m[4]) }
            }
            consume(cube) { m in
                for a in ModelDimension.allCases { append(a, m[1], m[2]) }
            }
            consume(finalSpan) { append(dimension($0[1]), $0[2], $0[3]) }
            consume(afterAxis) { append(dimension($0[1]), $0[2], $0[3]) }
            consume(beforeAxis) { append(dimension($0[3]), $0[1], $0[2]) }
            if let question, let axis = answerAxis(for: question), contains(simpleAnswer, source) {
                consume(simpleAnswer) { append(axis, $0[1], $0[2]) }
            }
        }
        let rest = remainder as String
        let remainingAxes = axes(in: rest)
        let measures = withoutCounts(rest)
        let values = quantity.matches(in: measures, range: range(measures))
        if targets.count > start {
            let modifier = framing.stringByReplacingMatches(in: rest, range: range(rest), withTemplate: "")
            if !modifier.isEmpty {
                for target in targets[start...] {
                    missing.append(Missing(wording: source, axis: target.dimension))
                }
                targets.removeSubrange(start...)
            }
        }
        if values.isEmpty && !contains(dimensionalWords, rest) && !contains(allAxes, rest) { return }
        // If axes and values cannot be paired locally, resolve each mention.
        // A repeated numeric value still occupies its own position in the text.
        if contains(allAxes, rest) {
            for axis in ModelDimension.allCases {
                missing.append(Missing(wording: "\(axis.label) in “\(source)”", axis: axis))
            }
        } else if remainingAxes.count > 1 && remainingAxes.count >= values.count {
            for axis in ModelDimension.allCases where remainingAxes.contains(axis) {
                missing.append(Missing(wording: "\(axis.label) in “\(source)”", axis: axis))
            }
        } else if values.count > 1 {
            for value in values {
                let literal = (measures as NSString).substring(with: value.range)
                missing.append(Missing(wording: "\(literal) in “\(source)”", axis: nil))
            }
        } else if values.first?.range == range(source), let question, let axis = answerAxis(for: question) {
            // A bare quantity answering a direct span question still belongs to
            // that axis when the user needs to restate it with a unit.
            missing.append(Missing(wording: source, axis: axis))
        } else {
            missing.append(Missing(wording: source, axis: remainingAxes.first))
        }
    }
}
