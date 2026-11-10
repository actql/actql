///|
// The generator emits this variant only when a oneOf schema also has
// constraining sibling keywords. Keep the validator ready for that case.
#warnings("-unused_constructor")
priv enum ProtocolSchemaRule {
  AnyRule
  NullRule
  BoolRule(Bool?)
  StringRule(String?, Array[String], Int, Int)
  StringCeilingRule(Int)
  ObjectCeilingRule(Int)
  NumberRule
  IntegerRule(Int64?, Int64?)
  ArrayRule(Int, Int, Bool, Int)
  ContainsRule(Int)
  TupleRule(Array[Int])
  ObjectRule(Array[(String, Int)], Array[String], Int, Int, String?, Int)
  OneOfRule(Array[Int])
  AnyOfRule(Array[Int])
  AllOfRule(Array[Int])
  NotRule(Int)
  ConditionalRule(Int, Int, Int)
}

///|
priv struct ProtocolValidationBudget {
  mut remaining : Int
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
fn protocol_any_rule() -> ProtocolSchemaRule {
  AnyRule
}

///|
/// JSON Schema lengths count Unicode scalar values. Admitted canonical text
/// already excludes unpaired surrogates; do not count a pair as two cells.
fn protocol_scalar_length(text : String) -> Int {
  let mut count = 0
  let mut i = 0
  while i < text.length() {
    count += 1
    let unit = text[i].to_int()
    if unit >= 55296 && unit <= 56319 {
      i += 1
    }
    i += 1
  }
  count
}

///|
fn protocol_null_rule() -> ProtocolSchemaRule {
  NullRule
}

///|
fn protocol_bool_rule(exact : Bool?) -> ProtocolSchemaRule {
  BoolRule(exact)
}

///|
fn protocol_string_rule(
  exact : String?,
  choices : Array[String],
  pattern : Int,
  min_length : Int,
) -> ProtocolSchemaRule {
  StringRule(exact, choices, pattern, min_length)
}

///|
fn protocol_integer_rule(
  minimum : Int64?,
  maximum : Int64?,
) -> ProtocolSchemaRule {
  IntegerRule(minimum, maximum)
}

///|
fn protocol_number_rule() -> ProtocolSchemaRule {
  NumberRule
}

///|
fn protocol_array_rule(
  items : Int,
  min_items : Int,
  unique : Bool,
  max_items : Int,
) -> ProtocolSchemaRule {
  ArrayRule(items, min_items, unique, max_items)
}

///|
// Exact positional schemas borrow the existing immutable rule table. They
// neither copy the input array nor grant authority to a decoded resource state.
fn protocol_tuple_rule(items : Array[Int]) -> ProtocolSchemaRule {
  TupleRule(items)
}

///|
/// `additional` is -2 for allowed, -1 for rejected, or a schema index.
fn protocol_object_rule(
  properties : Array[(String, Int)],
  required : Array[String],
  additional : Int,
  min_properties : Int,
  forbidden_property_prefix : String?,
) -> ProtocolSchemaRule {
  ObjectRule(
    properties, required, additional, min_properties, forbidden_property_prefix,
    0,
  )
}

///|
fn protocol_named_object_rule(
  properties : Array[(String, Int)],
  required : Array[String],
  additional : Int,
  min_properties : Int,
  forbidden_property_prefix : String?,
  property_name_pattern : Int,
) -> ProtocolSchemaRule {
  ObjectRule(
    properties, required, additional, min_properties, forbidden_property_prefix,
    property_name_pattern,
  )
}

///|
fn protocol_one_of_rule(alternatives : Array[Int]) -> ProtocolSchemaRule {
  OneOfRule(alternatives)
}

///|
fn version_token_char(unit : Int) -> Bool {
  (unit >= 48 && unit <= 57) ||
  (unit >= 65 && unit <= 90) ||
  (unit >= 97 && unit <= 122) ||
  unit == 46 ||
  unit == 95 ||
  unit == 43 ||
  unit == 58 ||
  unit == 45
}

///|
fn valid_version_token(value : String) -> Bool {
  if value.is_empty() || value.length() > 128 {
    return false
  }
  let first = value[0].to_int()
  if !((first >= 48 && first <= 57) ||
    (first >= 65 && first <= 90) ||
    (first >= 97 && first <= 122)) {
    return false
  }
  for index = 1; index < value.length(); index = index + 1 {
    if !version_token_char(value[index].to_int()) {
      return false
    }
  }
  true
}

///|
fn protocol_string_pattern(value : String, pattern : Int) -> Bool {
  match pattern {
    0 => true
    1 => valid_contract_cid(value)
    2 => valid_timestamp(value)
    3 => valid_version_token(value)
    4 => valid_digest(value)
    5 => value.has_prefix("$")
    6 => value.has_prefix("command:")
    7 =>
      if value.length() == 0 {
        false
      } else {
        let first = value[0].to_int()
        if !((first >= 65 && first <= 90) ||
          (first >= 97 && first <= 122) ||
          first == 95) {
          false
        } else {
          let mut valid = true
          for index = 1; index < value.length(); index = index + 1 {
            let char = value[index].to_int()
            if !((char >= 65 && char <= 90) ||
              (char >= 97 && char <= 122) ||
              (char >= 48 && char <= 57) ||
              char == 95) {
              valid = false
            }
          }
          valid
        }
      }
    8 =>
      if value == "0" {
        true
      } else if value.length() == 0 ||
        value[0].to_int() < 49 ||
        value[0].to_int() > 57 {
        false
      } else {
        let mut valid = true
        for index = 1; index < value.length(); index = index + 1 {
          let char = value[index].to_int()
          if char < 48 || char > 57 {
            valid = false
          }
        }
        valid
      }
    9 => {
      let mut valid = value.length() > 0
      for char in value.to_array() {
        if char.to_int() < 32 || char.to_int() == 127 {
          valid = false
        }
      }
      valid
    }
    10 =>
      if !value.has_prefix("ACTQL_E_") || value.length() <= 8 {
        false
      } else {
        let mut valid = true
        for index = 8; index < value.length(); index = index + 1 {
          let char = value[index].to_int()
          if !((char >= 65 && char <= 90) ||
            (char >= 48 && char <= 57) ||
            char == 95) {
            valid = false
          }
        }
        valid
      }
    11 => value.length() > 0
    12 => parse_control_amount_micro(value) is Ok(_)
    13 => {
      let mut valid = value.length() == 3
      for char in value.to_array() {
        if char.to_int() < 65 || char.to_int() > 90 {
          valid = false
        }
      }
      valid
    }
    14 =>
      if value == "0" {
        true
      } else {
        let first = if value.has_prefix("-") { 1 } else { 0 }
        if value.length() <= first ||
          value[first].to_int() < 49 ||
          value[first].to_int() > 57 {
          false
        } else {
          let mut valid = true
          for index = first + 1; index < value.length(); index = index + 1 {
            let unit = value[index].to_int()
            if unit < 48 || unit > 57 {
              valid = false
            }
          }
          valid
        }
      }
    15 =>
      value.length() <= 20 &&
      protocol_string_pattern(value, 8) &&
      (value.length() < 20 || value <= "18446744073709551615")
    _ => false
  }
}

///|
fn protocol_property_schema(
  properties : Array[(String, Int)],
  name : String,
) -> Int? {
  for (key, value) in properties {
    if key == name {
      return Some(value)
    }
  }
  None
}

///|
fn protocol_unique_array(
  values : Array[@json.CanonicalValue],
  budget : ProtocolValidationBudget,
) -> Bool {
  let seen : Array[String] = []
  for value in values {
    let wire = @json.stringify_value(
      value,
      budget.max_wire_bytes,
      budget.max_nodes,
      budget.max_depth,
    ) catch {
      _ => return false
    }
    if seen.contains(wire) {
      return false
    }
    seen.push(wire)
  }
  true
}

///|
fn validate_protocol_node(
  value : @json.CanonicalValue,
  index : Int,
  nodes : Array[ProtocolSchemaRule],
  budget : ProtocolValidationBudget,
) -> Bool {
  let cursor = start_protocol_validation(value, index, nodes, budget)
  while !cursor.advance(256).0 {
    ()
  }
  let result = cursor.result
  cursor.cancel()
  result
}

///|
// Private immutable metadata generated from the pinned protocol contract.
// Construct it at module initialization, before Native calls can run in parallel.
// Validation state/budget is per call; no caller value or result is retained.
let retained_protocol_schema_nodes : Array[ProtocolSchemaRule] = generated_protocol_schema_nodes()

///|
fn protocol_schema_nodes() -> Array[ProtocolSchemaRule] {
  retained_protocol_schema_nodes
}

///|
fn validate_generated_protocol_shape(
  name : String,
  value : @json.CanonicalValue,
  complete : Bool,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Bool {
  guard generated_protocol_schema_root(name, complete) is Some(root) else {
    return false
  }
  let nodes = protocol_schema_nodes()
  let validation_work = if max_nodes > 268435455 {
    2147483647
  } else {
    max_nodes * 8
  }
  validate_protocol_node(value, root, nodes, {
    remaining: validation_work,
    max_wire_bytes,
    max_nodes,
    max_depth,
  }) &&
  (
    name != "model_original_storage_binding" ||
    model_original_storage_binding_shape(value)
  )
}

///|
/// Parse the closed private Effect Preview shape. This does not establish
/// its semantic CID, nested identities, current authority, or apply admission.
/// Data-bearing members keep exact keys; the generated schema still admits
/// structural field names and the complete wire must already be canonical.
pub fn parse_effect_preview_shape(
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@json.CanonicalValue, PublicationContractIssue] {
  let value = match
    parse_contract_wire(
      wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
      data_keys=true,
    ) {
    Ok(parsed) => parsed
    Err(issue) => return Err(issue)
  }
  check_effect_preview_shape_original(
    wire, value, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
// Both the wire parser and a funded original cursor use this SAME complete
// canonical-wire and generated shape check. Neither path supplies authority.
fn check_effect_preview_shape_original(
  wire : String,
  value : @json.CanonicalValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@json.CanonicalValue, PublicationContractIssue] {
  let canonical = @json.stringify_value(
    value, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  if canonical != wire {
    return Err(InvalidWire)
  }
  if !validate_generated_protocol_shape(
      "effect_preview", value, true, max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(InvalidField("effect_preview"))
  }
  Ok(value)
}

///|
/// Canonicalize a complete Preview draft before semantic identities are
/// issued. This does not admit its references or authorize an Effect apply.
/// Ordering must not normalize the values whose identities will be sealed.
pub fn canonical_effect_preview_draft_wire(
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, PublicationContractIssue] {
  let value = match
    parse_contract_wire(
      wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
      data_keys=true,
    ) {
    Ok(parsed) => parsed
    Err(issue) => return Err(issue)
  }
  if !validate_generated_protocol_shape(
      "effect_preview", value, true, max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(InvalidField("effect_preview"))
  }
  let canonical = @json.stringify_value(
    value, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  Ok(canonical)
}

///|
/// Admit the closed, canonical EffectOutcome value shape. This does not bind
/// a provider response, Preview row, dispatch, or terminal Receipt.
/// Provider result/error data remains exact inside the closed outer shape.
pub fn parse_effect_outcome_shape(
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@json.CanonicalValue, PublicationContractIssue] {
  let value = match
    parse_contract_wire(
      wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
      data_keys=true,
    ) {
    Ok(parsed) => parsed
    Err(issue) => return Err(issue)
  }
  let canonical = @json.stringify_value(
    value, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  if canonical != wire {
    return Err(InvalidWire)
  }
  if !validate_generated_protocol_shape(
      "effect_outcome", value, true, max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(InvalidField("effect_outcome"))
  }
  Ok(value)
}

///|
// Exact historical root-field omission through the same generated rule table
// and validator. No temporary revision/wire, copied table or larger budget.
// Current public validation cannot select this private compatibility path.
fn validate_historical_run_state_shape(
  value : @json.CanonicalValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Bool {
  guard generated_protocol_schema_root("run_state", true) is Some(root) else {
    return false
  }
  let cursor = start_protocol_validation(
    value,
    root,
    protocol_schema_nodes(),
    {
      remaining: if max_nodes > 268435455 {
        2147483647
      } else {
        max_nodes * 8
      },
      max_wire_bytes,
      max_nodes,
      max_depth,
    },
    historical_run_state=true,
  )
  while !cursor.advance(256).0 {
    ()
  }
  let result = cursor.result
  cursor.cancel()
  result
}
