///|
priv struct RecheckBudget {
  mut nodes : Int
  mut text : Int
  max_depth : Int
}

///|
fn recheck_text(value : String, budget : RecheckBudget) -> Int? {
  guard @scalar.admit_utf8_length(value, budget.text) is Ok(bytes) &&
    @canonical.normalize_nfc_lf(value) is Ok(normalized) &&
    normalized == value else {
    return None
  }
  budget.text -= bytes
  Some(bytes)
}

///|
fn recheck_json(value : Value, budget : RecheckBudget, depth : Int) -> Bool {
  if budget.nodes == 0 {
    return false
  }
  budget.nodes -= 1
  match value {
    Null | Boolean(_) => true
    Number(number) =>
      !number.is_nan() &&
      !number.is_inf() &&
      !(number == 0.0 && 1.0 / number < 0.0)
    Text(text) => recheck_text(text, budget) is Some(_)
    Array(values) => {
      if depth >= budget.max_depth {
        return false
      }
      values.values.all(value => recheck_json(value, budget, depth + 1))
    }
    Object(values) => {
      if depth >= budget.max_depth {
        return false
      }
      for (name, child) in values.values {
        if recheck_text(name, budget) is None ||
          !recheck_json(child, budget, depth + 1) {
          return false
        }
      }
      true
    }
    Date(_) | Timestamp(_) | Decimal(_) | Vector(_) | Reference(_) => false
  }
}

///|
fn recheck_value(
  value : Value,
  contract : @contract.Contract,
  budget : RecheckBudget,
  depth : Int,
) -> Bool {
  if budget.nodes == 0 {
    return false
  }
  budget.nodes -= 1
  if value is Null {
    return contract.nullable
  }
  match (value, contract.shape) {
    (Boolean(_), @contract.Boolean) => true
    (Number(number), @contract.Number) =>
      !number.is_nan() &&
      !number.is_inf() &&
      !(number == 0.0 && 1.0 / number < 0.0)
    (Text(text), @contract.Text(bounds)) => {
      guard recheck_text(text, budget) is Some(bytes) &&
        @scalar.unicode_scalar_count(text) is Some(count) else {
        return false
      }
      let characters = count.to_int64()
      let byte_count = bytes.to_int64()
      (bounds.min_length is None || characters >= bounds.min_length.unwrap()) &&
      (
        bounds.max_codepoints is None ||
        characters <= bounds.max_codepoints.unwrap()
      ) &&
      (
        bounds.max_utf8_bytes is None ||
        byte_count <= bounds.max_utf8_bytes.unwrap()
      )
    }
    (Date(text), @contract.Date) =>
      recheck_text(text, budget) is Some(_) &&
      text.length() == 10 &&
      valid_date(text)
    (Timestamp(text), @contract.Timestamp) =>
      recheck_text(text, budget) is Some(_) && valid_timestamp(text)
    (Decimal(decimal_value), @contract.Decimal(precision~, scale~)) => {
      guard recheck_text(decimal_value.coefficient, budget) is Some(_) &&
        decimal_from_coefficient(decimal_value.coefficient, precision, scale)
        is Some(Decimal(canonical)) else {
        return false
      }
      decimal_value.precision == canonical.precision &&
      decimal_value.scale == canonical.scale &&
      decimal_value.coefficient == canonical.coefficient
    }
    (Vector(values), @contract.Vector(dimensions~)) => {
      let count = values.values.length()
      if depth >= budget.max_depth ||
        count.to_double() != dimensions ||
        count > budget.nodes {
        return false
      }
      budget.nodes -= count
      values.values.all(component => {
        !component.is_nan() &&
        !component.is_inf() &&
        !(component == 0.0 && 1.0 / component < 0.0)
      })
    }
    (Array(values), @contract.Array(item, max_items~)) => {
      let count = values.values.length()
      if depth >= budget.max_depth ||
        (max_items is Some(limit) && count.to_int64() > limit) {
        return false
      }
      values.values.all(value => recheck_value(value, item, budget, depth + 1))
    }
    (Object(values), @contract.Object(fields)) => {
      if depth >= budget.max_depth ||
        values.values.length() != @contract.field_count(fields) {
        return false
      }
      for index in 0..<values.values.length() {
        let (name, child) = values.values[index]
        guard @contract.field_at(fields, index) is Some(field) &&
          name == field.name &&
          recheck_text(name, budget) is Some(_) &&
          recheck_value(child, field.contract, budget, depth + 1) else {
          return false
        }
      }
      true
    }
    (Reference(reference), @contract.ResourceRef(_))
    | (Reference(reference), @contract.ArtifactRef(_)) =>
      reference_available(reference) &&
      reference_compatible(reference, contract)
    (_, @contract.Json) => {
      budget.nodes += 1
      recheck_json(value, budget, depth)
    }
    _ => false
  }
}

///|
/// Rebind an immutable runtime value to a checked contract only after a full
/// bounded structural validation. No coercion, rounding, repair, or reference
/// authority is introduced.
pub fn recheck_runtime_value(
  value : Value,
  contract : @contract.Contract,
  limits : Limits,
) -> CheckedValue? {
  recheck_runtime_value_usage(value, contract, limits).map(result => result.0)
}

///|
/// Rebind an immutable runtime value and report its exact logical value-node
/// and UTF-8 text usage. No partial usage escapes when validation fails.
pub fn recheck_runtime_value_usage(
  value : Value,
  contract : @contract.Contract,
  limits : Limits,
) -> (CheckedValue, Int, Int)? {
  if limits.max_nodes < 0 || limits.max_depth < 0 || limits.max_text_bytes < 0 {
    return None
  }
  let budget : RecheckBudget = {
    nodes: limits.max_nodes,
    text: limits.max_text_bytes,
    max_depth: limits.max_depth,
  }
  if recheck_value(value, contract, budget, 0) {
    Some(
      (
        { contract, value, },
        limits.max_nodes - budget.nodes,
        limits.max_text_bytes - budget.text,
      ),
    )
  } else {
    None
  }
}
