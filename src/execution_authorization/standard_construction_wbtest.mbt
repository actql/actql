///|
test "prepared standard Account uses exact original builder and refuses before materialization" {
  let subjects = standard_profile_subjects()
  let calls = Ref(0)
  assert_true(
    local_standard_account_configuration_prepared(subjects, _ => {
      calls.val += 1
      false
    })
    is None,
  )
  assert_eq(calls.val, 1)
  assert_eq(
    local_standard_account_configuration_prepared(subjects, _ => true).unwrap(),
    local_standard_account_configuration(subjects),
  )
}

///|
test "prepared standard materializer supports original generated Account beyond one million bytes" {
  let subjects = {
    ..standard_profile_subjects(),
    configured_connections: ["c".repeat(1000001)],
  }
  let wire = local_standard_account_configuration_prepared(subjects, _ => true)
    .unwrap()
    .unwrap()
  assert_true(wire.length() > 1000000)
  assert_eq(wire, local_standard_account_configuration(subjects).unwrap())
}
