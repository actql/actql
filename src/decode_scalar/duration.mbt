///|
/// Read a positive safe-integer duration in milliseconds.
/// Accept ASCII digits and ms/s/m/h/d (case-insensitive), including leading zeros.
/// Reject whitespace, signs, fractions, zero and overflow without rounding.
pub fn read_duration_ms(text : String) -> Int64? {
  let mut split = 0
  while split < text.length() && text[split] >= '0' && text[split] <= '9' {
    split += 1
  }
  if split == 0 {
    return None
  }
  let suffix = text.length() - split
  let lower = fn(index) {
    let c = text[index].to_int()
    if c >= 65 && c <= 90 {
      c + 32
    } else {
      c
    }
  }
  let factor : Int64 = if suffix == 2 &&
    lower(split) == 109 &&
    lower(split + 1) == 115 {
    1L
  } else if suffix == 1 {
    match lower(split) {
      115 => 1000L
      109 => 60000L
      104 => 3600000L
      100 => 86400000L
      _ => return None
    }
  } else {
    return None
  }
  let cap = 9007199254740991L / factor
  let mut amount = 0L
  for index = 0; index < split; index = index + 1 {
    let digit = (text[index].to_int() - 48).to_int64()
    if amount > (cap - digit) / 10L {
      return None
    }
    amount = amount * 10L + digit
    if amount > cap {
      return None
    }
  }
  if amount == 0L {
    None
  } else {
    Some(amount * factor)
  }
}
