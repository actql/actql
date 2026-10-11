///|
// Independently authored compiler connection expectations.
// Expectations are authored from positional rotation and evaluated input slots.
fn assert_tuple_unpivot_wire(
  actual : @wire.Cursor,
  expected : @wire.Cursor,
) raise {
  match @wire.view(expected) {
    @wire.TextValue(value) => assert_eq(@wire.text(actual), Ok(value))
    @wire.ArrayValue(values) => {
      assert_eq(@wire.array_length(actual), Some(values.length()))
      for index in 0..<values.length() {
        assert_tuple_unpivot_wire(
          @wire.element_at(actual, index).unwrap(),
          values[index],
        )
      }
    }
    @wire.ObjectValue(expected_object) => {
      let names = @wire.object_field_names(expected).unwrap()
      let actual_object = @wire.open_object(actual).unwrap()
      assert_eq(@wire.object_length(actual), Some(names.length()))
      for name in names {
        assert_tuple_unpivot_wire(
          @wire.required(actual_object, name).unwrap(),
          @wire.required(expected_object, name).unwrap(),
        )
      }
    }
    _ =>
      fail(
        "this independently authored connection uses only arrays, objects and Strings",
      )
  }
}

///|
test "tuple UNPIVOT has independent complete connection steps and visible slots" {
  let text = "FROM wide |> UNPIVOT ((amount,note) FOR month IN ((jan_amount,jan_note) AS 'Jan',(feb_amount,feb_note) AS 'Feb'))"
  let query = @query.parse_query(text, mapping_syntax_limits()).unwrap()
  guard @query.operation_at(query, 0) is Some(@query.Unpivot(clause)) else {
    fail("retain one grouped UNPIVOT operation")
  }
  let document = @origin.document(text, 10000).unwrap()
  let builder = @builder.create(document, mapping_limits().source).unwrap()
  let construction : Construction = {
    builder,
    generated: @origin.range(document, 0, 0, kind=Generated).unwrap(),
    model_tasks: None,
    parameter_names: None,
  }
  let (steps, visible, physical) = lower_multi_column_unpivot(
    construction,
    clause,
    [
      ("id", "id"),
      ("jan_amount", "jan_amount"),
      ("jan_note", "jan_note"),
      ("feb_amount", "feb_amount"),
      ("feb_note", "feb_note"),
    ],
  )
  // Destination names participate in private-name reservation.
  assert_eq(visible, [
    ("id", "id"),
    ("amount", "aql_unpivot_output_13"),
    ("note", "aql_unpivot_output_14"),
    ("month", "aql_unpivot_label_12"),
  ])
  assert_eq(physical, [
    "id", "aql_unpivot_name_10", "aql_unpivot_value_11", "aql_unpivot_label_12",
    "aql_unpivot_output_13", "aql_unpivot_output_14",
  ])
  let root = construction.array(steps.map(step => construction.object(step)))
  let actual = @builder.cursor(@builder.finish(builder, root).unwrap())
  let expected = @wire.admit(
    @source.parse_json(
      (
        #|[{"derive":{"aql_unpivot_input_8":{"object":{"v0":{"field":"jan_amount"},"v1":{"field":"jan_note"}}},"aql_unpivot_input_9":{"object":{"v0":{"field":"feb_amount"},"v1":{"field":"feb_note"}}}}},{"select":["id","aql_unpivot_input_8","aql_unpivot_input_9"]},{"unpivot":{"columns":["aql_unpivot_input_8","aql_unpivot_input_9"],"keep":["id"],"name_column":"aql_unpivot_name_10","value_column":"aql_unpivot_value_11"}},{"derive":{"aql_unpivot_output_13":{"property":{"value":{"field":"aql_unpivot_value_11"},"name":"v0"}},"aql_unpivot_output_14":{"property":{"value":{"field":"aql_unpivot_value_11"},"name":"v1"}},"aql_unpivot_label_12":{"if":[{"eq":[{"field":"aql_unpivot_name_10"},{"literal":"aql_unpivot_input_8"}]},{"literal":"Jan"},{"literal":"Feb"}]}}},{"filter":{"or":[{"not":{"is_null":{"field":"aql_unpivot_output_13"}}},{"not":{"is_null":{"field":"aql_unpivot_output_14"}}}]}}]
      ),
      mapping_limits().source.source,
    ).unwrap(),
    mapping_limits().source.tree,
  ).unwrap()
  assert_tuple_unpivot_wire(actual, expected)
}
