///|
test "final selected Client environment preserves the same admitted wire original" {
  let (body, cid) = source_extent_environment(false)
  let wire = admit_client_check_environment_wire(body, cid).unwrap()
  let expressions : @context.ExpressionProfiles = {
    text_time: false,
    veca: true,
  }
  let operations : @context.PureOperationProfiles = {
    rela: true,
    sga: true,
    tea: true,
    calendar: false,
    text_rank: false,
  }
  let numeric = @numeric.cid(@numeric.builtin_profile())
  let selected_environment = admit_client_check_environment_from_wire_with_numeric_profile_cid(
    wire,
    expressions,
    operations,
    numeric,
    graph=true,
  ).unwrap()
  assert_true(
    physical_equal(
      @checked.checking_environment_wire(selected_environment),
      wire,
    ),
  )
  assert_eq(@checked.checking_environment_cid(selected_environment), cid)
  let selected = @checked.checking_environment_profile_selection(
    selected_environment,
  )
  assert_eq(selected.numeric_profile_cid, Some(numeric))
  assert_true(selected.graph)
  assert_true(selected.expressions.veca)
  assert_true(selected.operations.sga)
  assert_eq(@environment.member_count(wire, @environment.SourceViews), 65)
}

///|
test "final selected Client environment rejects another numeric profile without replacing its wire" {
  let wire = admit_client_check_environment_wire(
    run_materials_environment_wire, run_materials_environment_cid,
  ).unwrap()
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
  assert_true(
    admit_client_check_environment_from_wire_with_numeric_profile_cid(
      wire,
      expressions,
      operations,
      "sha256:" + "0".repeat(64),
      graph=true,
    )
    is None,
  )
  let valid = admit_client_check_environment_from_wire_with_numeric_profile_cid(
    wire,
    expressions,
    operations,
    @numeric.cid(@numeric.builtin_profile()),
  ).unwrap()
  assert_true(physical_equal(@checked.checking_environment_wire(valid), wire))
  assert_false(@checked.checking_environment_profile_selection(valid).graph)
}
