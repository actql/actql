///|
/// Internal evaluation values. Structured admitted values remain immutable;
/// arithmetic does not coerce them. This package is not a Program run API.
pub(all) enum Value {
  Null
  Number(Double)
  Boolean(Bool)
  Text(String)
  Captured(@admitted.Value)
}

///|
pub(all) enum ScalarIssue {
  InvalidOperand
  ArithmeticFailure
  ComparisonDomainNotImplemented
} derive(Eq, Debug)

///|
priv enum ComparisonChargeIssue {
  ComparisonChargeLimit
  ComparisonChargeInvalidOperand
}

///|
pub fn capture(value : @admitted.Value) -> Value {
  match value {
    @admitted.Null => Null
    @admitted.Number(n) => Number(n)
    @admitted.Boolean(b) => Boolean(b)
    @admitted.Text(s) => Text(s)
    @admitted.Date(_)
    | @admitted.Timestamp(_)
    | @admitted.Decimal(_)
    | @admitted.Array(_)
    | @admitted.Object(_)
    | @admitted.JsonData(_)
    | @admitted.Vector(_)
    | @admitted.Reference(_) => Captured(value)
  }
}

///|
fn finite(n : Double) -> Result[Value, ScalarIssue] {
  if n.is_nan() || n.is_inf() {
    Err(ArithmeticFailure)
  } else {
    Ok(Number(if n == 0.0 { 0.0 } else { n }))
  }
}

///|
pub fn unary(
  op : @lower.UnaryOperator,
  value : Value,
) -> Result[Value, ScalarIssue] {
  match op {
    IsNull | IsUnknown => Ok(Boolean(value is Null))
    NotNull => Ok(Boolean(!(value is Null)))
    IsTrue => Ok(Boolean(value is Boolean(true)))
    IsFalse => Ok(Boolean(value is Boolean(false)))
    Not =>
      match value {
        Null => Ok(Null)
        Boolean(b) => Ok(Boolean(!b))
        Number(_) | Text(_) | Captured(_) => Err(InvalidOperand)
      }
    Negate =>
      match value {
        Null => Ok(Null)
        Number(n) => finite(-n)
        Captured(@admitted.Decimal(decimal)) => {
          let coefficient = decimal.coefficient
          let negated = if coefficient == "0" {
            "0"
          } else if coefficient.has_prefix("-") {
            coefficient[1:].to_owned()
          } else {
            "-" + coefficient
          }
          match @admitted.decimal_from_coefficient(
            negated,
            decimal.precision,
            decimal.scale,
          ) {
            Some(result) => Ok(Captured(result))
            _ => Err(InvalidOperand)
          }
        }
        Boolean(_) | Text(_) | Captured(_) => Err(InvalidOperand)
      }
  }
}

///|
/// No decimal rounding or JSON stringification is a numeric equality law.
fn compare(left : Value, right : Value) -> Result[Int, ScalarIssue] {
  match (left, right) {
    (Number(a), Number(b)) =>
      if a.is_nan() || b.is_nan() || a.is_inf() || b.is_inf() {
        Err(InvalidOperand)
      } else {
        Ok(if a < b { -1 } else if a > b { 1 } else { 0 })
      }
    (Boolean(a), Boolean(b)) => Ok(if a == b { 0 } else if a { 1 } else { -1 })
    (Text(a), Text(b)) => Ok(@canonical.compare_utf16(a, b))
    (Captured(@admitted.Date(a)), Captured(@admitted.Date(b)))
    | (Captured(@admitted.Timestamp(a)), Captured(@admitted.Timestamp(b))) =>
      // Admitted fixed-width UTC wire values have chronological lexical order.
      Ok(@canonical.compare_utf16(a, b))
    (Captured(@admitted.Decimal(a)), Captured(@admitted.Decimal(b))) =>
      Ok(compare_decimal(a, b))
    (Captured(@admitted.Reference(a)), Captured(@admitted.Reference(b))) =>
      if !@admitted.reference_available(a) || !@admitted.reference_available(b) {
        Err(InvalidOperand)
      } else if !@admitted.reference_same_domain(a, b) {
        Err(ComparisonDomainNotImplemented)
      } else {
        Ok(
          @canonical.compare_utf16(
            @admitted.reference_identity_cid(a),
            @admitted.reference_identity_cid(b),
          ),
        )
      }
    (Captured(_), _) | (_, Captured(_)) => Err(ComparisonDomainNotImplemented)
    _ => Err(InvalidOperand)
  }
}

///|
/// Exact numeric order over admitted coefficients, including differing scales.
/// No binary64 conversion, padded strings, or bounded-integer accumulation.
fn compare_decimal(
  a : @admitted.DecimalValue,
  b : @admitted.DecimalValue,
) -> Int {
  let ac = a.coefficient
  let bc = b.coefficient
  let an = ac[0] == '-'
  let bn = bc[0] == '-'
  if ac == "0" {
    return if bc == "0" { 0 } else if bn { 1 } else { -1 }
  }
  if bc == "0" {
    return if an { -1 } else { 1 }
  }
  if an != bn {
    return if an { -1 } else { 1 }
  }
  let ai = if an { 1 } else { 0 }
  let bi = if bn { 1 } else { 0 }
  let al = ac.length() - ai
  let bl = bc.length() - bi
  let ae = al - a.scale
  let be = bl - b.scale
  let direction = if an { -1 } else { 1 }
  if ae != be {
    return (if ae < be { -1 } else { 1 }) * direction
  }
  for i = 0; i < Int::max(al, bl); i = i + 1 {
    let x = if i < al { ac[ai + i] } else { '0' }
    let y = if i < bl { bc[bi + i] } else { '0' }
    if x != y {
      return (if x < y { -1 } else { 1 }) * direction
    }
  }
  0
}

///|
/// Caller-owned control budget must cover variable-size scalar comparison work.
/// Shared by expression evaluation and Relation ordering/equality kernels.
fn charge_comparison_operand(
  budget : ControlBudget,
  value : Value,
) -> Result[Unit, ComparisonChargeIssue] {
  match value {
    Text(s) =>
      if spend_control_text(budget, s) {
        Ok(())
      } else {
        Err(ComparisonChargeLimit)
      }
    Captured(@admitted.Date(s)) | Captured(@admitted.Timestamp(s)) =>
      if spend_control_text(budget, s) {
        Ok(())
      } else {
        Err(ComparisonChargeLimit)
      }
    Captured(@admitted.Decimal(d)) =>
      if spend_control_text(budget, d.coefficient) {
        Ok(())
      } else {
        Err(ComparisonChargeLimit)
      }
    Captured(@admitted.Reference(reference)) =>
      if !@admitted.reference_available(reference) {
        Err(ComparisonChargeInvalidOperand)
      } else if spend_control_text(
          budget,
          @admitted.reference_identity_cid(reference),
        ) {
        Ok(())
      } else {
        Err(ComparisonChargeLimit)
      }
    Null | Number(_) | Boolean(_) | Captured(_) => Ok(())
  }
}

///|
fn charge_comparison_pair(
  budget : ControlBudget,
  left : Value,
  right : Value,
) -> Result[Unit, ComparisonChargeIssue] {
  match charge_comparison_operand(budget, left) {
    Ok(_) => charge_comparison_operand(budget, right)
    Err(issue) => Err(issue)
  }
}

///|
/// Arguments are already evaluated, once and in source order, by the row
/// evaluator. Null handling here must not be used to skip either argument.
pub fn binary(
  op : @lower.BinaryOperator,
  left : Value,
  right : Value,
) -> Result[Value, ScalarIssue] {
  match op {
    In | NotIn => {
      let items = match right {
        Null => return Ok(Boolean(op == @lower.NotIn))
        Captured(@admitted.Array(items)) => items
        _ => return Err(InvalidOperand)
      }
      let mut matched = false
      let mut unknown = false
      for i in 0..<@admitted.element_count(items) {
        match
          binary(
            @lower.Equal,
            left,
            capture(@admitted.element_at(items, i).unwrap()),
          ) {
          Ok(Boolean(true)) => matched = true
          Ok(Boolean(false)) => ()
          Ok(Null) => unknown = true
          Ok(_) => return Err(InvalidOperand)
          Err(issue) => return Err(issue)
        }
      }
      Ok(membership_result(op, matched, unknown))
    }
    Add | Subtract | Multiply | Divide | Modulo => {
      if left is Null || right is Null {
        return Ok(Null)
      }
      guard left is Number(a) && right is Number(b) else {
        return Err(InvalidOperand)
      }
      if a.is_nan() || a.is_inf() || b.is_nan() || b.is_inf() {
        return Err(InvalidOperand)
      }
      match op {
        Add => finite(a + b)
        Subtract => finite(a - b)
        Multiply => finite(a * b)
        Divide => if b == 0.0 { Err(ArithmeticFailure) } else { finite(a / b) }
        Modulo => if b == 0.0 { Err(ArithmeticFailure) } else { finite(a % b) }
        Equal
        | NotEqual
        | IsDistinctFrom
        | Less
        | LessEqual
        | Greater
        | GreaterEqual
        | NullIf
        | In
        | NotIn => Err(InvalidOperand)
      }
    }
    Equal
    | NotEqual
    | IsDistinctFrom
    | Less
    | LessEqual
    | Greater
    | GreaterEqual
    | NullIf => {
      if left is Null {
        return Ok(
          if op == @lower.IsDistinctFrom {
            Boolean(!(right is Null))
          } else {
            Null
          },
        )
      }
      if right is Null {
        return Ok(
          match op {
            @lower.NullIf => left
            @lower.IsDistinctFrom => Boolean(true)
            _ => Null
          },
        )
      }
      let cmp = match compare(left, right) {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      binary_comparison_result(op, left, cmp)
    }
  }
}

///|
fn binary_comparison_result(
  op : @lower.BinaryOperator,
  left : Value,
  compared : Int,
) -> Result[Value, ScalarIssue] {
  match op {
    Equal => Ok(Boolean(compared == 0))
    NotEqual | IsDistinctFrom => Ok(Boolean(compared != 0))
    Less => Ok(Boolean(compared < 0))
    LessEqual => Ok(Boolean(compared <= 0))
    Greater => Ok(Boolean(compared > 0))
    GreaterEqual => Ok(Boolean(compared >= 0))
    NullIf => Ok(if compared == 0 { Null } else { left })
    Add | Subtract | Multiply | Divide | Modulo | In | NotIn =>
      Err(InvalidOperand)
  }
}

///|
/// Combining eager AND/OR results does not imply short-circuit evaluation.
pub fn boolean_pair(
  op : @lower.ManyOperator,
  left : Value,
  right : Value,
) -> Result[Value, ScalarIssue] {
  if !(left is Null || left is Boolean(_)) ||
    !(right is Null || right is Boolean(_)) {
    return Err(InvalidOperand)
  }
  match op {
    And =>
      Ok(
        if left is Boolean(false) || right is Boolean(false) {
          Boolean(false)
        } else if left is Null || right is Null {
          Null
        } else {
          Boolean(true)
        },
      )
    Or =>
      Ok(
        if left is Boolean(true) || right is Boolean(true) {
          Boolean(true)
        } else if left is Null || right is Null {
          Null
        } else {
          Boolean(false)
        },
      )
    Coalesce | Concat | ConcatStrict => Err(InvalidOperand)
  }
}

///|
fn membership_result(
  op : @lower.BinaryOperator,
  matched : Bool,
  unknown : Bool,
) -> Value {
  if matched {
    Boolean(op == @lower.In)
  } else if unknown {
    Null
  } else {
    Boolean(op == @lower.NotIn)
  }
}
