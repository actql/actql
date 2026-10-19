///|
pub(all) struct ExpressionLimits {
  lexical : LexicalLimits
  max_nodes : Int
  max_depth : Int
  max_work : Int
}

///|
pub(all) struct NamePart {
  value : String
  quoted : Bool
} derive(Eq, Debug)

///|
// This source AST is not a checked expression or an execution capability.
// Child indices belong to the containing Expression owner, never another AST.
pub(all) enum ExpressionKind {
  Null
  Boolean(Bool)
  Number(String)
  StringLiteral(String)
  JsonLiteral(String)
  Reference(Array[NamePart])
  ParameterReference(String)
  Property(Int, NamePart)
  Unary(String, Int)
  Binary(String, Int, Int)
  Call(Array[NamePart], Array[Int])
  ArrayConstructor(Array[Int], ArrayElementType?)
  Parenthesized(Int)
  Predicate(String, Array[Int])
  SearchedCase(Array[(Int, Int)], Int)
  Cast(Int, CastType)
} derive(Eq, Debug)

///|
pub(all) enum ArrayElementType {
  Boolean
  String
  Number
  Timestamp
  Json
} derive(Eq, Debug)

///|
pub(all) enum CastType {
  Boolean
  String
  Number
  Timestamp
  Decimal(Int, Int)
} derive(Eq, Debug)

///|
pub struct ExpressionNode {
  kind : ExpressionKind
  start : Int
  end : Int
}

///|
struct Expression {
  source : Tokens
  nodes : Array[ExpressionNode]
  root : Int
  work : Int
}

///|
pub fn expression_root(expression : Expression) -> Int {
  expression.root
}

///|
pub fn expression_node_count(expression : Expression) -> Int {
  expression.nodes.length()
}

///|
pub fn expression_work(expression : Expression) -> Int {
  expression.work
}

///|
pub fn expression_node(expression : Expression, index : Int) -> ExpressionNode? {
  if index < 0 || index >= expression.nodes.length() {
    return None
  }
  // Copy array-bearing source nodes so observation cannot mutate the owner.
  let node = expression.nodes[index]
  let kind = match node.kind {
    Reference(parts) => Reference(parts.copy())
    Call(parts, args) => Call(parts.copy(), args.copy())
    ArrayConstructor(items, target) => ArrayConstructor(items.copy(), target)
    Predicate(op, args) => Predicate(op, args.copy())
    SearchedCase(branches, otherwise) =>
      SearchedCase(branches.copy(), otherwise)
    kind => kind
  }
  Some({ ..node, kind, })
}

///|
// A child retains the parsed owner and source spans; it is never reparsed.
pub fn expression_child(expression : Expression, index : Int) -> Expression? {
  expression_subtree(expression, index, [])
}

///|
// A compiler may bind proven evaluated subtrees to private physical fields.
// This preserves source spans and work evidence; it does not evaluate an AST.
pub fn expression_with_field_bindings(
  expression : Expression,
  bindings : Array[(Int, NamePart)],
) -> Expression? {
  expression_subtree(expression, expression.root, bindings)
}

///|
fn expression_subtree(
  expression : Expression,
  index : Int,
  bindings : Array[(Int, NamePart)],
) -> Expression? {
  if index < 0 || index >= expression.nodes.length() {
    return None
  }
  let fields : Array[NamePart?] = Array::make(expression.nodes.length(), None)
  for (node, field) in bindings {
    if node < 0 || node >= fields.length() || fields[node] is Some(_) {
      return None
    }
    fields[node] = Some(field)
  }
  let reachable = Array::make(expression.nodes.length(), false)
  let pending = [index]
  while !pending.is_empty() {
    let next = pending.pop().unwrap()
    if reachable[next] {
      continue
    }
    reachable[next] = true
    if fields[next] is Some(_) {
      continue
    }
    match expression.nodes[next].kind {
      Unary(_, child)
      | Parenthesized(child)
      | Cast(child, _)
      | Property(child, _) => pending.push(child)
      Binary(_, left, right) => {
        pending.push(left)
        pending.push(right)
      }
      Call(_, arguments)
      | Predicate(_, arguments)
      | ArrayConstructor(arguments, _) =>
        for argument in arguments {
          pending.push(argument)
        }
      SearchedCase(branches, otherwise) => {
        pending.push(otherwise)
        for branch in branches {
          pending.push(branch.0)
          pending.push(branch.1)
        }
      }
      _ => ()
    }
  }
  let remap = Array::make(expression.nodes.length(), -1)
  let mut count = 0
  for old in 0..<reachable.length() {
    if reachable[old] {
      remap[old] = count
      count += 1
    }
  }
  let nodes : Array[ExpressionNode] = []
  for old in 0..<reachable.length() {
    if !reachable[old] {
      continue
    }
    let node = expression.nodes[old]
    let kind = if fields[old] is Some(field) {
      Reference([field])
    } else {
      match node.kind {
        Unary(op, child) => Unary(op, remap[child])
        Binary(op, left, right) => Binary(op, remap[left], remap[right])
        Parenthesized(child) => Parenthesized(remap[child])
        Cast(child, target) => Cast(remap[child], target)
        Property(child, name) => Property(remap[child], name)
        Call(path, arguments) =>
          Call(path.copy(), arguments.map(argument => remap[argument]))
        ArrayConstructor(items, target) =>
          ArrayConstructor(items.map(item => remap[item]), target)
        Predicate(op, arguments) =>
          Predicate(op, arguments.map(argument => remap[argument]))
        SearchedCase(branches, otherwise) =>
          SearchedCase(
            branches.map(branch => (remap[branch.0], remap[branch.1])),
            remap[otherwise],
          )
        Reference(path) => Reference(path.copy())
        kind => kind
      }
    }
    nodes.push({ ..node, kind, })
  }
  Some({ ..expression, nodes, root: remap[index], })
}

///|
pub fn expression_origin(
  expression : Expression,
  index : Int,
) -> @origin.Origin? {
  if index < 0 || index >= expression.nodes.length() {
    return None
  }
  let node = expression.nodes[index]
  Some(@origin.range(expression.source.document, node.start, node.end).unwrap())
}

///|
priv enum ExpressionFrame {
  Enter(Int, Int)
  Tail(Int, Int, Int)
  Prefix(String, Int)
  BinaryRight(String, Int, Int, Int)
  CloseGroup(Int)
  Argument(Array[NamePart], Array[Int], Int, Int)
  ArrayItem(Array[Int], ArrayElementType?, Int, Int)
  BetweenLower(Int, Bool, Int, Int)
  BetweenUpper(Int, Int, Bool, Int, Int)
  InItem(Int, Bool, Array[Int], Int, Int)
  InUnnest(Int, Bool, Int, Int)
  IsDistinct(Int, Bool, Int, Int)
  CaseCondition(Array[(Int, Int)], Int, Int)
  CaseValue(Array[(Int, Int)], Int, Int, Int)
  CaseElse(Array[(Int, Int)], Int)
  CastTarget(Int)
}

///|
priv suberror ExpressionAbort {
  ExpressionAbort(String, Int)
  ExpressionDiagnostic(Diagnostic)
}

///|
priv struct ExpressionParser {
  source : Tokens
  limits : ExpressionLimits
  nodes : Array[ExpressionNode]
  depths : Array[Int]
  mut offset : Int
  mut work : Int
  mut embedded_nodes : Int
  stop_before_star : Bool
  primary : ((Int, ExpressionLimits) -> Result[
    (NamePart, Int, Int, Int)?,
    Diagnostic,
  ])?
}

///|
fn upper_ascii(value : String) -> String {
  let out = StringBuilder()
  for unit in value {
    let n = unit.to_int()
    out.write_char(
      (if n >= 97 && n <= 122 { n - 32 } else { n }).unsafe_to_char(),
    )
  }
  out.to_string()
}

///|
fn ExpressionParser::peek(self : ExpressionParser) -> Token {
  self.source.tokens[self.offset]
}

///|
fn ExpressionParser::advance(
  self : ExpressionParser,
) -> Token raise ExpressionAbort {
  let token = self.peek()
  if token.value == End {
    raise ExpressionAbort("Expected expression", token.start)
  }
  self.offset += 1
  token
}

///|
fn ExpressionParser::spend(
  self : ExpressionParser,
) -> Unit raise ExpressionAbort {
  if self.work >= self.limits.max_work {
    raise ExpressionAbort("Expression work limit", self.peek().start)
  }
  self.work += 1
}

///|
fn ExpressionParser::add(
  self : ExpressionParser,
  kind : ExpressionKind,
  start : Int,
  end : Int,
) -> Int raise ExpressionAbort {
  if self.nodes.length() + self.embedded_nodes >= self.limits.max_nodes {
    raise ExpressionAbort("Expression node limit", start)
  }
  // Postfix chains do not enter a recursive Pratt continuation. Measure their
  // actual source tree depth from the already admitted children instead.
  let mut child_depth = 0
  match kind {
    Unary(_, child)
    | Parenthesized(child)
    | Cast(child, _)
    | Property(child, _) => child_depth = self.depths[child]
    Binary(_, left, right) =>
      child_depth = self.depths[left].max(self.depths[right])
    Call(_, arguments)
    | Predicate(_, arguments)
    | ArrayConstructor(arguments, _) =>
      for child in arguments {
        child_depth = child_depth.max(self.depths[child])
      }
    SearchedCase(branches, otherwise) => {
      child_depth = self.depths[otherwise]
      for (condition, value) in branches {
        child_depth = child_depth
          .max(self.depths[condition])
          .max(self.depths[value])
      }
    }
    _ => ()
  }
  if child_depth >= self.limits.max_depth {
    raise ExpressionAbort("Expression depth limit", start)
  }
  let index = self.nodes.length()
  self.nodes.push({ kind, start, end, })
  self.depths.push(child_depth + 1)
  index
}

///|
fn infix(token : Token) -> (String, Int)? {
  match token.value {
    Word(name) =>
      match upper_ascii(name) {
        "OR" => Some(("OR", 1))
        "AND" => Some(("AND", 2))
        "LIKE" => Some(("LIKE", 4))
        _ => None
      }
    Operator("=" | "!=" | "<>" | "<" | "<=" | ">" | ">=" as op) => Some((op, 4))
    Symbol(61) => Some(("=", 4))
    Operator("||") => Some(("||", 7))
    Symbol(43) => Some(("+", 6))
    Symbol(45) => Some(("-", 6))
    Symbol(42) => Some(("*", 7))
    Symbol(47) => Some(("/", 7))
    Symbol(37) => Some(("%", 7))
    _ => None
  }
}

///|
fn keyword(token : Token, expected : String) -> Bool {
  token.value is Word(name) && upper_ascii(name) == expected
}

///|
fn ExpressionParser::require_keyword(
  self : ExpressionParser,
  expected : String,
) -> Unit raise ExpressionAbort {
  let token = self.advance()
  if !keyword(token, expected) {
    raise ExpressionAbort("Expected " + expected, token.start)
  }
}

///|
fn comparison(kind : ExpressionKind) -> Bool {
  match kind {
    Binary(op, _, _) =>
      ["=", "!=", "<>", "<", "<=", ">", ">=", "LIKE", "NOT LIKE"].contains(op)
    Predicate(_, _) => true
    _ => false
  }
}

///|
fn ExpressionParser::small_integer(
  self : ExpressionParser,
) -> Int raise ExpressionAbort {
  let token = self.advance()
  match token.value {
    Numeric(text) => {
      for _ in 0..<text.length() {
        self.spend()
      }
      guard exact_integer_literal(text) is Some(value) && value <= 38L else {
        raise ExpressionAbort(
          "Expected bounded integer type argument",
          token.start,
        )
      }
      value.to_int()
    }
    _ => raise ExpressionAbort("Expected integer type argument", token.start)
  }
}

///|
fn ExpressionParser::path(
  self : ExpressionParser,
  first : Token,
) -> Array[NamePart] raise ExpressionAbort {
  let names : Array[NamePart] = []
  let mut part = first
  while true {
    self.spend()
    match part.value {
      Word(value) => names.push({ value, quoted: false, })
      QuotedName(value) =>
        names.push({ value: self.source.identifier(value), quoted: true, })
      _ => raise ExpressionAbort("Expected identifier", part.start)
    }
    if self.peek().value != Symbol(46) ||
      (
        self.stop_before_star &&
        self.source.tokens[self.offset + 1].value == Symbol(42)
      ) {
      break
    }
    ignore(self.advance())
    part = self.advance()
  }
  names
}

///|
// A typed literal shares ordinary decoded String chunks. JSON parsing happens
// after lexical decoding; it does not reinterpret the source's escape syntax.
fn ExpressionParser::string_chunks(
  self : ExpressionParser,
  first : Token,
) -> (String, Int) raise ExpressionAbort {
  guard first.value is Text(value) else {
    raise ExpressionAbort("Expected String literal", first.start)
  }
  let chunks = StringBuilder()
  chunks.write_string(value)
  let mut end = first.end
  while self.peek().value is Text(next) {
    let token = self.peek()
    if token.start == end {
      raise ExpressionAbort("Literal chunks require separation", token.start)
    }
    self.spend()
    ignore(self.advance())
    chunks.write_string(next)
    end = token.end
  }
  (chunks.to_string(), end)
}

///|
// Explicit Pratt continuations bound heap work without recursive native calls.
fn ExpressionParser::expression(
  self : ExpressionParser,
) -> Int raise ExpressionAbort {
  let frames : Array[ExpressionFrame] = [Enter(1, 1)]
  let mut result = -1
  while frames.pop() is Some(frame) {
    self.spend()
    match frame {
      Enter(minimum, depth) => {
        if depth > self.limits.max_depth {
          raise ExpressionAbort("Expression depth limit", self.peek().start)
        }
        // Clause-owned calls retain token spans and use the same admitted
        // token stream. Ordinary scalar expression parsing has no resolver.
        if self.primary is Some(primary) {
          let remaining = {
            ..self.limits,
            max_nodes: self.limits.max_nodes -
            self.nodes.length() -
            self.embedded_nodes -
            1,
            max_depth: self.limits.max_depth - depth,
            max_work: self.limits.max_work - self.work,
          }
          match primary(self.offset, remaining) {
            Err(error) => raise ExpressionDiagnostic(error)
            Ok(Some((name, next, work, nodes))) => {
              self.work += work
              self.embedded_nodes += nodes
              let start = self.peek().start
              self.offset = next
              result = self.add(
                Reference([name]),
                start,
                self.source.tokens[next - 1].end,
              )
              frames.push(Tail(-1, minimum, depth))
              continue
            }
            Ok(None) => ()
          }
        }
        let t = self.advance()
        frames.push(Tail(-1, minimum, depth))
        match t.value {
          Text(_) => {
            let (value, end) = self.string_chunks(t)
            result = self.add(StringLiteral(value), t.start, end)
          }
          Word(name) if upper_ascii(name) == "JSON" &&
            self.peek().value is Text(_) => {
            let (value, end) = self.string_chunks(self.advance())
            result = self.add(JsonLiteral(value), t.start, end)
          }
          value if value == Symbol(91) || keyword(t, "ARRAY") => {
            let mut target : ArrayElementType? = None
            if t.value != Symbol(91) {
              if self.peek().value == Operator("<") {
                ignore(self.advance())
                let name = self.advance()
                target = Some(
                  match name.value {
                    Word(word) =>
                      match upper_ascii(word) {
                        "BOOL" | "BOOLEAN" => ArrayElementType::Boolean
                        "STRING" => ArrayElementType::String
                        "FLOAT64" | "DOUBLE" => ArrayElementType::Number
                        "TIMESTAMP" => ArrayElementType::Timestamp
                        "JSON" => ArrayElementType::Json
                        _ =>
                          raise ExpressionAbort(
                            "Unsupported ARRAY element type",
                            name.start,
                          )
                      }
                    _ =>
                      raise ExpressionAbort(
                        "Expected ARRAY element type",
                        name.start,
                      )
                  },
                )
                let close = self.advance()
                if close.value != Operator(">") {
                  raise ExpressionAbort(
                    "Expected ARRAY type closing angle bracket",
                    close.start,
                  )
                }
              }
              let open = self.advance()
              if open.value != Symbol(91) {
                raise ExpressionAbort(
                  "Expected ARRAY opening bracket",
                  open.start,
                )
              }
            }
            if self.peek().value == Symbol(93) {
              let close = self.advance()
              result = self.add(
                ArrayConstructor([], target),
                t.start,
                close.end,
              )
            } else {
              frames.push(ArrayItem([], target, t.start, depth))
              frames.push(Enter(1, depth + 1))
            }
          }
          Numeric(value) => result = self.add(Number(value), t.start, t.end)
          Parameter(name) =>
            result = self.add(
              ParameterReference(self.source.identifier(name)),
              t.start,
              t.end,
            )
          Word(name) if upper_ascii(name) == "NULL" =>
            result = self.add(Null, t.start, t.end)
          Word(name) if upper_ascii(name) == "TRUE" ||
            upper_ascii(name) == "FALSE" =>
            result = self.add(
              Boolean(upper_ascii(name) == "TRUE"),
              t.start,
              t.end,
            )
          Word(name) if upper_ascii(name) == "CAST" => {
            let open = self.advance()
            if open.value != Symbol(40) {
              raise ExpressionAbort(
                "Expected CAST opening parenthesis",
                open.start,
              )
            }
            frames.push(CastTarget(t.start))
            frames.push(Enter(1, depth + 1))
          }
          Word(name) if upper_ascii(name) == "CASE" => {
            self.require_keyword("WHEN")
            frames.push(CaseCondition([], t.start, depth))
            frames.push(Enter(1, depth + 1))
          }
          Word(name) if upper_ascii(name) == "NOT" => {
            frames.push(Prefix("NOT", t.start))
            frames.push(Enter(3, depth + 1))
          }
          Symbol(43 | 45 as sign) => {
            frames.push(Prefix(if sign == 43 { "+" } else { "-" }, t.start))
            frames.push(Enter(8, depth + 1))
          }
          Symbol(40) => {
            frames.push(CloseGroup(t.start))
            frames.push(Enter(1, depth + 1))
          }
          Word(_) | QuotedName(_) => {
            if t.value is Word(name) &&
              [
                "SELECT", "FROM", "WHERE", "GROUP", "BY", "HAVING", "ORDER", "LIMIT",
                "AS", "WITH", "RECURSIVE", "DISTINCT", "ALL", "UNION", "INTERSECT",
                "EXCEPT", "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "CROSS", "ON",
                "USING", "OVER", "PARTITION", "ROWS", "RANGE", "WINDOW", "WHEN",
                "THEN", "ELSE", "END", "AND", "OR", "IS", "IN", "BETWEEN", "LIKE",
              ].contains(upper_ascii(name)) &&
              !(["LEFT", "RIGHT"].contains(upper_ascii(name)) &&
              self.peek().value == Symbol(40)) {
              raise ExpressionAbort(
                "Reserved query identifier requires quoting",
                t.start,
              )
            }
            let path = self.path(t)
            if self.peek().value == Symbol(40) {
              ignore(self.advance())
              if self.peek().value == Symbol(41) {
                let close = self.advance()
                result = self.add(Call(path, []), t.start, close.end)
              } else {
                frames.push(Argument(path, [], t.start, depth))
                frames.push(Enter(1, depth + 1))
              }
            } else {
              result = self.add(
                Reference(path),
                t.start,
                self.source.tokens[self.offset - 1].end,
              )
            }
          }
          _ => raise ExpressionAbort("Expected expression", t.start)
        }
      }
      Tail(left, minimum, depth) => {
        let left = if left < 0 { result } else { left }
        let token = self.peek()
        if token.value == Symbol(46) {
          if self.stop_before_star &&
            self.source.tokens[self.offset + 1].value == Symbol(42) {
            result = left
            continue
          }
          ignore(self.advance())
          let property_token = self.advance()
          let name = match property_token.value {
            Word(value) => { value, quoted: false, }
            QuotedName(value) =>
              { value: self.source.identifier(value), quoted: true, }
            _ =>
              raise ExpressionAbort(
                "Expected property name",
                property_token.start,
              )
          }
          result = self.add(
            Property(left, name),
            self.nodes[left].start,
            property_token.end,
          )
          frames.push(Tail(result, minimum, depth))
          continue
        }
        let mut negated = false
        if minimum <= 4 && keyword(token, "NOT") {
          ignore(self.advance())
          negated = true
        }
        let op = self.peek()
        if minimum <= 4 &&
          (
            keyword(op, "IS") ||
            keyword(op, "BETWEEN") ||
            keyword(op, "IN") ||
            negated
          ) {
          if comparison(self.nodes[left].kind) {
            raise ExpressionAbort(
              "Comparison requires parentheses",
              token.start,
            )
          }
          ignore(self.advance())
          if keyword(op, "BETWEEN") {
            frames.push(BetweenLower(left, negated, minimum, depth))
            frames.push(Enter(5, depth + 1))
          } else if keyword(op, "IN") {
            let array = keyword(self.peek(), "UNNEST")
            if array {
              ignore(self.advance())
            }
            let open = self.advance()
            if open.value != Symbol(40) {
              raise ExpressionAbort(
                if array {
                  "Expected UNNEST argument"
                } else {
                  "Expected IN list"
                },
                open.start,
              )
            }
            if array {
              frames.push(InUnnest(left, negated, minimum, depth))
            } else {
              frames.push(InItem(left, negated, [], minimum, depth))
            }
            frames.push(Enter(1, depth + 1))
          } else if keyword(op, "LIKE") && negated {
            frames.push(BinaryRight("NOT LIKE", left, minimum, depth))
            frames.push(Enter(5, depth + 1))
          } else if keyword(op, "IS") && !negated {
            let invert = keyword(self.peek(), "NOT")
            if invert {
              ignore(self.advance())
            }
            let predicate_token = self.advance()
            if keyword(predicate_token, "DISTINCT") {
              self.require_keyword("FROM")
              frames.push(IsDistinct(left, invert, minimum, depth))
              frames.push(Enter(5, depth + 1))
            } else {
              let predicate = match predicate_token.value {
                Word(name) if ["NULL", "TRUE", "FALSE", "UNKNOWN"].contains(
                    upper_ascii(name),
                  ) => upper_ascii(name)
                _ =>
                  raise ExpressionAbort(
                    "Expected IS predicate",
                    predicate_token.start,
                  )
              }
              result = self.add(
                Predicate(
                  "IS " + (if invert { "NOT " } else { "" }) + predicate,
                  [left],
                ),
                self.nodes[left].start,
                predicate_token.end,
              )
              frames.push(Tail(result, minimum, depth))
            }
          } else {
            raise ExpressionAbort(
              "Expected IN, LIKE or BETWEEN after NOT",
              op.start,
            )
          }
        } else {
          match infix(token) {
            Some((op, level)) if level >= minimum => {
              if level == 4 && comparison(self.nodes[left].kind) {
                raise ExpressionAbort(
                  "Comparison requires parentheses",
                  token.start,
                )
              }
              ignore(self.advance())
              frames.push(BinaryRight(op, left, minimum, depth))
              frames.push(Enter(level + 1, depth + 1))
            }
            _ => result = left
          }
        }
      }
      Prefix(op, start) =>
        result = self.add(Unary(op, result), start, self.nodes[result].end)
      CloseGroup(start) => {
        let token = self.advance()
        if token.value != Symbol(41) {
          raise ExpressionAbort("Expected closing parenthesis", token.start)
        }
        result = self.add(Parenthesized(result), start, token.end)
      }
      BinaryRight(op, left, minimum, depth) => {
        result = self.add(
          Binary(op, left, result),
          self.nodes[left].start,
          self.nodes[result].end,
        )
        frames.push(Tail(result, minimum, depth))
      }
      BetweenLower(left, negated, minimum, depth) => {
        self.require_keyword("AND")
        frames.push(BetweenUpper(left, result, negated, minimum, depth))
        frames.push(Enter(5, depth + 1))
      }
      BetweenUpper(left, low, negated, minimum, depth) => {
        result = self.add(
          Predicate(if negated { "NOT BETWEEN" } else { "BETWEEN" }, [
            left, low, result,
          ]),
          self.nodes[left].start,
          self.nodes[result].end,
        )
        frames.push(Tail(result, minimum, depth))
      }
      InItem(left, negated, items, minimum, depth) => {
        items.push(result)
        let token = self.advance()
        if token.value == Symbol(44) {
          frames.push(InItem(left, negated, items, minimum, depth))
          frames.push(Enter(1, depth + 1))
        } else if token.value == Symbol(41) {
          result = self.add(
            Predicate(if negated { "NOT IN" } else { "IN" }, [left] + items),
            self.nodes[left].start,
            token.end,
          )
          frames.push(Tail(result, minimum, depth))
        } else {
          raise ExpressionAbort(
            "Expected comma or closing IN list",
            token.start,
          )
        }
      }
      InUnnest(left, negated, minimum, depth) => {
        let token = self.advance()
        if token.value != Symbol(41) {
          raise ExpressionAbort("Expected closing UNNEST argument", token.start)
        }
        result = self.add(
          Predicate(if negated { "NOT IN UNNEST" } else { "IN UNNEST" }, [
            left, result,
          ]),
          self.nodes[left].start,
          token.end,
        )
        frames.push(Tail(result, minimum, depth))
      }
      IsDistinct(left, negated, minimum, depth) => {
        result = self.add(
          Predicate(
            if negated {
              "IS NOT DISTINCT FROM"
            } else {
              "IS DISTINCT FROM"
            },
            [left, result],
          ),
          self.nodes[left].start,
          self.nodes[result].end,
        )
        frames.push(Tail(result, minimum, depth))
      }
      CaseCondition(branches, start, depth) => {
        self.require_keyword("THEN")
        frames.push(CaseValue(branches, result, start, depth))
        frames.push(Enter(1, depth + 1))
      }
      CaseValue(branches, condition, start, depth) => {
        branches.push((condition, result))
        let next = self.advance()
        if keyword(next, "WHEN") {
          frames.push(CaseCondition(branches, start, depth))
          frames.push(Enter(1, depth + 1))
        } else if keyword(next, "ELSE") {
          frames.push(CaseElse(branches, start))
          frames.push(Enter(1, depth + 1))
        } else if keyword(next, "END") {
          let otherwise = self.add(Null, next.start, next.end)
          result = self.add(SearchedCase(branches, otherwise), start, next.end)
        } else {
          raise ExpressionAbort("Expected WHEN, ELSE or END", next.start)
        }
      }
      CastTarget(start) => {
        self.require_keyword("AS")
        let name = self.advance()
        let target = match name.value {
          Word(word) =>
            match upper_ascii(word) {
              "BOOL" | "BOOLEAN" => CastType::Boolean
              "STRING" => CastType::String
              "NUMBER" | "FLOAT64" | "DOUBLE" => CastType::Number
              "TIMESTAMP" => CastType::Timestamp
              "DECIMAL" => {
                let open = self.advance()
                if open.value != Symbol(40) {
                  raise ExpressionAbort(
                    "Expected DECIMAL precision and scale",
                    open.start,
                  )
                }
                let precision = self.small_integer()
                let comma = self.advance()
                if comma.value != Symbol(44) {
                  raise ExpressionAbort("Expected DECIMAL scale", comma.start)
                }
                let scale = self.small_integer()
                let close = self.advance()
                if close.value != Symbol(41) ||
                  precision < 1 ||
                  precision > 38 ||
                  scale > precision {
                  raise ExpressionAbort(
                    "Invalid DECIMAL precision or scale",
                    name.start,
                  )
                }
                CastType::Decimal(precision, scale)
              }
              _ =>
                raise ExpressionAbort("Unsupported query cast type", name.start)
            }
          _ => raise ExpressionAbort("Expected query cast type", name.start)
        }
        let close = self.advance()
        if close.value != Symbol(41) {
          raise ExpressionAbort(
            "Expected CAST closing parenthesis",
            close.start,
          )
        }
        result = self.add(Cast(result, target), start, close.end)
      }
      CaseElse(branches, start) => {
        let next = self.peek()
        self.require_keyword("END")
        result = self.add(SearchedCase(branches, result), start, next.end)
      }
      Argument(path, args, start, depth) => {
        args.push(result)
        let token = self.advance()
        if token.value == Symbol(44) {
          frames.push(Argument(path, args, start, depth))
          frames.push(Enter(1, depth + 1))
        } else if token.value == Symbol(41) {
          result = self.add(Call(path, args), start, token.end)
        } else {
          raise ExpressionAbort(
            "Expected comma or closing parenthesis",
            token.start,
          )
        }
      }
      ArrayItem(items, target, start, depth) => {
        items.push(result)
        let token = self.advance()
        if token.value == Symbol(44) {
          frames.push(ArrayItem(items, target, start, depth))
          frames.push(Enter(1, depth + 1))
        } else if token.value == Symbol(93) {
          result = self.add(ArrayConstructor(items, target), start, token.end)
        } else {
          raise ExpressionAbort(
            "Expected comma or closing bracket",
            token.start,
          )
        }
      }
    }
  }
  result
}

///|
pub fn parse_expression(
  text : String,
  limits : ExpressionLimits,
  source_path? : String = "<query>",
) -> Result[Expression, Diagnostic] {
  if [limits.max_nodes, limits.max_depth, limits.max_work].any(n => {
      n < 0 || n == 2147483647
    }) {
    return Err({ issue: InvalidLimits, span: None, })
  }
  let source = match tokenize(text, limits.lexical, source_path~) {
    Ok(source) => source
    Err(error) => return Err(error)
  }
  match parse_fragment(source, 0, limits) {
    Ok((expression, offset)) =>
      if source.tokens[offset].value == End {
        Ok(expression)
      } else {
        Err({
          issue: Syntax("Unexpected trailing expression token"),
          span: Some(
            @origin.span(
              @origin.range(
                source.document,
                source.tokens[offset].start,
                source.tokens[offset].start,
              ).unwrap(),
            ),
          ),
        })
      }
    Err(error) => Err(error)
  }
}

///|
// Query clauses consume this owner directly from the already admitted token
// stream. No expression is serialized back to text for another parse pass.
fn parse_fragment(
  source : Tokens,
  offset : Int,
  limits : ExpressionLimits,
  stop_before_star? : Bool = false,
) -> Result[(Expression, Int), Diagnostic] {
  match
    parse_fragment_resolved(source, offset, limits, None, stop_before_star~) {
    Ok((expression, next, _)) => Ok((expression, next))
    Err(error) => Err(error)
  }
}

///|
fn parse_fragment_resolved(
  source : Tokens,
  offset : Int,
  limits : ExpressionLimits,
  primary : ((Int, ExpressionLimits) -> Result[
    (NamePart, Int, Int, Int)?,
    Diagnostic,
  ])?,
  stop_before_star? : Bool = false,
) -> Result[(Expression, Int, Int), Diagnostic] {
  let parser : ExpressionParser = {
    source,
    limits,
    nodes: [],
    depths: [],
    offset,
    work: 0,
    embedded_nodes: 0,
    stop_before_star,
    primary,
  }
  try {
    let root = parser.expression()
    Ok(
      (
        { source, nodes: parser.nodes, root, work: parser.work, },
        parser.offset,
        parser.embedded_nodes,
      ),
    )
  } catch {
    ExpressionDiagnostic(error) => Err(error)
    ExpressionAbort(message, at) =>
      Err({
        issue: Syntax(message),
        span: Some(
          @origin.span(@origin.range(source.document, at, at).unwrap()),
        ),
      })
  }
}

///|
pub fn expression_document(expression : Expression) -> @origin.Document {
  expression.source.document
}
