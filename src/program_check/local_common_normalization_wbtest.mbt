///|
fn common_normalization_checked_fixture() -> CheckedProgram raise {
  let checked : Array[CheckedProgram] = []
  ignore(
    local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      checked_results=checked,
      generated_rows=Some("[{\"id\":1}]"),
      producer_expression="abs(id)",
    ),
  )
  checked[0]
}

///|
test "common normalization has one finite original audit without running legacy applicability" {
  let owner = common_normalization_checked_fixture()
  assert_false(owner.local_legacy_audit_prepared)
  let inventory = local_program_common_normalization_inventory(owner, 10000).unwrap()
  assert_false(owner.local_legacy_audit_prepared)
  assert_true(local_common_normalization_inventory_matches(inventory, owner))
  assert_eq(local_common_normalization_entry_count(inventory), 0)
  assert_true(
    physical_equal(
      local_common_normalization_inventory_requirements(inventory),
      owner.requirements,
    ),
  )
  let work = local_common_normalization_inventory_work(inventory)
  assert_true(work > 0)
  assert_true(
    local_program_common_normalization_inventory(owner, work) is Ok(_),
  )
  assert_true(
    local_program_common_normalization_inventory(owner, work - 1) is Err(_),
  )
  assert_true(
    local_program_common_normalization_inventory(owner, -1)
    is Err(InvalidLimits),
  )
  let equal = common_normalization_checked_fixture()
  assert_false(local_common_normalization_inventory_matches(inventory, equal))
  let copied = { ..owner, }
  assert_false(local_common_normalization_inventory_matches(inventory, copied))
}

///|
test "generic normalization does not reinterpret unrecorded implicit expression completion" {
  let checked : Array[CheckedProgram] = []
  ignore(
    local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      checked_results=checked,
      generated_rows=Some("[{\"id\":1}]"),
      producer_expression="CASE WHEN true THEN id END",
    ),
  )
  assert_true(
    local_program_common_normalization_inventory(checked[0], 10000)
    is Err(CompletionObserved),
  )
}

///|
test "common normalization retains Number reduction requirements without supplying numeric execution" {
  for name in ["sum", "avg"] {
    let owner = checked_direct_program_fixture(
      explicit_view=true,
      group_body="{\"by\":[\"id\"],\"aggregates\":{\"total\":{\"fn\":\"" +
        name +
        "\",\"field\":\"id\"}}}",
      numeric_profile=Some(numeric_profile_fixture()),
    )
    let inventory = local_program_common_normalization_inventory(owner, 10000).unwrap()
    assert_true(
      physical_equal(
        local_common_normalization_inventory_requirements(inventory),
        owner.requirements,
      ),
    )
    let prepared = @lower.prepare(owner.units[0].pipeline, {
      max_nodes: 1000,
      max_references: 1000,
      max_work: 100000,
      max_identifier_bytes: 10000,
    }).unwrap()
    let bound = @lower.bind_parameters(
      prepared,
      None,
      max_parameters=100,
      max_name_bytes=10000,
    ).unwrap()
    let (group, _) = @lower.prepare_group(bound, 0, 1000, 10000, {
      max_nodes: 1000,
      max_work: 100000,
      max_depth: 100,
      max_literal_nodes: 10000,
      max_literal_text_bytes: 100000,
    }).unwrap()
    assert_true(
      @lower.group_aggregate_requires_numeric_observation(
        @lower.group_aggregate_at(group, 0).unwrap(),
      ),
    )
    assert_false(@execution.group_execution_supported(group))
    assert_true(@execution.group_execution_supported_with_numeric(group))
  }
}
