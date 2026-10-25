///|
/// These authored ports exercise the read fence only, not physical Original
/// custody, Catalog acquisition, cryptography or public approval.
test "original policy refuses a read without current custody or evidence authority" {
  let reads = [0]
  assert_true(
    holder_effect_policy_read_current(() => false, () => {
      reads[0] += 1
      Some(1)
    })
    is None,
  )
  assert_eq(reads[0], 0)
}

///|
test "original policy denies adoption after authority is lost during its read" {
  let current = [true]
  let reads = [0]
  assert_true(
    holder_effect_policy_read_current(() => current[0], () => {
      reads[0] += 1
      current[0] = false
      Some(1)
    })
    is None,
  )
  assert_eq(reads[0], 1)
}

///|
test "original policy preserves the selected value and never retries an unavailable read" {
  let reads = [0]
  assert_eq(
    holder_effect_policy_read_current(() => true, () => {
      reads[0] += 1
      Some("original")
    }),
    Some("original"),
  )
  let unavailable : String? = holder_effect_policy_read_current(() => true, () => {
    reads[0] += 1
    None
  })
  assert_true(unavailable is None)
  assert_eq(reads[0], 2)
}

///|
/// A read may retain its own response/unknown responsibility even when current
/// authority is lost. Deny policy adoption, not the read Owner's cleanup.
fn[T] holder_effect_policy_read_current(
  current : () -> Bool,
  read : () -> T?,
) -> T? {
  if !current() {
    return None
  }
  let selected = read()
  if !current() {
    return None
  }
  selected
}
