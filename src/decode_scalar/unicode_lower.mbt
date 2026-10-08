///|
/// Borrow the pinned default full mapping, retaining the input scalar for None.
/// Final_Sigma is selected by the caller from the original input context.
/// The fixed Unicode table bounds this search independently of input length.
pub fn unicode_lower_mapping(scalar : Char) -> String? {
  let code = scalar.to_int()
  let mut start = 0
  let mut end = unicode_lower_keys.length()
  while start < end {
    let middle = start + (end - start) / 2
    let candidate = unicode_lower_keys[middle]
    if candidate == code {
      return Some(unicode_lower_values[middle])
    } else if candidate < code {
      start = middle + 1
    } else {
      end = middle
    }
  }
  None
}

///|
fn unicode_case_property_contains(
  ranges : FixedArray[(Int, Int)],
  scalar : Char,
) -> Bool {
  let code = scalar.to_int()
  let mut start = 0
  let mut end = ranges.length()
  while start < end {
    let middle = start + (end - start) / 2
    let (first, last) = ranges[middle]
    if code < first {
      end = middle
    } else if code > last {
      start = middle + 1
    } else {
      return true
    }
  }
  false
}

///|
/// Read Unicode 16 Cased, including cased scalars without a lowercase mapping.
pub fn unicode_is_cased(scalar : Char) -> Bool {
  unicode_case_property_contains(unicode_cased_ranges, scalar)
}

///|
/// Read Unicode 16 Case_Ignorable independently of the overlapping Cased set.
/// Final_Sigma skips these scalars even when they are also Cased.
pub fn unicode_is_case_ignorable(scalar : Char) -> Bool {
  unicode_case_property_contains(unicode_case_ignorable_ranges, scalar)
}
