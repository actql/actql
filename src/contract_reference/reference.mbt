///|
fn reference_char(unit : Int) -> Bool {
  (unit >= 0x30 && unit <= 0x39) ||
  (unit >= 0x41 && unit <= 0x5a) ||
  (unit >= 0x61 && unit <= 0x7a) ||
  unit == 0x2e ||
  unit == 0x5f ||
  unit == 0x2f ||
  unit == 0x2d
}

///|
fn reference_alphanumeric(unit : Int) -> Bool {
  (unit >= 0x30 && unit <= 0x39) ||
  (unit >= 0x41 && unit <= 0x5a) ||
  (unit >= 0x61 && unit <= 0x7a)
}

///|
fn valid_reference(reference : String, command : Bool) -> Bool {
  let prefix = if command { "command:" } else { "mapping:" }
  if !reference.has_prefix(prefix) {
    return false
  }
  let start = prefix.length()
  let mut suffix = reference.length()
  while suffix > start &&
        reference[suffix - 1].to_int() >= 0x30 &&
        reference[suffix - 1].to_int() <= 0x39 {
    suffix -= 1
  }
  if suffix == reference.length() ||
    suffix < start + 3 ||
    reference[suffix - 2].to_int() != 0x2e ||
    reference[suffix - 1].to_int() != 0x76 {
    return false
  }
  let name_end = suffix - 2
  if !command && !reference_alphanumeric(reference[start].to_int()) {
    return false
  }
  for index in start..<name_end {
    if !reference_char(reference[index].to_int()) {
      return false
    }
  }
  true
}

///|
pub fn valid_mapping_ref(reference : String) -> Bool {
  valid_reference(reference, false)
}

///|
pub fn valid_command_ref(reference : String) -> Bool {
  valid_reference(reference, true)
}
