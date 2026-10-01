///|
/// Accept exactly the normative decimal/binary64 textual grammar before using
/// the existing finite JSON number reader. No trimming or host-language casts.
fn cast_number_lexeme(text : String, exponent~ : Bool) -> Bool {
  let size = text.length()
  let mut i = if size > 0 && text[0] == '-' { 1 } else { 0 }
  if i >= size {
    return false
  }
  if text[i] == '0' {
    i += 1
  } else if text[i] >= '1' && text[i] <= '9' {
    while i < size && text[i] >= '0' && text[i] <= '9' {
      i += 1
    }
  } else {
    return false
  }
  if i < size && text[i] == '.' {
    i += 1
    let start = i
    while i < size && text[i] >= '0' && text[i] <= '9' {
      i += 1
    }
    if i == start {
      return false
    }
  }
  if exponent && i < size && (text[i] == 'e' || text[i] == 'E') {
    i += 1
    if i < size && (text[i] == '+' || text[i] == '-') {
      i += 1
    }
    let start = i
    while i < size && text[i] >= '0' && text[i] <= '9' {
      i += 1
    }
    if i == start {
      return false
    }
  }
  i == size
}

///|
fn cast_text_decimal(text : String, precision : Int, scale : Int) -> Value? {
  if !cast_number_lexeme(text, exponent=false) {
    return None
  }
  let negative = text[0] == '-'
  let start = if negative { 1 } else { 0 }
  let digits = StringBuilder()
  let mut fractional = -1
  let mut significant = 0
  for i = start; i < text.length(); i = i + 1 {
    let unit = text[i]
    if unit == '.' {
      fractional = 0
      continue
    }
    if fractional >= 0 {
      fractional += 1
    }
    if significant > 0 || unit != '0' {
      significant += 1
      if significant > precision {
        return None
      }
      digits.write_char(unit.to_int().unsafe_to_char())
    }
  }
  if fractional > scale {
    return None
  }
  if significant == 0 {
    if negative {
      return None
    }
    return @admitted.decimal_from_coefficient("0", precision, scale).map(
      capture,
    )
  }
  let padding = scale - fractional.max(0)
  if significant + padding > precision {
    return None
  }
  let coefficient = (if negative { "-" } else { "" }) +
    digits.to_string() +
    String::make(padding, '0')
  @admitted.decimal_from_coefficient(coefficient, precision, scale).map(capture)
}

///|
fn cast_decimal_scale(
  value : @admitted.DecimalValue,
  precision : Int,
  scale : Int,
) -> Value? {
  if value.coefficient == "0" {
    return @admitted.decimal_from_coefficient("0", precision, scale).map(
      capture,
    )
  }
  let negative = value.coefficient[0] == '-'
  let start = if negative { 1 } else { 0 }
  let count = value.coefficient.length() - start
  let difference = scale - value.scale
  let coefficient = if difference >= 0 {
    if count + difference > precision {
      return None
    }
    value.coefficient + String::make(difference, '0')
  } else {
    let end = value.coefficient.length() + difference
    if end <= start {
      return None
    }
    for i = end; i < value.coefficient.length(); i = i + 1 {
      if value.coefficient[i] != '0' {
        return None
      }
    }
    String::from_array(value.coefficient.to_array()[:end])
  }
  @admitted.decimal_from_coefficient(coefficient, precision, scale).map(capture)
}

///|
/// Conversion is demanded inside the existing expression frame. Preflight
/// variable-size work against its physical control budget before allocating;
/// the caller retains ordinary logical operand/result charging and root leases.
fn cast_expression_value(
  expression : @lower.Expression,
  child : @lower.Expression,
  value : Value,
  budget : ControlBudget,
) -> Result[Value, EvalIssue] {
  if value is Null {
    return Ok(Null)
  }
  let text_limit = budget.remaining
  // Cover lexing, parsing, validation and canonical spelling passes. This is
  // physical control work only; expression semantic charges stay unchanged.
  for _i = 0; _i < 8; _i = _i + 1 {
    match charge_comparison_operand(budget, value) {
      Err(ComparisonChargeLimit) =>
        return Err({ kind: ControlLimit, expression, })
      Err(_) => return Err({ kind: Scalar(InvalidOperand), expression, })
      Ok(_) => ()
    }
  }
  if !spend_control(budget, 64) {
    return Err({ kind: ControlLimit, expression, })
  }
  let converted = match @lower.expression_contract(expression).shape {
    Number =>
      match value {
        Number(n) =>
          match finite(n) {
            Ok(v) => Some(v)
            Err(_) => None
          }
        Text(text) =>
          if !cast_number_lexeme(text, exponent=true) {
            None
          } else {
            match
              @source.parse_json(text, {
                max_input_bytes: text.length(),
                max_nodes: 1,
                max_depth: 1,
              }) {
              Ok({ value: @source.Number(n), .. }) =>
                match finite(n) {
                  Ok(v) => Some(v)
                  Err(_) => None
                }
              Err({ issue: @source.NegativeZero, .. }) => Some(Number(0.0))
              _ => None
            }
          }
        _ => None
      }
    Boolean =>
      match value {
        Boolean(_) => Some(value)
        Text("true") => Some(Boolean(true))
        Text("false") => Some(Boolean(false))
        _ => None
      }
    Timestamp =>
      match value {
        Captured(@admitted.Timestamp(_)) => Some(value)
        Text(text) =>
          @admitted.checked_timestamp_value(
            text,
            @lower.expression_contract(expression),
          ).map(fn(v) { capture(v.value) })
        _ => None
      }
    Text(_) => {
      // Scalar output is at most 64 bytes larger than the charged operand:
      // decimal padding is bounded by precision 38, binary64 by its grammar.
      let admitted = match value {
        Number(n) => @admitted.number_value(n)
        Boolean(b) => Some(@admitted.boolean_value(b))
        Text(s) => @admitted.text_value(s, text_limit)
        Captured(v) => Some(v)
        Null => None
      }
      match admitted {
        Some(v) =>
          match
            @admitted.recheck_runtime_value(
              v,
              @lower.expression_contract(child),
              { max_nodes: 1, max_depth: 1, max_text_bytes: text_limit, },
            ) {
            Some(checked) =>
              @admitted.canonical_scalar_text(checked, text_limit).map(fn(s) {
                Text(s)
              })
            None => None
          }
        None => None
      }
    }
    Decimal(precision~, scale~) =>
      match value {
        Text(text) => cast_text_decimal(text, precision, scale)
        Number(n) =>
          match @scalar.read_safe_integer(n) {
            Some(integer) =>
              cast_text_decimal(integer.to_string(), precision, scale)
            None => None
          }
        Captured(@admitted.Decimal(d)) =>
          cast_decimal_scale(d, precision, scale)
        _ => None
      }
    _ => None
  }
  match converted {
    Some(v) => Ok(v)
    None => Err({ kind: Scalar(InvalidOperand), expression, })
  }
}
