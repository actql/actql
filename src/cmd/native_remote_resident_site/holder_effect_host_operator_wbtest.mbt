///|
/// Native caller compile-only counterexamples. These authored ports do not
/// execute filesystem/TLS or install production Account permission.
test "Host operator selection distinguishes missing empty repeated and explicit input" {
  assert_true(holder_effect_host_root(None) is Ok(None))
  assert_true(holder_effect_host_root(Some([])) is Err(_))
  assert_true(holder_effect_host_root(Some([""])) is Err(_))
  assert_true(holder_effect_host_root(Some(["one", "two"])) is Err(_))
  assert_true(holder_effect_host_root(Some(["x".repeat(4097)])) is Err(_))
  assert_true(
    holder_effect_host_root(Some(["operator-root"]))
    is Ok(Some("operator-root")),
  )
}

///|
test "Host operator current input refuses deleted replaced and foreign subject selector" {
  let snapshot = [
    ("host-principal.txt", "original"),
    ("host-read-resource.txt", "evidence"),
  ]
  assert_true(
    holder_effect_host_snapshot_current(snapshot, name => {
      if name == "host-principal.txt" {
        Some("original")
      } else {
        Some("evidence")
      }
    }),
  )
  for replacement in [None, Some("foreign")] {
    assert_false(
      holder_effect_host_snapshot_current(snapshot, _ => replacement),
    )
  }
  assert_false(
    holder_effect_host_snapshot_current(snapshot, name => {
      if name == "host-principal.txt" {
        Some("original")
      } else {
        Some("publication")
      }
    }),
  )
}
