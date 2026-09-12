///|
test "item dependency ranges preserve repeated occurrences without mixing members" {
  for modes in [1, 10] {
    let contents = reference_fixture(view_count=3, modes~)
    let checked = check_catalog_references(contents, reference_caps()).unwrap()
    let catalog = catalog_at(contents, 0).unwrap()
    let environment = contract_registry_environment(catalog_registry(contents))
    let view_refs = 13 + (modes - 1) * 3
    assert_eq(reference_usage(checked).1, view_refs * 3 + 6)
    for
      item in [
        catalog_view_at(catalog, 0).unwrap(),
        catalog_view_at(catalog, 1).unwrap(),
        catalog_view_at(catalog, 2).unwrap(),
        catalog_command_at(catalog, 0).unwrap(),
      ] {
      let expected_count = if member_section(item) == SourceViews {
        view_refs
      } else {
        6
      }
      assert_eq(
        catalog_member_reference_count(checked, item),
        Some(expected_count),
      )
      let expected = []
      for i in 0..<reference_usage(checked).1 {
        let r = catalog_reference_at(checked, i).unwrap()
        if physical_equal(reference_member(r), item) {
          expected.push(r)
        }
      }
      assert_eq(expected.length(), expected_count)
      for i in 0..<expected_count {
        let actual = catalog_member_reference_at(checked, item, i).unwrap()
        assert_true(physical_equal(actual, expected[i]))
        assert_true(physical_equal(reference_member(actual), item))
        assert_true(physical_equal(reference_catalog(actual), catalog))
      }
      // A Member wrapper obtained again from the same environment remains valid.
      let again = member_at(
        environment,
        member_section(item),
        member_index(item),
      ).unwrap()
      assert_eq(
        catalog_member_reference_count(checked, again),
        Some(expected_count),
      )
      for invalid in [-2147483648, -1, expected_count, 2147483647] {
        assert_true(catalog_member_reference_at(checked, item, invalid) is None)
      }
    }
    for
      item in [
        catalog_member(catalog),
        member_at(environment, ContractRegistry, 0).unwrap(),
      ] {
      assert_true(catalog_member_reference_count(checked, item) is None)
      assert_true(catalog_member_reference_at(checked, item, 0) is None)
    }
    let foreign = reference_fixture(view_count=3, modes~)
    let foreign_catalog = catalog_at(foreign, 0).unwrap()
    let foreign_view = catalog_view_at(foreign_catalog, 0).unwrap()
    assert_eq(
      member_cid(foreign_view),
      member_cid(catalog_view_at(catalog, 0).unwrap()),
    )
    assert_true(catalog_member_reference_count(checked, foreign_view) is None)
    assert_true(catalog_member_reference_at(checked, foreign_view, 0) is None)
    let (work, count) = reference_usage(checked)
    assert_true(
      check_catalog_references(contents, {
        max_work: work,
        max_references: count,
      })
      is Ok(_),
    )
    assert_true(
      check_catalog_references(contents, {
        max_work: work - 1,
        max_references: count,
      })
      is Err({ kind: WorkLimit, .. }),
    )
  }
}
