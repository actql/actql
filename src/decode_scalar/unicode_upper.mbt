///|
/// Borrow the pinned full mapping, or retain the original scalar for None.
/// The fixed Unicode table bounds this search independently of input length.
pub fn unicode_upper_mapping(scalar : Char) -> String? {
  let code = scalar.to_int()
  let mut start = 0
  let mut end = unicode_upper_keys.length()
  while start < end {
    let middle = start + (end - start) / 2
    let candidate = unicode_upper_keys[middle]
    if candidate == code {
      return Some(unicode_upper_values[middle])
    } else if candidate < code {
      start = middle + 1
    } else {
      end = middle
    }
  }
  None
}
