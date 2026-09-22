///|
test "admitted projection retains nonnumeric values aliases and empty schema metadata" {
  let owner = capture_fixture()
  let limits : ValueLimits = {
    max_nodes: 1000,
    max_text_bytes: 1000,
    max_depth: 10,
    max_work: 10000,
  }
  for count in [0, 2] {
    let buffer = prepare_admitted_output(owner, Step(1), count, limits).unwrap()
    for row in 0..<count {
      append_admitted_output(buffer, output_fixture_row(owner, row)).unwrap()
    }
    let material = finish_admitted_output(buffer).unwrap()
    let names = Array::makei(@schema.field_count(material.schema), i => {
      @schema.reference_name(@schema.field_at(material.schema, i).unwrap().name)
    })
    let text_column = names.search_by(name => name != "n").unwrap()
    let text_name = names[text_column]
    let checked = @relation.check(
      Select,
      input_cursor("[{\"renamed\":\"" + text_name + "\"}]"),
      material.schema,
      None,
      {
        max_work: 10000,
        max_nodes: 1000,
        max_text_bytes: 1000,
        max_tokens: 1000,
        max_depth: 10,
      },
    ).unwrap()
    let table : CompletedTable = AdmittedTable({
      owner,
      id: "source",
      names,
      rows: material.rows,
    })
    let workspace = row_workspace(10000)
    let result = evaluate_completed_body(
      Projection(@lower.prepare_projection(checked).unwrap()),
      table,
      "projected",
      count,
      { remaining: 10000, max_frames: 100, },
      value_budget(limits).unwrap(),
      workspace,
      None,
    ).unwrap()
    guard result is AdmittedTable(projected) else {
      fail("lost admitted representation")
    }
    assert_eq(projected.names, ["renamed"])
    assert_eq(projected.rows.length(), count)
    assert_true(physical_equal(projected.owner, owner))
    for row in 0..<count {
      assert_true(
        physical_equal(projected.rows[row][0], material.rows[row][text_column]),
      )
    }
    for capacity in [workspace.peak, workspace.peak - 1] {
      let retried = evaluate_completed_body(
        Projection(@lower.prepare_projection(checked).unwrap()),
        table,
        "retry",
        count,
        { remaining: 10000, max_frames: 100, },
        value_budget(limits).unwrap(),
        { limit: capacity, live: 0, peak: 0, },
        None,
      )
      if capacity == workspace.peak {
        assert_true(retried is Ok(_))
      } else {
        assert_true(retried is Err(RowLimit))
      }
    }
    assert_eq(material.rows.length(), count)
  }
}
