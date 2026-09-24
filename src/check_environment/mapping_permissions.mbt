///|
pub(all) enum MappingPermissionIssue {
  InvalidLimits
  InvalidRequest
  InvalidRule(Int)
  InvalidRequiredPermissions
  WorkLimit
  NoMatchingRule
  AmbiguousRules
} derive(Eq, Debug)

///|
pub struct MappingPermissionSelection {
  shape : MappingContractShape
  effect_kind : String
  selector_class : String
  write_fields : Array[String]
  permissions : Array[String]
  required_permissions : Array[String]
  work : Int
}

///|
pub fn mapping_permission_shape(
  selection : MappingPermissionSelection,
) -> MappingContractShape {
  selection.shape
}

///|
pub fn mapping_permission_rule(
  selection : MappingPermissionSelection,
) -> (String, String, Array[String]) {
  (
    selection.effect_kind,
    selection.selector_class,
    selection.write_fields.copy(),
  )
}

///|
pub fn mapping_permission_names(
  selection : MappingPermissionSelection,
) -> Array[String] {
  selection.permissions.copy()
}

///|
pub fn mapping_permission_required_names(
  selection : MappingPermissionSelection,
) -> Array[String] {
  selection.required_permissions.copy()
}

///|
pub fn mapping_permission_work(selection : MappingPermissionSelection) -> Int {
  selection.work
}

///|
priv suberror MappingPermissionStop {
  MappingPermissionStop(MappingPermissionIssue)
}

///|
fn mapping_permission_charge(
  remaining : Ref[Int],
  amount : Int,
) -> Unit raise MappingPermissionStop {
  if amount < 0 || amount > remaining.val {
    raise MappingPermissionStop(WorkLimit)
  }
  remaining.val -= amount
}

///|
fn mapping_permission_words(
  array : @decode.Cursor,
  remaining : Ref[Int],
  invalid : MappingPermissionIssue,
  require_nonempty : Bool,
) -> Array[String] raise MappingPermissionStop {
  let count = match @decode.array_length(array) {
    Some(value) if !require_nonempty || value > 0 => value
    _ => raise MappingPermissionStop(invalid)
  }
  mapping_permission_charge(remaining, count)
  let seen : Map[String, Bool] = Map([])
  let values : Array[String] = []
  for index in 0..<count {
    let value = match @decode.text(@decode.element_at(array, index).unwrap()) {
      Ok(text) if !text.is_empty() => text
      _ => raise MappingPermissionStop(invalid)
    }
    if seen.contains(value) {
      raise MappingPermissionStop(invalid)
    }
    seen[value] = true
    values.push(value)
  }
  values
}

///|
fn mapping_permission_equal_set(
  left : Array[String],
  right : Array[String],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  let names : Map[String, Bool] = Map([])
  for value in left {
    names[value] = true
  }
  for value in right {
    if !names.contains(value) {
      return false
    }
  }
  true
}

///|
fn mapping_permission_valid_kind(value : String) -> Bool {
  ["create", "update", "upsert", "delete", "store"].contains(value)
}

///|
fn mapping_permission_valid_selector(value : String) -> Bool {
  ["none", "id", "match", "ids", "external_id", "where", "key"].contains(value)
}

///|
fn mapping_permission_rule_text(
  object : @decode.ObjectView,
  key : String,
  index : Int,
) -> String raise MappingPermissionStop {
  let value = match @decode.lookup(object, key) {
    Some(value) => value
    None => raise MappingPermissionStop(InvalidRule(index))
  }
  match @decode.text(value) {
    Ok(text) if !text.is_empty() => text
    _ => raise MappingPermissionStop(InvalidRule(index))
  }
}

///|
/// Selects exactly one static Mapping permission rule for the complete
/// requested write-field set. This does not check a current grant, provider
/// authority, Preview guard, or apply admission.
pub fn select_mapping_permissions(
  shape : MappingContractShape,
  effect_kind : String,
  selector_class : String,
  write_fields : Array[String],
  max_work : Int,
) -> Result[MappingPermissionSelection, MappingPermissionIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if !mapping_permission_valid_kind(effect_kind) ||
    !mapping_permission_valid_selector(selector_class) {
    return Err(InvalidRequest)
  }
  let remaining = Ref(max_work)
  try {
    mapping_permission_charge(remaining, write_fields.length())
    let requested : Map[String, Bool] = Map([])
    let writable : Map[String, Bool] = Map([])
    mapping_permission_charge(remaining, shape.writable_fields.length())
    for field in shape.writable_fields {
      writable[field] = true
    }
    for field in write_fields {
      if !writable.contains(field) || requested.contains(field) {
        raise MappingPermissionStop(InvalidRequest)
      }
      requested[field] = true
    }
    let root = member_body(shape.item)
    let object = @decode.open_object(root).unwrap()
    let required = match @decode.lookup(object, "required_permissions") {
      Some(value) =>
        mapping_permission_words(
          value,
          remaining,
          InvalidRequiredPermissions,
          false,
        )
      None => raise MappingPermissionStop(InvalidRequiredPermissions)
    }
    let rules = match @decode.lookup(object, "permission_rules") {
      Some(value) => value
      None => raise MappingPermissionStop(InvalidRule(0))
    }
    let count = match @decode.array_length(rules) {
      Some(value) if value > 0 => value
      _ => raise MappingPermissionStop(InvalidRule(0))
    }
    let mut matched : Array[String]? = None
    for index in 0..<count {
      mapping_permission_charge(remaining, 1)
      let rule = @decode.element_at(rules, index).unwrap()
      let entry = match
        @decode.closed_object(rule, [
          "effect_kind", "selector_class", "write_fields", "permissions",
        ]) {
        Ok(value) => value
        Err(_) => raise MappingPermissionStop(InvalidRule(index))
      }
      let kind = mapping_permission_rule_text(entry, "effect_kind", index)
      let selector = mapping_permission_rule_text(
        entry, "selector_class", index,
      )
      if !mapping_permission_valid_kind(kind) ||
        !mapping_permission_valid_selector(selector) {
        raise MappingPermissionStop(InvalidRule(index))
      }
      let fields = match @decode.lookup(entry, "write_fields") {
        Some(value) =>
          mapping_permission_words(value, remaining, InvalidRule(index), false)
        None => raise MappingPermissionStop(InvalidRule(index))
      }
      for field in fields {
        if !writable.contains(field) {
          raise MappingPermissionStop(InvalidRule(index))
        }
      }
      let permissions = match @decode.lookup(entry, "permissions") {
        Some(value) =>
          mapping_permission_words(value, remaining, InvalidRule(index), true)
        None => raise MappingPermissionStop(InvalidRule(index))
      }
      if kind == effect_kind &&
        selector == selector_class &&
        mapping_permission_equal_set(fields, write_fields) {
        if matched is Some(_) {
          raise MappingPermissionStop(AmbiguousRules)
        }
        matched = Some(permissions)
      }
    }
    match matched {
      Some(permissions) =>
        Ok({
          shape,
          effect_kind,
          selector_class,
          write_fields: write_fields.copy(),
          permissions,
          required_permissions: required,
          work: max_work - remaining.val,
        })
      None => Err(NoMatchingRule)
    }
  } catch {
    MappingPermissionStop(issue) => Err(issue)
  }
}
