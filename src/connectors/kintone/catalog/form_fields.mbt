///|
/// Bounds for one complete original Form Fields response. These describe a
/// caller's finite physical projection, not a language or permission limit.
pub(all) struct FormFieldLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_fields : Int
  max_name_units : Int
}

///|
pub(all) enum FormFieldIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  InvalidField(String)
  FieldUnavailable
  UniqueKeyUnconfirmed
} derive(Eq, Debug)

///|
/// Only the original response constructs this metadata. A table path and its
/// field code remain distinct from labels, option display order and row IDs.
pub struct FormFieldMetadata {
  code : String
  native_type : String
  required : Bool?
  unique : Bool?
  display_scale : String?
  calculation_format : String?
  priv path : Array[String]
  priv options : Array[String]?
  priv write_expression : String?
  priv write_lookup_targets : Array[String]?
} derive(Eq)

///|
/// A pure observation, not an admitted RowDeclaration, acquisition or grant.
/// The endpoint does not echo the App ID: app_id is only the caller's label.
/// Its actual authenticated request/app/credential binding remains with the
/// existing physical Site and current owner.
pub struct FormFieldCatalog {
  app_id : String
  revision : String
  response_sha256 : String
  priv fields : Array[FormFieldMetadata]
}

///|
fn form_text(object : @decode.ObjectView, key : String) -> String? {
  guard @decode.lookup(object, key) is Some(value) else { return None }
  match @decode.text(value) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
fn form_flag(object : @decode.ObjectView, key : String) -> Result[Bool?, Unit] {
  match @decode.field(object, key) {
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
fn form_optional_text(
  object : @decode.ObjectView,
  key : String,
) -> Result[String?, Unit] {
  match @decode.field(object, key) {
    Missing => Ok(None)
    ExplicitNull => Err(())
    Present(value) =>
      match @decode.text(value) {
        Ok(value) => Ok(Some(value))
        Err(_) => Err(())
      }
  }
}

///|
fn form_digits(text : String) -> Bool {
  if text.is_empty() {
    return false
  }
  for character in text {
    if character < '0' || character > '9' {
      return false
    }
  }
  true
}

///|
// Missing lookup means this field has no mapping. A hidden or malformed
// lookup cannot prove the absence of destinations elsewhere in the Form.
// Retain this write evidence without changing the existing readable carriers.
fn form_write_lookup_targets(object : @decode.ObjectView) -> Array[String]? {
  match @decode.field(object, "lookup") {
    Missing => Some([])
    ExplicitNull => None
    Present(value) => {
      guard @decode.open_object(value) is Ok(lookup) &&
        @decode.lookup(lookup, "fieldMappings") is Some(mappings) else {
        return None
      }
      // The provider also documents an empty string for no mappings.
      if @decode.text(mappings) == Ok("") {
        return Some([])
      }
      guard @decode.array_length(mappings) is Some(count) else { return None }
      let targets = []
      for index in 0..<count {
        guard @decode.element_at(mappings, index) is Some(mapping) &&
          @decode.open_object(mapping) is Ok(entry) &&
          form_text(entry, "field") is Some(target) &&
          !target.is_empty() &&
          form_text(entry, "relatedField") is Some(source) &&
          !source.is_empty() else {
          return None
        }
        targets.push(target)
      }
      Some(targets)
    }
  }
}

///|
fn form_field_metadata(
  value : @decode.Cursor,
  key : String,
  path : Array[String],
) -> Result[FormFieldMetadata, FormFieldIssue] {
  guard @decode.open_object(value) is Ok(object) &&
    form_text(object, "code") == Some(key) &&
    form_text(object, "type") is Some(native_type) &&
    !native_type.is_empty() &&
    form_flag(object, "required") is Ok(required) &&
    form_flag(object, "unique") is Ok(unique) &&
    form_optional_text(object, "displayScale") is Ok(display_scale) &&
    form_optional_text(object, "format") is Ok(calculation_format) else {
    return Err(InvalidField(key))
  }
  // An omitted option map is unconfirmed, not an empty positive enumeration.
  let options = match @decode.field(object, "options") {
    Missing => None
    ExplicitNull => return Err(InvalidField(key))
    Present(value) => {
      guard @decode.open_object(value) is Ok(option_map) &&
        @decode.object_field_names(value) is Ok(names) else {
        return Err(InvalidField(key))
      }
      for name in names {
        guard @decode.lookup(option_map, name) is Some(option) &&
          @decode.open_object(option) is Ok(option_object) &&
          form_text(option_object, "label") == Some(name) else {
          return Err(InvalidField(key))
        }
      }
      Some(names)
    }
  }
  Ok({
    code: key,
    native_type,
    required,
    unique,
    display_scale,
    calculation_format,
    path,
    options,
    write_expression: form_text(object, "expression"),
    write_lookup_targets: form_write_lookup_targets(object),
  })
}

///|
/// Project only a complete original live-app Form Fields response. Unknown
/// native types remain metadata; this does not advertise a readable carrier
/// or a writable field. No number goes through binary64 and no display scale
/// is promoted to precision. Only the physical caller can attest which live
/// or pre-live endpoint supplied these bytes; this projection cannot do so.
pub fn project_form_fields(
  bytes : Bytes,
  app_id : String,
  limits : FormFieldLimits,
) -> Result[FormFieldCatalog, FormFieldIssue] {
  if limits.max_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_fields <= 0 ||
    limits.max_name_units <= 0 {
    return Err(InvalidLimits)
  }
  if !form_digits(app_id) || app_id.length() > limits.max_name_units {
    return Err(InvalidResponse)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  let parsed = match
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(error) =>
      return Err(
        match error.issue {
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
    Err(error) =>
      return Err(
        match error.kind {
          BudgetExceeded => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
  guard @decode.open_object(root) is Ok(object) &&
    form_text(object, "revision") is Some(revision) &&
    form_digits(revision) &&
    @decode.lookup(object, "properties") is Some(properties) &&
    @decode.open_object(properties) is Ok(_) else {
    return Err(InvalidResponse)
  }
  let fields = []
  let mut name_units = 0
  let pending : Array[(@decode.Cursor, Array[String])] = [(properties, [])]
  while !pending.is_empty() {
    let (properties, prefix) = pending.pop().unwrap()
    guard @decode.open_object(properties) is Ok(_) &&
      @decode.object_length(properties) is Some(count) else {
      return Err(InvalidResponse)
    }
    if count > limits.max_fields - fields.length() {
      return Err(BudgetExceeded)
    }
    for index in 0..<count {
      let (key, value) = @decode.field_at(properties, index).unwrap()
      if key.is_empty() {
        return Err(InvalidResponse)
      }
      if key.length() > limits.max_name_units - name_units {
        return Err(BudgetExceeded)
      }
      name_units += key.length()
      let path = prefix.copy()
      path.push(key)
      let field = match form_field_metadata(value, key, path) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      if field.native_type == "SUBTABLE" {
        guard @decode.open_object(value) is Ok(table) &&
          @decode.lookup(table, "fields") is Some(children) &&
          @decode.open_object(children) is Ok(_) else {
          return Err(InvalidField(key))
        }
        pending.push((children, path))
      }
      fields.push(field)
    }
  }
  Ok({ app_id, revision, response_sha256: @sha.hex(bytes), fields, })
}

///|
/// Read-only original inventory size. This allocates no path/name snapshots
/// and grants no lookup, write or capacity authority.
pub fn form_field_count(catalog : FormFieldCatalog) -> Int {
  catalog.fields.length()
}

///|
pub fn form_field_paths(catalog : FormFieldCatalog) -> Array[Array[String]] {
  catalog.fields.map(field => field.path.copy())
}

///|
pub fn form_field_named(
  catalog : FormFieldCatalog,
  path : Array[String],
) -> FormFieldMetadata? {
  for field in catalog.fields {
    if field.path == path {
      return Some(field)
    }
  }
  None
}

///|
pub fn form_field_options(field : FormFieldMetadata) -> Array[String]? {
  field.options.map(values => values.copy())
}

///|
/// Provider-enforced update-key eligibility, not a write or lookup grant.
/// A configured name, a label or duplicate-looking observed values cannot
/// replace the original positive metadata for a top-level supported key.
pub fn require_form_unique_key(
  catalog : FormFieldCatalog,
  code : String,
) -> Result[FormFieldMetadata, FormFieldIssue] {
  guard form_field_named(catalog, [code]) is Some(field) else {
    return Err(FieldUnavailable)
  }
  if field.unique != Some(true) ||
    (field.native_type != "SINGLE_LINE_TEXT" && field.native_type != "NUMBER") {
    return Err(UniqueKeyUnconfirmed)
  }
  Ok(field)
}

///|
/// Pure correspondence only. Authentication, original nominal use/current
/// authorization, App/Site generation and physical capacity are not inferred
/// from these equal metadata values or a matching settings revision.
pub fn form_field_definition_matches(
  original : FormFieldCatalog,
  observed : FormFieldCatalog,
  path : Array[String],
) -> Bool {
  if original.app_id != observed.app_id ||
    original.revision != observed.revision {
    return false
  }
  match (form_field_named(original, path), form_field_named(observed, path)) {
    (Some(left), Some(right)) => left == right
    _ => false
  }
}
