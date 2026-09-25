///|
fn valid_limits(limits : WireLimits) -> Bool {
  limits.max_wire_bytes > 0 && limits.max_nodes > 1 && limits.max_depth > 1
}

///|
fn hex_digit(value : String, index : Int) -> Bool {
  let code = value[index].to_int()
  (code >= '0'.to_int() && code <= '9'.to_int()) ||
  (code >= 'a'.to_int() && code <= 'f'.to_int())
}

///|
fn valid_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index in 7..<71 {
    if !hex_digit(value, index) {
      return false
    }
  }
  true
}

///|
fn digit_at(value : String, index : Int) -> Int? {
  let code = value[index].to_int() - '0'.to_int()
  if code >= 0 && code <= 9 {
    Some(code)
  } else {
    None
  }
}

///|
fn number_at(value : String, start : Int, end : Int) -> Int? {
  let mut result = 0
  for index in start..<end {
    match digit_at(value, index) {
      Some(digit) => result = result * 10 + digit
      None => return None
    }
  }
  Some(result)
}

///|
/// Exact `YYYY-MM-DDTHH:MM:SS.mmmZ` UTC form. Equal-length UTC instants in this
/// form order lexicographically, so window checks compare the strings.
fn valid_timestamp(value : String) -> Bool {
  if value.length() != 24 ||
    value[4] != '-' ||
    value[7] != '-' ||
    value[10] != 'T' ||
    value[13] != ':' ||
    value[16] != ':' ||
    value[19] != '.' ||
    value[23] != 'Z' {
    return false
  }
  let parts = [
    number_at(value, 0, 4),
    number_at(value, 5, 7),
    number_at(value, 8, 10),
    number_at(value, 11, 13),
    number_at(value, 14, 16),
    number_at(value, 17, 19),
    number_at(value, 20, 23),
  ]
  let numbers : Array[Int] = []
  for part in parts {
    match part {
      Some(number) => numbers.push(number)
      None => return false
    }
  }
  let year = numbers[0]
  let month = numbers[1]
  let day = numbers[2]
  if month < 1 || month > 12 || day < 1 {
    return false
  }
  let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
  let days = match month {
    2 => if leap { 29 } else { 28 }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
  day <= days && numbers[3] <= 23 && numbers[4] <= 59 && numbers[5] <= 59
}

///|
/// Identity-bearing text must already be canonical so sealing never rewrites
/// caller text silently.
fn canonical_text(value : String) -> Bool {
  if value.is_empty() {
    return false
  }
  match @canonical.normalize_nfc_lf(value) {
    Ok(normalized) => normalized == value
    Err(_) => false
  }
}

///|
fn valid_base64(value : String) -> Bool {
  if value.is_empty() {
    return false
  }
  let mut padding = 0
  for index in 0..<value.length() {
    let code = value[index].to_int()
    if code == '='.to_int() {
      padding += 1
      if padding > 2 {
        return false
      }
    } else if padding > 0 {
      return false
    } else if !((code >= 'A'.to_int() && code <= 'Z'.to_int()) ||
      (code >= 'a'.to_int() && code <= 'z'.to_int()) ||
      (code >= '0'.to_int() && code <= '9'.to_int()) ||
      code == '+'.to_int() ||
      code == '/'.to_int()) {
      return false
    }
  }
  true
}

///|
fn parse_wire(wire : String, limits : WireLimits) -> @json.CanonicalValue? {
  if !valid_limits(limits) {
    return None
  }
  let node = match
    @source.parse_json(wire, {
      max_input_bytes: limits.max_wire_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  Some(
    @json.from_source(
      node,
      limits.max_nodes,
      limits.max_depth,
      limits.max_wire_bytes,
    ),
  ) catch {
    _ => None
  }
}

///|
fn canonical_of(json : Json, limits : WireLimits) -> @json.CanonicalValue? {
  Some(
    @json.from_json(
      json,
      limits.max_nodes,
      limits.max_depth,
      limits.max_wire_bytes,
    ),
  ) catch {
    _ => None
  }
}

///|
fn cid_of(value : @json.CanonicalValue, limits : WireLimits) -> String? {
  Some(
    @json.cid_value(
      value,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ),
  ) catch {
    _ => None
  }
}

///|
fn wire_of(value : @json.CanonicalValue, limits : WireLimits) -> String? {
  Some(
    @json.stringify_value(
      value,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ),
  ) catch {
    _ => None
  }
}

///|
/// Closed-object key check. Returns the first unknown key, then the first
/// missing required key.
priv enum ShapeIssue {
  Unknown(String)
  Missing(String)
  NotObject
}

///|
fn closed_shape(
  value : @json.CanonicalValue,
  required : Array[String],
  optional : Array[String],
) -> ShapeIssue? {
  let fields = match @json.object_fields(value) {
    Some(fields) => fields
    None => return Some(NotObject)
  }
  for field in fields {
    let (key, _) = field
    if !required.contains(key) && !optional.contains(key) {
      return Some(Unknown(key))
    }
  }
  for key in required {
    if @json.object_field(value, key) is None {
      return Some(Missing(key))
    }
  }
  None
}

///|
fn string_field(value : @json.CanonicalValue, key : String) -> String? {
  match @json.object_field(value, key) {
    Some(String(text)) => Some(text)
    _ => None
  }
}

///|
fn string_list_field(
  value : @json.CanonicalValue,
  key : String,
) -> Array[String]? {
  match @json.object_field(value, key) {
    Some(Array(items)) => {
      let result : Array[String] = []
      for item in @json.array_values(items) {
        match item {
          String(text) => result.push(text)
          _ => return None
        }
      }
      Some(result)
    }
    _ => None
  }
}

///|
fn string_array_json(values : Array[String]) -> Json {
  Json::array(values.map(value => Json::string(value)))
}
