///|
test "unary metadata shares the accepted lazy audit and preserves Sort completion" {
  for sorted in [false, true] {
    let checked : Array[CheckedProgram] = []
    ignore(
      local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        through_check=true,
        checked_results=checked,
        generated_rows=Some("[{\"id\":2},{\"id\":1}]"),
        producer_expression="try_timestamp('2000-02-29T00:00:00.123456789Z')",
        producer_suffix=if sorted {
          ",{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"value\":{\"fn\":\"count\"}}}},{\"sort\":[{\"value\":\"asc\"}],\"as\":\"ordered\"}"
        } else {
          ""
        },
        producer_result_from=if sorted { "ordered" } else { "derived" },
        extra_step_budget=if sorted { 2 } else { 0 },
      ),
    )
    let owner = checked[0]
    assert_false(owner.local_legacy_audit_prepared)
    ignore(local_program_common_normalization_inventory(owner, 10000).unwrap())
    assert_false(owner.local_legacy_audit_prepared)
    if sorted {
      let inventory = local_program_sort_normalization_inventory(owner)
        .unwrap()
        .unwrap()
      assert_true(
        local_sort_normalization_inventory_uses_unary_timestamp(inventory),
      )
      assert_false(
        local_sort_normalization_inventory_uses_decimal_sum(inventory),
      )
      assert_eq(local_sort_normalization_entry_count(inventory), 1)
      assert_true(
        local_program_completion_free_inventory(owner)
        is Err(CompletionObserved),
      )
    } else {
      let inventory = local_program_completion_free_inventory(owner).unwrap()
      assert_true(
        local_completion_free_inventory_uses_unary_timestamp(inventory),
      )
      assert_false(local_completion_free_inventory_uses_decimal_sum(inventory))
    }
    assert_true(owner.local_legacy_audit_prepared)
    let original = local_legacy_audit(owner)
    assert_true(physical_equal(original, local_legacy_audit(owner)))
    let foreign = common_normalization_checked_fixture()
    assert_false(foreign.local_legacy_audit_prepared)
  }
}
