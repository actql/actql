///|
// The generator emits this variant only when a oneOf schema also has
// constraining sibling keywords. Keep the validator ready for that case.
#warnings("-unused_constructor")
priv enum ProtocolSchemaRule {
  AnyRule
  NullRule
  BoolRule(Bool?)
  StringRule(String?, Array[String], Int, Int)
  NumberRule
  IntegerRule(Int64?, Int64?)
  ArrayRule(Int, Int, Bool)
  ObjectRule(Array[(String, Int)], Array[String], Int, Int, String?)
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
) -> ProtocolSchemaRule {
  ArrayRule(items, min_items, unique)
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
  if index < 0 || index >= nodes.length() || budget.remaining < 1 {
    return false
  }
  budget.remaining -= 1
  match nodes[index] {
    AnyRule => true
    NullRule => value is @json.Null
    BoolRule(exact) =>
      match value {
        @json.Bool(actual) =>
          exact.map(expected => expected == actual).unwrap_or(true)
        _ => false
      }
    StringRule(exact, choices, pattern, min_length) =>
      match value {
        @json.String(text) =>
          text.length() >= min_length &&
          exact.map(expected => expected == text).unwrap_or(true) &&
          (choices.is_empty() || choices.contains(text)) &&
          protocol_string_pattern(text, pattern)
        _ => false
      }
    NumberRule => value is @json.Number(_)
    IntegerRule(minimum, maximum) =>
      match value {
        @json.Number(number) =>
          match @scalar.read_safe_integer(number) {
            Some(actual) =>
              minimum.map(bound => actual >= bound).unwrap_or(true) &&
              maximum.map(bound => actual <= bound).unwrap_or(true)
            None => false
          }
        _ => false
      }
    ArrayRule(items, min_items, unique) =>
      match value {
        @json.Array(frozen) => {
          let values = @json.array_values(frozen)
          if values.length() < min_items ||
            (unique && !protocol_unique_array(values, budget)) {
            return false
          }
          for item in values {
            if !validate_protocol_node(item, items, nodes, budget) {
              return false
            }
          }
          true
        }
        _ => false
      }
    ObjectRule(
      properties,
      required,
      additional,
      min_properties,
      forbidden_property_prefix
    ) =>
      match object_fields(value) {
        Ok(fields) => {
          if fields.length() < min_properties {
            return false
          }
          for name in required {
            if field_value(fields, name) is None {
              return false
            }
          }
          for (name, child) in fields {
            if forbidden_property_prefix
              .map(prefix => name.has_prefix(prefix))
              .unwrap_or(false) {
              return false
            }
            match protocol_property_schema(properties, name) {
              Some(child_schema) =>
                if !validate_protocol_node(child, child_schema, nodes, budget) {
                  return false
                }
              None if additional >= 0 =>
                if !validate_protocol_node(child, additional, nodes, budget) {
                  return false
                }
              None if additional == -1 => return false
              None => ()
            }
          }
          true
        }
        Err(_) => false
      }
    OneOfRule(alternatives) => {
      let mut matches = 0
      for alternative in alternatives {
        let branch_budget = {
          remaining: budget.remaining,
          max_wire_bytes: budget.max_wire_bytes,
          max_nodes: budget.max_nodes,
          max_depth: budget.max_depth,
        }
        if validate_protocol_node(value, alternative, nodes, branch_budget) {
          matches += 1
        }
        budget.remaining = branch_budget.remaining
      }
      budget.remaining > 0 && matches == 1
    }
    AnyOfRule(alternatives) => {
      let mut matches = 0
      for alternative in alternatives {
        let branch_budget = {
          remaining: budget.remaining,
          max_wire_bytes: budget.max_wire_bytes,
          max_nodes: budget.max_nodes,
          max_depth: budget.max_depth,
        }
        if validate_protocol_node(value, alternative, nodes, branch_budget) {
          matches += 1
        }
        budget.remaining = branch_budget.remaining
      }
      matches > 0
    }
    AllOfRule(conditions) => {
      for condition in conditions {
        if !validate_protocol_node(value, condition, nodes, budget) {
          return false
        }
      }
      true
    }
    NotRule(excluded) => {
      if budget.remaining <= 1 {
        return false
      }
      let excluded_match = validate_protocol_node(
        value, excluded, nodes, budget,
      )
      budget.remaining > 0 && !excluded_match
    }
    ConditionalRule(condition, when_true, when_false) => {
      let branch = if validate_protocol_node(value, condition, nodes, budget) {
        when_true
      } else {
        when_false
      }
      validate_protocol_node(value, branch, nodes, budget)
    }
  }
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
  let nodes = generated_protocol_schema_nodes()
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
  })
}

///|
/// Parse the closed private Effect Preview shape. This does not establish
/// its semantic CID, nested identities, current authority, or apply admission.
pub fn parse_effect_preview_shape(
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@json.CanonicalValue, PublicationContractIssue] {
  let value = match
    parse_contract_wire(wire, max_wire_bytes, max_nodes, max_depth) {
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
      "effect_preview", value, true, max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(InvalidField("effect_preview"))
  }
  Ok(value)
}
