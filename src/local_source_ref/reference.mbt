///|
pub(all) enum Issue {
  InvalidLimit
  LimitExceeded
  InvalidReference
  NonCanonicalName
} derive(Eq, Debug)

///|
struct Reference {
  stage : String
  input : String
  text : String
}

///|
fn canonical_name(name : String) -> Bool {
  if name == "" {
    return false
  }
  match @canonical.normalize_nfc_lf(name) {
    Ok(value) => value == name
    Err(_) => false
  }
}

///|
fn token(name : String) -> String {
  let out = StringBuilder()
  for ch in name.iter() {
    match ch {
      '~' => out.write_string("~0")
      '/' => out.write_string("~1")
      _ => out.write_char(ch)
    }
  }
  out.to_string()
}

///|
pub fn create(
  stage : String,
  input : String,
  max_bytes~ : Int,
) -> Result[Reference, Issue] {
  if max_bytes < 0 {
    return Err(InvalidLimit)
  }
  let mut remaining = max_bytes
  for name in [stage, input] {
    match @scalar.admit_utf8_length(name, remaining) {
      Ok(n) => remaining -= n
      Err(@scalar.MalformedUtf16(_)) => return Err(NonCanonicalName)
      Err(_) => return Err(LimitExceeded)
    }
    if !canonical_name(name) {
      return Err(NonCanonicalName)
    }
  }
  let text = "source:local/" + token(stage) + "/" + token(input)
  if @scalar.admit_utf8_length(text, max_bytes) is Err(_) {
    return Err(LimitExceeded)
  }
  Ok({ stage, input, text, })
}

///|
fn untoken(text : String) -> String? {
  let out = StringBuilder()
  let mut escaped = false
  for ch in text.iter() {
    if escaped {
      match ch {
        '0' => out.write_char('~')
        '1' => out.write_char('/')
        _ => return None
      }
      escaped = false
    } else if ch == '~' {
      escaped = true
    } else {
      out.write_char(ch)
    }
  }
  if escaped {
    None
  } else {
    Some(out.to_string())
  }
}

///|
pub fn read(text : String, max_bytes~ : Int) -> Result[Reference, Issue] {
  if max_bytes < 0 {
    return Err(InvalidLimit)
  }
  match @scalar.admit_utf8_length(text, max_bytes) {
    Ok(_) => ()
    Err(@scalar.MalformedUtf16(_)) => return Err(NonCanonicalName)
    Err(_) => return Err(LimitExceeded)
  }
  let parts = text.split("/").to_array()
  if parts.length() != 3 || parts[0] != "source:local" {
    return Err(InvalidReference)
  }
  let stage = match untoken(parts[1].to_owned()) {
    Some(v) => v
    None => return Err(InvalidReference)
  }
  let input = match untoken(parts[2].to_owned()) {
    Some(v) => v
    None => return Err(InvalidReference)
  }
  match create(stage, input, max_bytes~) {
    Ok(value) =>
      if value.text == text {
        Ok(value)
      } else {
        Err(InvalidReference)
      }
    Err(e) => Err(e)
  }
}

///|
pub fn stage_name(v : Reference) -> String {
  v.stage
}

///|
pub fn input_name(v : Reference) -> String {
  v.input
}

///|
pub fn stringify(v : Reference) -> String {
  v.text
}
