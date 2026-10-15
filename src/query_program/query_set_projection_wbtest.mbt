///|
test "anonymous positional fields reserve authored names and cannot shadow them" {
  let lexical : @query.LexicalLimits = {
    max_source_bytes: 10000,
    max_tokens: 1000,
    max_literal_bytes: 10000,
    max_work: 20000,
  }
  let query = @query.parse_query("SELECT 1 AS aql_set_anonymous_3, 2", {
    lexical,
    expression: { lexical, max_nodes: 1000, max_depth: 100, max_work: 10000, },
    max_syntax_nodes: 1000,
    max_cte_count: 20,
    max_work: 20000,
  }).unwrap()
  let projections = selected_projections(query)
  assert_eq(
    anonymous_set_projection_name(projections, ["input"], ["selected"]),
    "aql_set_anonymous_4",
  )
}

///|
test "set alignment composes evaluated column aliases and retains strict boundaries" {
  for
    (text, first_step, producer, folded) in [
      (
        "{\"from\":\"input\",\"select\":[{\"b\":\"right\"},{\"a\":\"left\"}],\"as\":\"out\"}",
        0, "out", true,
      ),
      (
        "{\"from\":\"input\",\"select\":[\"b\",\"a\"],\"as\":\"out\"}", 1, "out",
        false,
      ),
      (
        "{\"from\":\"input\",\"select\":[\"b\",\"a\"],\"as\":\"out\"}", 0, "another",
        false,
      ),
      (
        "{\"from\":\"input\",\"select\":[\"b\",\"a\"],\"as\":\"out\",\"distinct\":[\"a\",\"b\"]}",
        0, "out", false,
      ),
      (
        "{\"from\":\"input\",\"select\":[{\"a\":{\"literal\":1}},\"b\"],\"as\":\"out\"}",
        0, "out", false,
      ),
    ] {
    let document = @origin.document(text, 10000).unwrap()
    let builder = @builder.create(document, mapping_limits().source).unwrap()
    let construction : Construction = {
      builder,
      generated: @origin.range(document, 0, 0, kind=Generated).unwrap(),
      model_tasks: None,
      parameter_names: None,
      infer_labels: false,
      infer_budget: { remaining_work: mapping_limits().max_expression_work, },
    }
    let parsed = @wire.admit(
      @source.parse_json(text, mapping_limits().source.source).unwrap(),
      mapping_limits().source.tree,
    ).unwrap()
    let node = @builder.import_cursor(builder, parsed, construction.generated).unwrap()
    let steps = [node]
    assert_eq(
      fold_script_set_terminal_select(
        construction,
        steps,
        first_step,
        producer,
        ["id", "amount"],
        ["a", "b"],
      ),
      folded,
    )
    let saved = @builder.finish(builder, steps[0]).unwrap()
    let cursor = @builder.cursor(saved)
    let object = @wire.open_object(cursor).unwrap()
    assert_eq(@wire.text(@wire.lookup(object, "as").unwrap()), Ok("out"))
    assert_eq(@wire.text(@wire.lookup(object, "from").unwrap()), Ok("input"))
    let select = @wire.lookup(object, "select").unwrap()
    assert_eq(@wire.array_length(select), Some(2))
    if folded {
      let expected = [("id", "left"), ("amount", "right")]
      for index in 0..<expected.length() {
        let (name, input) = expected[index]
        let (actual_name, actual_input) = @wire.field_at(
          @wire.element_at(select, index).unwrap(),
          0,
        ).unwrap()
        assert_eq(actual_name, name)
        assert_eq(@wire.text(actual_input), Ok(input))
      }
    } else {
      assert_eq(
        @wire.object_field_names(cursor),
        @wire.object_field_names(parsed),
      )
    }
  }
}

///|
test "implicit set alignment preserves its receiver and rejects extra operations" {
  for
    (text, accepted) in [
      ("{\"select\":[{\"b\":\"right\"},{\"a\":\"left\"}],\"as\":\"out\"}", true),
      ("{\"select\":[{\"a\":{\"literal\":1}},\"b\"],\"as\":\"out\"}", false),
      (
        "{\"select\":[\"b\",\"a\"],\"as\":\"out\",\"distinct\":[\"a\",\"b\"]}", false,
      ),
    ] {
    let document = @origin.document(text, 10000).unwrap()
    let builder = @builder.create(document, mapping_limits().source).unwrap()
    let construction : Construction = {
      builder,
      generated: @origin.range(document, 0, 0, kind=Generated).unwrap(),
      model_tasks: None,
      parameter_names: None,
      infer_labels: false,
      infer_budget: { remaining_work: mapping_limits().max_expression_work, },
    }
    let parsed = @wire.admit(
      @source.parse_json(text, mapping_limits().source.source).unwrap(),
      mapping_limits().source.tree,
    ).unwrap()
    let steps = [
      @builder.import_cursor(builder, parsed, construction.generated).unwrap(),
    ]
    assert_eq(
      fold_script_set_terminal_select(
        construction,
        steps,
        0,
        "out",
        ["id", "amount"],
        ["a", "b"],
      ),
      accepted,
    )
    let object = @wire.open_object(
      @builder.cursor(@builder.finish(builder, steps[0]).unwrap()),
    ).unwrap()
    assert_true(@wire.lookup(object, "from") is None)
    if accepted {
      let select = @wire.lookup(object, "select").unwrap()
      for (index, expected) in [(0, ("id", "left")), (1, ("amount", "right"))] {
        let (name, value) = @wire.field_at(
          @wire.element_at(select, index).unwrap(),
          0,
        ).unwrap()
        assert_eq(name, expected.0)
        assert_eq(@wire.text(value), Ok(expected.1))
      }
    }
  }
}

///|
test "set result binding preserves bounded arguments and excludes shared steps" {
  let text = "{\"from\":\"ordered\",\"take\":{\"count\":{\"$param\":\"count\"},\"offset\":1},\"as\":\"limited\"}"
  for
    (first_step, producer, rebound) in [
      (0, "limited", true),
      (1, "limited", false),
      (0, "different", false),
    ] {
    let document = @origin.document(text, 10000).unwrap()
    let builder = @builder.create(document, mapping_limits().source).unwrap()
    let construction : Construction = {
      builder,
      generated: @origin.range(document, 0, 0, kind=Generated).unwrap(),
      model_tasks: None,
      parameter_names: None,
      infer_labels: false,
      infer_budget: { remaining_work: mapping_limits().max_expression_work, },
    }
    let parsed = @wire.admit(
      @source.parse_json(text, mapping_limits().source.source).unwrap(),
      mapping_limits().source.tree,
    ).unwrap()
    let steps = [
      @builder.import_cursor(builder, parsed, construction.generated).unwrap(),
    ]
    assert_eq(
      rebind_script_set_terminal_output(
        construction, steps, first_step, producer, "result",
      ),
      rebound,
    )
    let saved = @builder.finish(builder, steps[0]).unwrap()
    let object = @wire.open_object(@builder.cursor(saved)).unwrap()
    assert_eq(@wire.text(@wire.lookup(object, "from").unwrap()), Ok("ordered"))
    assert_eq(
      @wire.text(@wire.lookup(object, "as").unwrap()),
      Ok(if rebound { "result" } else { "limited" }),
    )
    let take = @wire.open_object(@wire.lookup(object, "take").unwrap()).unwrap()
    let count = @wire.open_object(@wire.lookup(take, "count").unwrap()).unwrap()
    assert_eq(@wire.text(@wire.lookup(count, "$param").unwrap()), Ok("count"))
    assert_eq(@wire.safe_integer(@wire.lookup(take, "offset").unwrap()), Ok(1L))
  }
}

///|
test "positional range names exclude anonymous storage without losing duplicate value slots" {
  let columns = [
    ("aql_set_anonymous_4", "aql_set_anonymous_4"),
    ("aql_set_duplicate_5", "aql_set_duplicate_5"),
    ("aql_set_duplicate_6", "aql_set_duplicate_6"),
    ("other", "other_slot"),
    ("aql_set_anonymous_100", "authored_slot"),
  ]
  assert_eq(
    positional_named_expression_columns(
      columns,
      ["aql_set_anonymous_4", "aql_set_duplicate_5", "aql_set_duplicate_6"],
      [("aql_set_duplicate_5", "v"), ("aql_set_duplicate_6", "V")],
    ),
    [
      ("v", "aql_set_duplicate_5"),
      ("V", "aql_set_duplicate_6"),
      ("other", "other_slot"),
      ("aql_set_anonymous_100", "authored_slot"),
    ],
  )
}
