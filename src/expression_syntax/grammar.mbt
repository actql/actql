///|
fn parameter_name(name : String) -> Bool {
  let mut first = true
  for ch in name.iter() {
    let letter = (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      ch == '_'
    if !(letter || (!first && ch >= '0' && ch <= '9')) {
      return false
    }
    first = false
  }
  !first
}

///|
fn field_name(name : String) -> Bool {
  if name == "__cid" || name.has_prefix("__actql_") {
    return false
  }
  let mut nonblank = false
  for ch in name.iter() {
    let cp = ch.to_int()
    if ch == '.' {
      return false
    }
    if !(cp >= 0x2000 && cp <= 0x200a) &&
      ![
        9, 10, 11, 12, 13, 32, 0xa0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000,
        0xfeff,
      ].contains(cp) {
      nonblank = true
    }
  }
  nonblank
}

///|
fn expression_role(
  tag : String,
  cursor : @decode.Cursor,
  origin : Origin,
) -> Role raise Stop {
  match tag {
    "field" | "$param" | "literal" | "template" => Data
    "to_number"
    | "to_string"
    | "to_boolean"
    | "to_timestamp"
    | "negate"
    | "not"
    | "is_null"
    | "not_null"
    | "is_true"
    | "is_false"
    | "is_unknown"
    | "len"
    | "sqrt"
    | "floor"
    | "lower"
    | "upper"
    | "trim"
    | "nfkc"
    | "case_fold" => Expr
    "add"
    | "subtract"
    | "multiply"
    | "divide"
    | "modulo"
    | "eq"
    | "neq"
    | "lt"
    | "lte"
    | "gt"
    | "gte"
    | "in"
    | "not_in"
    | "like"
    | "is_distinct_from"
    | "nullif"
    | "and"
    | "or"
    | "concat_strict"
    | "coalesce"
    | "if"
    | "between"
    | "contains"
    | "safe_div"
    | "replace"
    | "concat"
    | "date_trunc"
    | "date_add"
    | "date_diff"
    | "array"
    | "vector_concat" => Arguments(tag)
    "to_decimal"
    | "join_field"
    | "cast"
    | "property"
    | "subscript"
    | "empty_array"
    | "case"
    | "try_decimal"
    | "quantize"
    | "decimal_divide"
    | "split_part"
    | "substring"
    | "utf8_truncate"
    | "try_number"
    | "parse_timestamp"
    | "try_timestamp"
    | "format_timestamp"
    | "regex_match"
    | "regex_extract"
    | "regex_replace"
    | "vector_score" => Body(tag)
    "object" => ObjectFields
    _ => invalid(cursor, origin, UnknownTag(tag))
  }
}

///|
fn arity(
  tag : String,
  size : Int,
  cursor : @decode.Cursor,
  origin : Origin,
) -> Unit raise Stop {
  let valid = match tag {
    "array" => true
    "and" | "or" | "concat_strict" | "coalesce" | "concat" => size >= 1
    "vector_concat" => size >= 2
    "if" | "between" | "replace" | "date_add" | "date_diff" => size == 3
    _ => size == 2
  }
  if !valid {
    invalid(cursor, origin, InvalidArguments)
  }
}

///|
fn body_fields(tag : String) -> (Array[String], Array[String]) {
  let required = match tag {
    "to_decimal" | "try_decimal" => ["value", "precision", "scale"]
    "quantize" => ["value", "precision", "scale", "rounding"]
    "decimal_divide" => ["left", "right", "precision", "scale", "rounding"]
    "join_field" => ["side", "name"]
    "cast" => ["value", "target"]
    "property" => ["value", "name"]
    "subscript" => ["value", "index"]
    "empty_array" => ["items"]
    "case" => ["when"]
    "split_part" => ["value", "delimiter", "index"]
    "substring" => ["value", "start", "length"]
    "utf8_truncate" => ["value", "max_bytes"]
    "try_number" => ["value"]
    "parse_timestamp" | "try_timestamp" | "format_timestamp" | "regex_match" =>
      ["value", "pattern"]
    "regex_extract" => ["value", "pattern", "capture"]
    "regex_replace" => ["value", "pattern", "replacement"]
    "vector_score" => ["left", "right", "metric"]
    _ => []
  }
  let allowed = required.copy()
  if tag == "case" {
    allowed.push("else")
  }
  if ["regex_match", "regex_extract", "regex_replace"].contains(tag) {
    allowed.push("flags")
  }
  (required, allowed)
}

///|
fn body_role(tag : String, name : String) -> Role {
  match (tag, name) {
    ("cast", "target") => CastTarget
    ("empty_array", "items") => ItemContract
    ("case", "when") => Branches
    ("case", "else") => Expr
    (
      _,
      "precision"
      | "scale"
      | "rounding"
      | "side"
      | "name"
      | "flags"
      | "metric",
    ) => Data
    _ => Expr
  }
}

///|
fn closed(
  cursor : @decode.Cursor,
  origin : Origin,
  required : Array[String],
  allowed : Array[String],
) -> @decode.ObjectView raise Stop {
  let view = decoded(@decode.closed_object(cursor, allowed), origin)
  for name in required {
    ignore(decoded(@decode.required(view, name), origin))
  }
  view
}

///|
fn part(value : @source.Node, name : String) -> @source.Node? {
  if value.value is @source.Object(fields) {
    for f in fields {
      if f.key == name {
        return Some(f.value)
      }
    }
  }
  None
}

///|
fn literal(value : @source.Node) -> @source.Node? {
  if value.value is @source.Object(fields) &&
    fields.length() == 1 &&
    fields[0].key == "literal" {
    Some(fields[0].value)
  } else {
    None
  }
}

///|
fn param(value : @source.Node) -> Bool {
  if value.value is @source.Object(fields) {
    fields.length() == 1 && fields[0].key == "$param"
  } else {
    false
  }
}

///|
fn literal_or_param(value : @source.Node) -> Bool {
  param(value) || literal(value) is Some({ value: @source.String(_), .. })
}

///|
fn decimal_fields(
  value : @source.Node,
  cursor : @decode.Cursor,
  origin : Origin,
) -> Unit raise Stop {
  match (part(value, "precision"), part(value, "scale")) {
    (
      Some({ value: @source.Number(p), .. }),
      Some({ value: @source.Number(s), .. }),
    ) =>
      if p < 1.0 ||
        p > 38.0 ||
        s < 0.0 ||
        s > p ||
        p.trunc() != p ||
        s.trunc() != s {
        invalid(cursor, origin, InvalidArguments)
      }
    _ => invalid(cursor, origin, InvalidArguments)
  }
}

///|
fn template(
  text : String,
  cursor : @decode.Cursor,
  origin : Origin,
) -> Unit raise Stop {
  let chars = text.iter().to_array()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '{' || chars[i] == '}' {
      let opening = chars[i] == '{'
      if i + 1 < chars.length() && chars[i] == chars[i + 1] {
        i += 2
        continue
      }
      if !opening {
        invalid(cursor, origin, InvalidArguments)
      }
      i += 1
      let name = StringBuilder()
      while i < chars.length() && chars[i] != '}' {
        if chars[i] == '{' {
          invalid(cursor, origin, InvalidArguments)
        }
        name.write_char(chars[i])
        i += 1
      }
      if i == chars.length() || !field_name(name.to_string()) {
        invalid(cursor, origin, InvalidArguments)
      }
    }
    i += 1
  }
}
