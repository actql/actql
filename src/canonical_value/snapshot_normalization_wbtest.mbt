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
  for cp in canonical_decomposition_keys {
    let values : Array[Int] = []
    append_canonical_decomposition(cp, values)
    assert_true(values.length() <= 4)
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
  for cp in [0xAC00, 0xAC01, 0xD7A3] {
    let values : Array[Int] = []
    append_canonical_decomposition(cp, values)
    assert_true(values.length() <= 3)
  }
}

