///|
priv enum Frame {
  Enter(Int, Int)
  Tail(Int, Int, Int)
  Group
  Prefix(Token)
  List(String?, Token, Array[@value.Node], Int)
  CastFinish(Token)
  CaseCondition(Array[@value.Node], Int)
  CaseValue(Array[@value.Node], @value.Node, Int)
  CaseElse(Array[(String, @value.Node)])
  Subscript(@value.Node)
  Binary(Parsed, TokenKind, Int, Token)
  Distinct(@value.Node, Bool)
  BetweenLow(@value.Node, Bool, Int)
  BetweenHigh(@value.Node, @value.Node, Bool)
  LikeFinish(@value.Node, Bool, Token)
  InParameter(@value.Node, Bool, Token)
  InItem(@value.Node, Bool, Array[@value.Node], Token, Int)
}

///|
fn object_get(node : @value.Node, key : String) -> @value.Node? {
  match node.value {
    @value.Object(fields) => {
      for field in fields {
        if field.key == key {
          return Some(field.value)
        }
      }
      None
    }
    _ => None
  }
}

///|
fn Parser::field_name(self : Parser) -> String raise ExpressionError {
  let token = self.advance()
  match token.kind {
    Word(name) | QuotedName(name) => name
    _ => raise SyntaxFailure(token.start, token.end)
  }
}

///|
fn Parser::binary(
  self : Parser,
  left : Parsed,
  right : @value.Node,
  op : TokenKind,
  level : Int,
  token : Token,
) -> Parsed raise ExpressionError {
  if level == 5 &&
    (
      literal_value(left.node) is Some({ value: @value.Null, .. }) ||
      literal_value(right) is Some({ value: @value.Null, .. })
    ) {
    raise InvalidArguments(token.start, token.end)
  }
  let name = match op {
    Reserved(And) => "and"
    Reserved(Or) => "or"
    Punctuation(Plus) => "add"
    Punctuation(Minus) => "subtract"
    Punctuation(Multiply) => "multiply"
    Punctuation(Divide) => "divide"
    Punctuation(Modulo) => "modulo"
    Punctuation(Equal) => "eq"
    Punctuation(NotEqual) => "neq"
    Punctuation(Less) => "lt"
    Punctuation(LessEqual) => "lte"
    Punctuation(Greater) => "gt"
    Punctuation(GreaterEqual) => "gte"
    Punctuation(Concat) => "concat_strict"
    _ => raise SyntaxFailure(token.start, token.end)
  }
  let chain = if level == 1 || level == 2 || level == 7 {
    Some(name)
  } else {
    None
  }
  if chain is Some(_) && left.chain == chain {
    // Only private, unparenthesized chains share this mutable builder.
    match object_get(left.node, name) {
      Some({ value: @value.Array(args), .. }) => args.push(right)
      _ => raise SyntaxFailure(token.start, token.end)
    }
    { ..left, numeric_token: false, }
  } else {
    {
      node: self.arguments(name, [left.node, right]),
      numeric_token: false,
      chain,
    }
  }
}

///|
/// Pratt continuations live on the heap. Sibling operands resume at the same
/// nesting budget; neither long left-associative chains nor nested calls use
/// the native call stack.
fn Parser::expression(self : Parser) -> @value.Node raise ExpressionError {
  let stack : Array[Frame] = [Enter(1, 1)]
  let mut result = parsed({ value: @value.Null, span: self.span, })
  while stack.pop() is Some(frame) {
    match frame {
      Enter(minimum, depth) => {
        let token = self.peek()
        if depth > self.max_depth {
          raise CapacityExceeded(token.start, token.end)
        }
        ignore(self.advance())
        stack.push(Tail(minimum, 10, depth))
        match token.kind {
          NumberLiteral(value~, ..) =>
            result = {
              node: self.form("literal", self.node(@value.Number(value))),
              numeric_token: true,
              chain: None,
            }
          StringLiteral(text) =>
            result = parsed(
              self.form("literal", self.node(@value.String(text))),
            )
          Parameter(name) =>
            result = parsed(self.form("$param", self.node(@value.String(name))))
          Reserved(Null) =>
            result = parsed(self.form("literal", self.node(@value.Null)))
          Reserved(True) =>
            result = parsed(self.form("literal", self.node(@value.Bool(true))))
          Reserved(False) =>
            result = parsed(self.form("literal", self.node(@value.Bool(false))))
          Punctuation(OpenParen) => {
            stack.push(Group)
            stack.push(Enter(1, depth + 1))
          }
          Punctuation(Minus) | Reserved(Not) => {
            if token.kind == Reserved(Not) && minimum > 3 {
              raise SyntaxFailure(token.start, token.end)
            }
            stack.push(Prefix(token))
            stack.push(
              Enter(if token.kind == Reserved(Not) { 3 } else { 10 }, depth + 1),
            )
          }
          Punctuation(OpenBracket) =>
            if self.has(Punctuation(CloseBracket)) {
              ignore(self.advance())
              result = parsed(self.arguments("array", []))
            } else {
              stack.push(List(None, token, [], depth))
              stack.push(Enter(1, depth + 1))
            }
          Reserved(Cast) => {
            self.take(Punctuation(OpenParen))
            stack.push(CastFinish(token))
            stack.push(Enter(1, depth + 1))
          }
          Reserved(Case) => {
            self.take(Reserved(When))
            stack.push(CaseCondition([], depth))
            stack.push(Enter(1, depth + 1))
          }
          Word(name) =>
            if self.has(Punctuation(OpenParen)) {
              ignore(self.advance())
              if self.has(Punctuation(CloseParen)) {
                ignore(self.advance())
                result = parsed(self.call(name, [], token))
              } else {
                stack.push(List(Some(name), token, [], depth))
                stack.push(Enter(1, depth + 1))
              }
            } else if (name == "left" || name == "right") &&
              self.has(Punctuation(Dot)) {
              ignore(self.advance())
              let field = self.field_name()
              self.relation_references.push({
                name: name + "." + field,
                range: {
                  start: token.start,
                  end: self.tokens[self.pos - 1].end,
                },
              })
              result = parsed(
                self.form(
                  "join_field",
                  self.object([
                    ("side", self.node(@value.String(name))),
                    ("name", self.node(@value.String(field))),
                  ]),
                ),
              )
            } else {
              self.field_references.push({
                name,
                range: { start: token.start, end: token.end, },
              })
              self.relation_references.push({
                name,
                range: { start: token.start, end: token.end, },
              })
              result = parsed(
                self.form("field", self.node(@value.String(name))),
              )
            }
          QuotedName(name) => {
            self.field_references.push({
              name,
              range: { start: token.start, end: token.end, },
            })
            self.relation_references.push({
              name,
              range: { start: token.start, end: token.end, },
            })
            result = parsed(self.form("field", self.node(@value.String(name))))
          }
          _ => raise SyntaxFailure(token.start, token.end)
        }
      }
      Group => {
        self.take(Punctuation(CloseParen))
        result = { ..result, chain: None, }
      }
      Prefix(token) =>
        if token.kind == Reserved(Not) {
          result = parsed(self.form("not", result.node))
        } else if result.numeric_token {
          match literal_value(result.node) {
            Some({ value: @value.Number(number), .. }) if number != 0.0 =>
              result = parsed(
                self.form("literal", self.node(@value.Number(-number))),
              )
            _ => raise InvalidArguments(token.start, token.end)
          }
        } else {
          result = parsed(self.form("negate", result.node))
        }
      List(name, token, args, depth) => {
        args.push(result.node)
        if self.has(Punctuation(Comma)) {
          ignore(self.advance())
          stack.push(List(name, token, args, depth))
          stack.push(Enter(1, depth + 1))
        } else {
          self.take(
            Punctuation(if name is None { CloseBracket } else { CloseParen }),
          )
          result = parsed(
            match name {
              None => self.arguments("array", args)
              Some(name) => self.call(name, args, token)
            },
          )
        }
      }
      CastFinish(token) => result = parsed(self.cast_target(token, result.node))
      CaseCondition(branches, depth) => {
        self.take(Reserved(Then))
        stack.push(CaseValue(branches, result.node, depth))
        stack.push(Enter(1, depth + 1))
      }
      CaseValue(branches, condition, depth) => {
        branches.push(self.object([("when", condition), ("then", result.node)]))
        if self.has(Reserved(When)) {
          ignore(self.advance())
          stack.push(CaseCondition(branches, depth))
          stack.push(Enter(1, depth + 1))
        } else {
          let fields = [("when", self.node(@value.Array(branches)))]
          if self.has(Reserved(Else)) {
            ignore(self.advance())
            stack.push(CaseElse(fields))
            stack.push(Enter(1, depth + 1))
          } else {
            self.take(Reserved(End))
            result = parsed(self.form("case", self.object(fields)))
          }
        }
      }
      CaseElse(fields) => {
        fields.push(("else", result.node))
        self.take(Reserved(End))
        result = parsed(self.form("case", self.object(fields)))
      }
      Subscript(left) => {
        self.take(Punctuation(CloseBracket))
        result = parsed(
          self.form(
            "subscript",
            self.object([("value", left), ("index", result.node)]),
          ),
        )
      }
      Binary(left, op, level, token) =>
        result = self.binary(left, result.node, op, level, token)
      Distinct(left, negated) => {
        let base = self.arguments("is_distinct_from", [left, result.node])
        result = parsed(if negated { self.form("not", base) } else { base })
      }
      BetweenLow(left, negated, depth) => {
        self.take(Reserved(And))
        stack.push(BetweenHigh(left, result.node, negated))
        stack.push(Enter(7, depth + 1))
      }
      BetweenHigh(left, low, negated) => {
        let base = self.arguments("between", [left, low, result.node])
        result = parsed(if negated { self.form("not", base) } else { base })
      }
      LikeFinish(left, negated, token) => {
        if !(literal_value(result.node) is Some({ value: @value.String(_), .. })) &&
          object_get(result.node, "$param") is None {
          raise SyntaxFailure(token.start, token.end)
        }
        let base = self.arguments("like", [left, result.node])
        result = parsed(if negated { self.form("not", base) } else { base })
      }
      InParameter(left, negated, token) => {
        if object_get(result.node, "$param") is None {
          raise SyntaxFailure(token.start, token.end)
        }
        result = parsed(
          self.arguments(if negated { "not_in" } else { "in" }, [
            left,
            result.node,
          ]),
        )
      }
      InItem(left, negated, items, token, depth) => {
        match literal_value(result.node) {
          Some(value) => items.push(value)
          None => {
            if object_get(result.node, "$param") is None {
              raise SyntaxFailure(token.start, token.end)
            }
            items.push(result.node)
          }
        }
        if self.has(Punctuation(Comma)) {
          ignore(self.advance())
          stack.push(InItem(left, negated, items, self.peek(), depth))
          stack.push(Enter(1, depth + 1))
        } else {
          self.take(Punctuation(CloseParen))
          let rhs = self.form("literal", self.node(@value.Array(items)))
          result = parsed(
            self.arguments(if negated { "not_in" } else { "in" }, [left, rhs]),
          )
        }
      }
      Tail(minimum, previous, depth) => {
        let token = self.peek()
        // Postfix belongs to primary, not to a completed comparison-family
        // suffix. Grouping starts a fresh Tail with previous = 10; postfixes
        // on an infix right operand are consumed by that operand's own Tail.
        if previous < 10 &&
          (
            token.kind == Punctuation(Dot) ||
            token.kind == Punctuation(OpenBracket)
          ) {
          raise SyntaxFailure(token.start, token.end)
        }
        if token.kind == Punctuation(Dot) {
          ignore(self.advance())
          let name = self.field_name()
          result = parsed(
            self.form(
              "property",
              self.object([
                ("value", result.node),
                ("name", self.node(@value.String(name))),
              ]),
            ),
          )
          stack.push(Tail(minimum, previous, depth))
          continue
        }
        if token.kind == Punctuation(OpenBracket) {
          ignore(self.advance())
          stack.push(Tail(minimum, previous, depth))
          stack.push(Subscript(result.node))
          stack.push(Enter(1, depth + 1))
          continue
        }
        let negated = token.kind == Reserved(Not) &&
          self.tokens.get(self.pos + 1)
          is Some({ kind: Reserved(In | Between | Like), .. })
        let op = if negated {
          self.tokens[self.pos + 1].kind
        } else {
          token.kind
        }
        let level = precedence(op)
        if level == 0 || level < minimum {
          continue
        }
        if level >= previous {
          raise SyntaxFailure(token.start, token.end)
        }
        let last = if level >= 4 && level <= 6 { level } else { previous }
        ignore(self.advance())
        if negated {
          ignore(self.advance())
        }
        stack.push(Tail(minimum, last, depth))
        match op {
          Reserved(Is) => {
            let not_ = self.has(Reserved(Not))
            if not_ {
              ignore(self.advance())
            }
            let predicate = self.advance()
            match predicate.kind {
              Reserved(Distinct) => {
                self.take(Reserved(From))
                stack.push(Distinct(result.node, not_))
                stack.push(Enter(5, depth + 1))
              }
              Reserved(Null) =>
                result = parsed(
                  self.form(
                    if not_ {
                      "not_null"
                    } else {
                      "is_null"
                    },
                    result.node,
                  ),
                )
              Reserved(True | False | Unknown) => {
                let name = match predicate.kind {
                  Reserved(True) => "is_true"
                  Reserved(False) => "is_false"
                  _ => "is_unknown"
                }
                let base = self.form(name, result.node)
                result = parsed(
                  if not_ {
                    self.form("not", base)
                  } else {
                    base
                  },
                )
              }
              _ => raise SyntaxFailure(predicate.start, predicate.end)
            }
          }
          Reserved(In) =>
            if self.has(Punctuation(OpenParen)) {
              ignore(self.advance())
              stack.push(InItem(result.node, negated, [], self.peek(), depth))
              stack.push(Enter(1, depth + 1))
            } else {
              let start = self.peek()
              if !(start.kind is Parameter(_)) {
                raise SyntaxFailure(start.start, start.end)
              }
              stack.push(InParameter(result.node, negated, start))
              stack.push(Enter(10, depth + 1))
            }
          Reserved(Between) => {
            stack.push(BetweenLow(result.node, negated, depth))
            stack.push(Enter(7, depth + 1))
          }
          Reserved(Like) => {
            stack.push(LikeFinish(result.node, negated, token))
            stack.push(Enter(7, depth + 1))
          }
          _ => {
            stack.push(Binary(result, op, level, token))
            stack.push(Enter(level + 1, depth + 1))
          }
        }
      }
    }
  }
  let token = self.peek()
  if token.kind != Eof {
    raise SyntaxFailure(token.start, token.end)
  }
  result.node
}
