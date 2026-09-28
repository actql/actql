///|
/// Bounded parsing limits for one authenticated Salesforce describe response.
/// This projection is metadata, not execution authority or a complete Catalog.
pub(all) struct DescribeLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_fields : Int
  max_name_units : Int
}

///|
pub(all) enum DescribeIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  ResourceMismatch
  DuplicateField(String)
  InvalidField(String)
} derive(Eq, Debug)

///|
pub struct FieldMetadata {
  name : String
  native_type : String
  nullable : Bool
  nullability_confirmed : Bool
  defaulted_on_create : Bool
  default_on_create_confirmed : Bool
  createable : Bool
  updateable : Bool
  filterable : Bool
  sortable : Bool
  external_id : Bool
  unique : Bool
  case_sensitive : Bool?
  reference_to : Array[String]
  // The described total digits and fractional digits of a `double` field;
  // none for any other type.
  precision : Int?
  scale : Int?
}

///|
pub struct ResourceMetadata {
  name : String
  queryable : Bool
  createable : Bool
  updateable : Bool
  fields : Array[FieldMetadata]
  response_sha256 : String
}

///|
fn required_text(object : @decode.ObjectView, name : String) -> String? {
  guard @decode.lookup(object, name) is Some(value) else { return None }
  match @decode.text(value) {
    Ok(text) => Some(text)
    Err(_) => None
  }
}

///|
fn optional_boolean(
  object : @decode.ObjectView,
  name : String,
  missing : Bool,
) -> Bool? {
  guard @decode.lookup(object, name) is Some(value) else {
    return Some(missing)
  }
  match @decode.boolean(value) {
    Ok(flag) => Some(flag)
    Err(_) => None
  }
}

///|
fn valid_api_name(name : String) -> Bool {
  if name.is_empty() || name.length() > 255 {
    return false
  }
  let mut first = true
  for character in name.iter() {
    if first {
      if !((character >= 'a' && character <= 'z') ||
        (character >= 'A' && character <= 'Z') ||
        character == '_') {
        return false
      }
      first = false
      continue
    }
    if !((character >= 'a' && character <= 'z') ||
      (character >= 'A' && character <= 'Z') ||
      (character >= '0' && character <= '9') ||
      character == '_') {
      return false
    }
  }
  true
}

///|
fn references(
  object : @decode.ObjectView,
  limits : DescribeLimits,
) -> Array[String]? {
  guard @decode.lookup(object, "referenceTo") is Some(list) else {
    return Some([])
  }
  guard @decode.array_length(list) is Some(count) && count <= limits.max_fields else {
    return None
  }
  let result = []
  for index in 0..<count {
    guard @decode.text(@decode.element_at(list, index).unwrap()) is Ok(name) &&
      valid_api_name(name) &&
      !result.contains(name) else {
      return None
    }
    result.push(name)
  }
  Some(result)
}

///|
/// A described digit count: a non-negative integer up to 1000.
fn digit_count(object : @decode.ObjectView, name : String) -> Int?? {
  guard @decode.lookup(object, name) is Some(value) else { return Some(None) }
  match @decode.safe_integer(value) {
    Ok(count) if count >= 0L && count <= 1000L => Some(Some(count.to_int()))
    _ => None
  }
}

///|
fn project_field(
  cursor : @decode.Cursor,
  limits : DescribeLimits,
) -> Result[FieldMetadata, DescribeIssue] {
  guard @decode.open_object(cursor) is Ok(object) else {
    return Err(InvalidResponse)
  }
  guard required_text(object, "name") is Some(name) && valid_api_name(name) else {
    return Err(InvalidResponse)
  }
  guard required_text(object, "type") is Some(native_type) &&
    !native_type.is_empty() &&
    native_type.length() <= 128 else {
    return Err(InvalidField(name))
  }
  guard optional_boolean(object, "nillable", true) is Some(nullable) &&
    optional_boolean(object, "defaultedOnCreate", false)
    is Some(defaulted_on_create) &&
    optional_boolean(object, "createable", false) is Some(createable) &&
    optional_boolean(object, "updateable", false) is Some(updateable) &&
    optional_boolean(object, "filterable", false) is Some(filterable) &&
    optional_boolean(object, "sortable", false) is Some(sortable) &&
    optional_boolean(object, "externalId", false) is Some(external_id) &&
    optional_boolean(object, "unique", false) is Some(unique) &&
    references(object, limits) is Some(reference_to) else {
    return Err(InvalidField(name))
  }
  let (precision, scale) = if native_type == "double" {
    guard digit_count(object, "precision") is Some(precision) &&
      digit_count(object, "scale") is Some(scale) else {
      return Err(InvalidField(name))
    }
    (precision, scale)
  } else {
    (None, None)
  }
  Ok({
    name,
    native_type,
    nullable,
    nullability_confirmed: @decode.lookup(object, "nillable") is Some(_),
    defaulted_on_create,
    default_on_create_confirmed: @decode.lookup(object, "defaultedOnCreate")
    is Some(_),
    createable,
    updateable,
    filterable,
    sortable,
    external_id,
    unique,
    case_sensitive: match @decode.lookup(object, "caseSensitive") {
      Some(value) =>
        match @decode.boolean(value) {
          Ok(flag) => Some(flag)
          Err(_) => return Err(InvalidField(name))
        }
      None => None
    },
    reference_to,
    precision,
    scale,
  })
}

///|
/// Projects only facts returned by the exact describe call. Missing permission
/// flags are conservative; a missing field is not evidence of nonexistence.
pub fn project_describe(
  bytes : Bytes,
  expected_name : String,
  limits : DescribeLimits,
) -> Result[ResourceMetadata, DescribeIssue] {
  if limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_fields < 0 ||
    limits.max_name_units < 0 {
    return Err(InvalidLimits)
  }
  if !valid_api_name(expected_name) {
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
  guard @decode.open_object(root) is Ok(object) else {
    return Err(InvalidResponse)
  }
  guard required_text(object, "name") is Some(name) else {
    return Err(InvalidResponse)
  }
  if name != expected_name {
    return Err(ResourceMismatch)
  }
  guard optional_boolean(object, "queryable", false) is Some(queryable) &&
    optional_boolean(object, "createable", false) is Some(createable) &&
    optional_boolean(object, "updateable", false) is Some(updateable) else {
    return Err(InvalidResponse)
  }
  guard @decode.lookup(object, "fields") is Some(list) &&
    @decode.array_length(list) is Some(count) else {
    return Err(InvalidResponse)
  }
  if count > limits.max_fields {
    return Err(BudgetExceeded)
  }
  let fields = []
  let seen : Map[String, Bool] = Map([])
  let mut name_units = 0
  for index in 0..<count {
    let field = match
      project_field(@decode.element_at(list, index).unwrap(), limits) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if seen.contains(field.name) {
      return Err(DuplicateField(field.name))
    }
    if field.name.length() > limits.max_name_units - name_units {
      return Err(BudgetExceeded)
    }
    name_units += field.name.length()
    seen[field.name] = true
    fields.push(field)
  }
  Ok({
    name,
    queryable,
    createable,
    updateable,
    fields,
    response_sha256: @sha.hex(bytes),
  })
}

///|
/// A field must be observed in this describe response before use. The caller
/// still has to recheck current authority and the exact connection revision.
pub fn described_field(
  resource : ResourceMetadata,
  name : String,
) -> FieldMetadata? {
  for field in resource.fields {
    if field.name == name {
      return Some(field)
    }
  }
  None
}
