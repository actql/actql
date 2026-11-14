///|
test "Client numeric admission preserves absent and mismatched profile refusal" {
  let expressions : @context.ExpressionProfiles = {
    text_time: false,
    veca: false,
  }
  let operations : @context.PureOperationProfiles = {
    rela: true,
    sga: false,
    tea: false,
    calendar: false,
    text_rank: false,
  }
  let absent = admit_client_check_environment(
    run_materials_environment_wire, run_materials_environment_cid, expressions, operations,
  ).unwrap()
  assert_eq(
    @checked.checking_environment_profile_selection(absent).numeric_profile_cid,
    None,
  )
  for
    foreign in [
      "sha256:0000000000000000000000000000000000000000000000000000000000000000",
      "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    ] {
    assert_true(
      admit_client_check_environment(
        run_materials_environment_wire,
        run_materials_environment_cid,
        expressions,
        operations,
        numeric_profile_cid=Some(foreign),
      )
      is None,
    )
  }
  let builtin = @numeric.cid(@numeric.builtin_profile())
  let admitted = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    expressions,
    operations,
    numeric_profile_cid=Some(builtin),
  ).unwrap()
  assert_eq(
    @checked.checking_environment_profile_selection(admitted).numeric_profile_cid,
    Some(builtin),
  )
}
