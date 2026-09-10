///|
fn Parser::cast_target(
  self : Parser,
  token : Token,
  value : @value.Node,
) -> @value.Node raise ExpressionError {
  self.take(Reserved(As))
  let type_token = self.advance()
  let name = match type_token.kind {
    Word(name) => name.to_lower()
    _ => raise SyntaxFailure(type_token.start, type_token.end)
  }
  if !["number", "string", "boolean", "timestamp", "decimal"].contains(name) {
    raise SyntaxFailure(type_token.start, type_token.end)
  }
  let fields = [("type", self.node(@value.String(name)))]
  if name == "decimal" {
    self.take(Punctuation(OpenParen))
    let numbers = []
    for field in ["precision", "scale"] {
      let next = self.advance()
      let number = match next.kind {
        NumberLiteral(spelling~, value~) if spelling.iter().all(digit) => value
        _ => raise InvalidArguments(next.start, next.end)
      }
      numbers.push(number)
      fields.push((field, self.node(@value.Number(number))))
      if field == "precision" {
        self.take(Punctuation(Comma))
      }
    }
    self.take(Punctuation(CloseParen))
    if numbers[0] < 1.0 ||
      numbers[0] > 38.0 ||
      numbers[1] < 0.0 ||
      numbers[1] > numbers[0] {
      raise InvalidArguments(token.start, token.end)
    }
  }
  self.take(Punctuation(CloseParen))
  self.form(
    "cast",
    self.object([("value", value), ("target", self.object(fields))]),
  )
}

///|
fn Parser::call(
  self : Parser,
  name : String,
  args : Array[@value.Node],
  token : Token,
) -> @value.Node raise ExpressionError {
  let (minimum, maximum) = match name {
    "len"
    | "sqrt"
    | "floor"
    | "lower"
    | "upper"
    | "trim"
    | "to_number"
    | "to_string"
    | "to_boolean"
    | "to_timestamp"
    | "negate"
    | "try_number"
    | "nfkc"
    | "case_fold" => (1, 1)
    "contains"
    | "safe_div"
    | "nullif"
    | "utf8_truncate"
    | "parse_timestamp"
    | "try_timestamp"
    | "format_timestamp" => (2, 2)
    "replace"
    | "if"
    | "date_trunc"
    | "date_add"
    | "date_diff"
    | "to_decimal"
    | "try_decimal"
    | "split_part"
    | "substring"
    | "vector_score" => if name == "date_trunc" { (2, 2) } else { (3, 3) }
    "quantize" => (4, 4)
    "decimal_divide" => (5, 5)
    "regex_match" => (2, 3)
    "regex_extract" | "regex_replace" => (3, 4)
    "concat" | "concat_strict" | "coalesce" => (1, self.tokens.length())
    "vector_concat" => (2, self.tokens.length())
    _ => raise UnknownFunction(token.start, token.end)
  }
  if args.length() < minimum || args.length() > maximum {
    raise InvalidArguments(token.start, token.end)
  }
  if ["to_number", "to_string", "to_boolean", "to_timestamp"].contains(name) {
    return self.form(
      "cast",
      self.object([
        ("value", args[0]),
        (
          "target",
          self.object([("type", self.node(@value.String(name[3:].to_owned())))]),
        ),
      ]),
    )
  }
  if name == "vector_score" {
    let metric = literal_value(args[2])
    if !(metric is Some({ value: @value.String("cosine" | "dot" | "l2"), .. })) {
      raise InvalidArguments(token.start, token.end)
    }
    return self.form(
      name,
      self.object([
        ("left", args[0]),
        ("right", args[1]),
        ("metric", metric.unwrap()),
      ]),
    )
  }
  if ["date_trunc", "date_add", "date_diff"].contains(name) {
    let index = if name == "date_trunc" { 0 } else { 2 }
    if !(literal_value(args[index])
      is Some({ value: @value.String("ms" | "s" | "m" | "h" | "d"), .. })) {
      raise InvalidArguments(token.start, token.end)
    }
  }
  let fields : Array[String] = match name {
    "to_decimal" | "try_decimal" => ["value", "precision", "scale"]
    "quantize" => ["value", "precision", "scale", "rounding"]
    "decimal_divide" => ["left", "right", "precision", "scale", "rounding"]
    "split_part" => ["value", "delimiter", "index"]
    "substring" => ["value", "start", "length"]
    "utf8_truncate" => ["value", "max_bytes"]
    "try_number" => ["value"]
    "parse_timestamp" | "try_timestamp" | "format_timestamp" =>
      ["value", "pattern"]
    "regex_match" => ["value", "pattern", "flags"]
    "regex_extract" => ["value", "pattern", "capture", "flags"]
    "regex_replace" => ["value", "pattern", "replacement", "flags"]
    _ => []
  }
  if !fields.is_empty() {
    let body = []
    for i, arg in args {
      let key = fields[i]
      if key == "pattern" || key == "delimiter" {
        if !(literal_value(arg) is Some({ value: @value.String(_), .. })) &&
          object_get(arg, "$param") is None {
          raise InvalidArguments(token.start, token.end)
        }
      }
      let value = if ["precision", "scale", "rounding", "flags"].contains(key) {
        let raw = match literal_value(arg) {
          Some(value) => value
          None => raise InvalidArguments(token.start, token.end)
        }
        if key == "precision" || key == "scale" {
          match raw.value {
            @value.Number(value) if value >= -9007199254740991.0 &&
              value <= 9007199254740991.0 &&
              value.trunc() == value => ()
            _ => raise InvalidArguments(token.start, token.end)
          }
        } else if !(raw.value is @value.String(_)) {
          raise InvalidArguments(token.start, token.end)
        }
        raw
      } else {
        arg
      }
      body.push((key, value))
    }
    if ["to_decimal", "try_decimal", "quantize", "decimal_divide"].contains(
        name,
      ) {
      let offset = if name == "decimal_divide" { 2 } else { 1 }
      match (body[offset].1.value, body[offset + 1].1.value) {
        (@value.Number(precision), @value.Number(scale)) if precision >= 1.0 &&
          precision <= 38.0 &&
          scale >= 0.0 &&
          scale <= precision => ()
        _ => raise InvalidArguments(token.start, token.end)
      }
    }
    if name == "quantize" || name == "decimal_divide" {
      match body[body.length() - 1].1.value {
        @value.String(
          "half_even"
          | "half_up"
          | "toward_zero"
          | "floor"
          | "ceiling"
        ) => ()
        _ => raise InvalidArguments(token.start, token.end)
      }
    }
    if name == "to_decimal" {
      return self.form(
        "cast",
        self.object([
          ("value", args[0]),
          (
            "target",
            self.object([
              ("type", self.node(@value.String("decimal"))),
              ("precision", body[1].1),
              ("scale", body[2].1),
            ]),
          ),
        ]),
      )
    }
    return self.form(name, self.object(body))
  }
  if minimum == 1 && maximum == 1 {
    self.form(name, args[0])
  } else {
    self.arguments(name, args)
  }
}
