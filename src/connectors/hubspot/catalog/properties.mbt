///|
/// Physical limits for one complete properties response. These do not grant
/// schema access, prove currentness, or impose a Connector language limit.
pub(all) struct PropertyLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_properties : Int
  max_name_units : Int
}

///|
pub(all) enum PropertyIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  ForeignCatalog
  DuplicateProperty(String)
  InvalidProperty(String)
  PropertyUnconfirmed(String)
  UnsupportedProperty(String)
  WriteUnconfirmed(String)
  ReadOnlyProperty(String)
  UniqueKeyUnconfirmed(String)
} derive(Eq, Debug)

///|
/// Only the properties response constructs these facts. Labels are never
/// substituted for internal option values. Definition editability and value
/// editability are different provider facts.
pub struct PropertyMetadata {
  name : String
  native_type : String
  field_type : String
  priv options : Array[String]
  unique : Bool
  writable : Bool?
} derive(Eq)

///|
/// Pure projection, not an admitted Catalog or a credential. The physical
/// caller must bind the exact response to its authenticated object/account
/// request and recheck that observation through its existing current Owner.
pub struct PropertyCatalog {
  object_type : String
  response_sha256 : String
  priv properties : Array[PropertyMetadata]
}

///|
fn text(object : @decode.ObjectView, name : String) -> String? {
  guard @decode.lookup(object, name) is Some(value) else { return None }
  match @decode.text(value) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
// Missing metadata is unconfirmed, never an affirmative write fact.
fn flag(object : @decode.ObjectView, name : String) -> Result[Bool?, Unit] {
  match @decode.field(object, name) {
    Missing => Ok(None)
    ExplicitNull => Err(())
    Present(value) =>
      match @decode.boolean(value) {
        Ok(value) => Ok(Some(value))
        Err(_) => Err(())
      }
  }
}

///|
fn property(cursor : @decode.Cursor) -> Result[PropertyMetadata, PropertyIssue] {
  guard @decode.open_object(cursor) is Ok(object) &&
    text(object, "name") is Some(name) &&
    !name.is_empty() else {
    return Err(InvalidResponse)
  }
  guard text(object, "type") is Some(native_type) &&
    !native_type.is_empty() &&
    text(object, "fieldType") is Some(field_type) &&
    !field_type.is_empty() &&
    flag(object, "hasUniqueValue") is Ok(unique) &&
    flag(object, "calculated") is Ok(calculated) &&
    flag(object, "archived") is Ok(archived) else {
    return Err(InvalidProperty(name))
  }
  let options : Array[String] = []
  if native_type == "enumeration" {
    guard @decode.lookup(object, "options") is Some(list) &&
      @decode.array_length(list) is Some(count) else {
      return Err(InvalidProperty(name))
    }
    let seen : Map[String, Bool] = Map([])
    for index in 0..<count {
      guard @decode.open_object(@decode.element_at(list, index).unwrap())
        is Ok(option) &&
        text(option, "value") is Some(value) &&
        !seen.contains(value) else {
        return Err(InvalidProperty(name))
      }
      seen[value] = true
      options.push(value)
    }
  }
  let read_only = match @decode.field(object, "modificationMetadata") {
    Missing => None
    ExplicitNull => return Err(InvalidProperty(name))
    Present(value) => {
      guard @decode.open_object(value) is Ok(metadata) &&
        flag(metadata, "readOnlyValue") is Ok(read_only) else {
        return Err(InvalidProperty(name))
      }
      read_only
    }
  }
  let writable = if archived == Some(true) ||
    calculated == Some(true) ||
    field_type == "calculation_equation" ||
    field_type == "calculation_rollup" ||
    native_type == "object_coordinates" ||
    native_type == "json" ||
    read_only == Some(true) {
    Some(false)
  } else if calculated == Some(false) && read_only == Some(false) {
    Some(true)
  } else {
    None
  }
  Ok({
    name,
    native_type,
    field_type,
    options,
    unique: unique == Some(true),
    writable,
  })
}

///|
/// The endpoint does not echo the object/account binding. Supplying an object
/// name here is only a projection label, never evidence of that binding.
pub fn project_properties(
  bytes : Bytes,
  object_type : String,
  limits : PropertyLimits,
) -> Result[PropertyCatalog, PropertyIssue] {
  if limits.max_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_properties <= 0 ||
    limits.max_name_units <= 0 {
    return Err(InvalidLimits)
  }
  if object_type.is_empty() || object_type.length() > limits.max_name_units {
    return Err(InvalidResponse)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  let parsed = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
  let root = match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(BudgetExceeded)
  }
  guard @decode.open_object(root) is Ok(object) &&
    @decode.lookup(object, "results") is Some(list) &&
    @decode.array_length(list) is Some(count) else {
    return Err(InvalidResponse)
  }
  if count > limits.max_properties {
    return Err(BudgetExceeded)
  }
  let properties = []
  let seen : Map[String, Bool] = Map([])
  let mut names = 0
  for index in 0..<count {
    let value = match property(@decode.element_at(list, index).unwrap()) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if seen.contains(value.name) {
      return Err(DuplicateProperty(value.name))
    }
    if value.name.length() > limits.max_name_units - names {
      return Err(BudgetExceeded)
    }
    names += value.name.length()
    seen[value.name] = true
    properties.push(value)
  }
  Ok({ object_type, response_sha256: @sha.hex(bytes), properties, })
}

///|
pub fn property_named(
  catalog : PropertyCatalog,
  name : String,
) -> PropertyMetadata? {
  for property in catalog.properties {
    if property.name == name {
      return Some(property)
    }
  }
  None
}

///|
/// Copies only: callers cannot append a foreign property or option into the
/// original observation through a mutable Array alias.
pub fn property_names(catalog : PropertyCatalog) -> Array[String] {
  catalog.properties.map(property => property.name)
}

///|
pub fn property_option_values(property : PropertyMetadata) -> Array[String] {
  property.options.copy()
}

///|
/// Common owns the actual carrier contract, including fixed decimal precision.
/// No provider number is converted through binary64 to choose its carrier.
pub fn property_contract(
  catalog : PropertyCatalog,
  name : String,
) -> Result[@contract.Contract, PropertyIssue] {
  guard property_named(catalog, name) is Some(property) else {
    return Err(PropertyUnconfirmed(name))
  }
  let primitive = match property.native_type {
    "string" | "phone_number" | "object_coordinates" => @contract.StringType
    "number" =>
      return match @contract.decimal_contract(38, 10, nullable=true) {
        Some(value) => Ok(value)
        None => Err(UnsupportedProperty(name))
      }
    "bool" => @contract.BooleanType
    "date" => @contract.DateType
    "datetime" => @contract.TimestampType
    "enumeration" => {
      if property.field_type == "checkbox" {
        return match
          @contract.array_contract(
            @contract.primitive(@contract.StringType, nullable=false),
            nullable=true,
          ) {
          Some(value) => Ok(value)
          None => Err(UnsupportedProperty(name))
        }
      }
      match property.field_type {
        "select" | "radio" | "booleancheckbox" | "calculation_equation" | "calculation_rollup" =>
          @contract.StringType
        _ => return Err(UnsupportedProperty(name))
      }
    }
    _ => return Err(UnsupportedProperty(name))
  }
  Ok(@contract.primitive(primitive, nullable=true))
}

///|
/// Metadata eligibility only. An executable Mapping, current Account and
/// original credential grant still belong to their existing independent Owners.
pub fn require_property_write(
  catalog : PropertyCatalog,
  name : String,
) -> Result[Unit, PropertyIssue] {
  guard property_named(catalog, name) is Some(property) else {
    return Err(PropertyUnconfirmed(name))
  }
  match property.writable {
    Some(false) => Err(ReadOnlyProperty(name))
    None => Err(WriteUnconfirmed(name))
    Some(true) => property_contract(catalog, name).map(_ => ())
  }
}

///|
/// Provider-enforced keys and positively observed custom unique properties.
/// Company domain lookup/import deduplication is not enforced API uniqueness.
/// Object/account binding still has to be authenticated by the caller; the
/// properties body alone cannot prove which object's schema was returned.
pub fn require_unique_property(
  catalog : PropertyCatalog,
  name : String,
) -> Result[Unit, PropertyIssue] {
  guard property_named(catalog, name) is Some(property) else {
    return Err(PropertyUnconfirmed(name))
  }
  let built_in = name == "hs_object_id" ||
    (catalog.object_type == "contacts" && name == "email")
  if property.unique || built_in {
    Ok(())
  } else {
    Err(UniqueKeyUnconfirmed(name))
  }
}
