///|
// Actual existing Manifest/Run originals plus independent state fields. The
// incoming observation never supplies the expected declared Result inventory.
test "original succeeded state reader binds canonical original Run and Manifest without control" {
  let fixture = commit_read_fixture()
  let run = fixture.originals[0]
  let manifest = fixture.originals[2]
  let names = manifest_result_names(manifest).unwrap()
  let wire = issue_succeeded_run_state_wire(
    run_definition_run_id(run).unwrap(),
    "2026-09-17T00:00:03.000Z",
    names,
    names,
    names.map(_ => "unknown"),
    names.map(_ => "verification_pending"),
    names.map(_ => "2026-09-17T00:00:03.000Z"),
    65536,
    4096,
    32,
  ).unwrap()
  assert_eq(
    validate_original_succeeded_run_state(run, manifest, wire, 65536, 4096, 32),
    Ok(()),
  )
  assert_true(!wire.contains("control"))
  for
    invalid in [
      " " + wire,
      wire.replace(old="\"succeeded\"", new="\"running\""),
      wire.replace(old="verification_pending", new="confirmed_present"),
      wire.replace(
        old="\"result_available\":false",
        new="\"result_available\":true",
      ),
      wire.replace(
        old="\"run_id\":",
        new="\"run_id\":\"foreign\",\"original_run_id\":",
      ),
      wire.replace(old="\"version\":", new="\"version\":null,\"version\":"),
    ] {
    assert_true(
      validate_original_succeeded_run_state(
        run, manifest, invalid, 65536, 4096, 32,
      )
      is Err(_),
    )
  }
  assert_true(
    validate_original_succeeded_run_state(run, manifest, wire, 1, 4096, 32)
    is Err(_),
  )
}

///|
test "original succeeded state reader refuses foreign declared names and original Run mismatch" {
  let fixture = commit_read_fixture()
  let run = fixture.originals[0]
  let manifest = fixture.originals[2]
  let wire = issue_succeeded_run_state_wire(
    run_definition_run_id(run).unwrap(),
    "2026-09-17T00:00:03.000Z",
    ["foreign"],
    ["foreign"],
    ["unknown"],
    ["verification_pending"],
    ["2026-09-17T00:00:03.000Z"],
    65536,
    4096,
    32,
  ).unwrap()
  assert_true(
    validate_original_succeeded_run_state(run, manifest, wire, 65536, 4096, 32)
    is Err(_),
  )
  let other = fixture.originals[1]
  assert_true(
    validate_original_succeeded_run_state(
      other, manifest, wire, 65536, 4096, 32,
    )
    is Err(_),
  )
}
