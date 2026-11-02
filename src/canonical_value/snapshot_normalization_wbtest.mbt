///|
fn snapshot_normalization_depth(cp : Int) -> Int {
  match lookup_int(canonical_decomposition_keys, cp) {
    None => 1
    Some(index) => {
      let mut depth = 0
      for
        i in canonical_decomposition_offsets[index]..<canonical_decomposition_offsets[index +
        1] {
        let next = snapshot_normalization_depth(canonical_decomposition_data[i])
        if next > depth {
          depth = next
        }
      }
      depth + 1
    }
  }
}

///|
test "snapshot normalization pinned recursive expansion proof" {
  let mut largest = 0
  let mut deepest = 0
  let mut largest_utf16_ratio = 0L
  for cp in canonical_decomposition_keys {
    let values : Array[Int] = []
    append_canonical_decomposition(cp, values)
    assert_true(values.length() <= 4)
    let mut units = 0L
    for value in values {
      units += if value <= 0xFFFF { 1L } else { 2L }
    }
    let input_units = if cp <= 0xFFFF { 1L } else { 2L }
    let ratio = (units + input_units - 1L) / input_units
    largest_utf16_ratio = Int64::max(largest_utf16_ratio, ratio)
    assert_true(units <= nfc_lf_retained_output_units(input_units).unwrap())
    let depth = snapshot_normalization_depth(cp)
    assert_true(depth <= 4)
    if values.length() > largest {
      largest = values.length()
    }
    if depth > deepest {
      deepest = depth
    }
  }
  assert_eq(largest, 4)
  assert_eq(deepest, 4)
  assert_eq(largest_utf16_ratio, 4L)
  assert_eq(canonical_decomposition_max_scalar_expansion, 4L)
  assert_eq(canonical_decomposition_max_utf16_expansion, 4L)
  for cp in [0xAC00, 0xAC01, 0xD7A3] {
    let values : Array[Int] = []
    append_canonical_decomposition(cp, values)
    assert_true(values.length() <= 3)
  }
}
