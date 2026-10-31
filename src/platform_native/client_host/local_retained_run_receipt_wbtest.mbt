///|
test "fresh and retained receipt exports preserve exact path and state exclusions" {
  let state = "/project/private-state"
  assert_true(
    native_local_receipt_export_path(
      state, "/project/run.json", "/project", "run.json",
    ),
  )
  assert_true(
    native_local_receipt_export_path(
      state, "/project/private-state-other/run.json", "/project/private-state-other",
      "run.json",
    ),
  )
  for
    (path, parent, name) in [
      ("/project/private-state/run.json", "/project/private-state", "run.json"),
      ("/project/private-state", "/project", "private-state"),
      ("/project/run.json", "/different", "run.json"),
      ("/project/run.json", "/project", "foreign.json"),
      ("/project/../run.json", "/project/..", "run.json"),
      ("run.json", "/project", "run.json"),
    ] {
    assert_false(native_local_receipt_export_path(state, path, parent, name))
  }
}
