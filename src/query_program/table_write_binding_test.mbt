///|
fn table_write_fixture(action : TableWriteAction) -> TableWriteBinding {
  let cid = "sha256:" + "a".repeat(64)
  {
    name: [
      { value: "analytics", quoted: false, },
      { value: "report", quoted: false, },
    ],
    target_ref: "connector://local/report",
    mapping_ref: "mapping:local.report.v1",
    mapping_cid: cid,
    capability_cid: "sha256:" + "b".repeat(64),
    installation_binding_cid: "sha256:" + "c".repeat(64),
    action,
  }
}

///|
test "Table write binding resolves a published name without a read alias" {
  let binding = table_write_fixture(Create)
  let selected = resolve_table_write_binding(
    [binding],
    [
      { value: "ANALYTICS", quoted: false, },
      { value: "REPORT", quoted: false, },
    ],
    false,
    20,
  ).unwrap()
  assert_eq(selected.target_ref, "connector://local/report")
  assert_eq(selected.mapping_ref, "mapping:local.report.v1")
  assert_eq(selected.capability_cid, binding.capability_cid)
  assert_true(selected.action is Create)
  assert_true(
    resolve_table_write_binding([], binding.name, false, 20)
    is Err(UnknownTable),
  )
}

///|
test "Table write binding rejects ambiguity and action mismatch" {
  let create = table_write_fixture(Create)
  let uuid = "12345678-1234-1234-1234-123456789abc"
  let generation = "sha256:" + "d".repeat(64)
  let replace = table_write_fixture(Replace(uuid, generation))
  assert_true(
    resolve_table_write_binding([create, replace], create.name, true, 20)
    is Err(AmbiguousTable),
  )
  assert_true(
    resolve_table_write_binding([replace], create.name, false, 20)
    is Err(ActionMismatch),
  )
  let selected = resolve_table_write_binding([replace], create.name, true, 20).unwrap()
  assert_eq(selected.action, Replace(uuid, generation))
  // OR REPLACE retains the published create action; no head lookup or fallback.
  assert_true(
    resolve_table_write_binding([create], create.name, true, 20).unwrap().action
    is Create,
  )
}

///|
test "Table write binding keeps quoted name rules and validates all metadata" {
  let binding = table_write_fixture(Create)
  assert_true(
    resolve_table_write_binding(
      [binding],
      [
        { value: "analytics", quoted: false, },
        { value: "REPORT", quoted: true, },
      ],
      false,
      20,
    )
    is Err(UnknownTable),
  )
  let bad = {
    ..binding,
    action: Replace("not-a-uuid", "sha256:" + "d".repeat(64)),
  }
  assert_true(
    resolve_table_write_binding([binding, bad], binding.name, false, 20)
    is Err(InvalidBinding),
  )
  assert_true(
    resolve_table_write_binding([binding], binding.name, false, 2)
    is Err(WorkLimit),
  )
  let foreign = { ..binding, target_ref: "source:local.report", }
  assert_true(
    resolve_table_write_binding([foreign], binding.name, false, 20)
    is Err(InvalidBinding),
  )
}
