///|
test "partitioned consumers complete only unfixed identity components" {
  let carrier = @carrier.relation(@carrier.typed_rows(schema()))
  let key = @evidence.declare_primary_key(
    cursor("[\"id\",\"amount\"]"),
    carrier,
    { max_fields: 2, max_name_bytes: 20, },
  ).unwrap()
  let inputs = [("rows", @pipeline_typing.KeyedInput(key))]
  for kind in ["top_k_by", "lag", "analytic"] {
    for
      partition in [
        "[]", "[\"amount\"]", "[\"id\"]", "[\"copy\"]", "[\"id\",\"id\"]", "[\"id\",\"amount\"]",
      ] {
      let body = if kind == "top_k_by" {
        "\"k\":1,\"by\":[{\"field\":\"amount\",\"dir\":\"desc\",\"nulls\":\"first\"}]"
      } else if kind == "lag" {
        "\"field\":\"amount\",\"output\":\"previous\",\"order_by\":[{\"amount\":\"asc\"}]"
      } else {
        "\"order_by\":[{\"amount\":\"asc\"}],\"functions\":{\"position\":{\"fn\":\"row_number\"}}"
      }
      let source = cursor(
        "[{\"derive\":{\"copy\":\"id\"}},{\"" +
        kind +
        "\":{\"partition_by\":" +
        partition +
        "," +
        body +
        "}}]",
      )
      let p = @pipeline_typing.check_with_evidence(
        source,
        inputs,
        None,
        None,
        limits(),
      ).unwrap()
      let completion = if kind == "lag" {
        @pipeline_typing.lag_order_completion(p, 1).unwrap()
      } else if kind == "analytic" {
        @pipeline_typing.analytic_order_completion(
          @pipeline_typing.analytic_position_order(p, 1).unwrap(),
        ).unwrap()
      } else {
        @pipeline_typing.order_sort_completion(
          @pipeline_typing.logical_order(p, Step(1)).unwrap(),
        ).unwrap()
      }
      assert_eq(
        @pipeline_typing.sort_completion_count(completion),
        if partition == "[]" || partition == "[\"amount\"]" {
          1
        } else {
          0
        },
      )
      assert_eq(
        @evidence.key_field_count(
          @pipeline_typing.sort_completion_key(completion),
        ),
        2,
      )
      // Position selection is not the output sequence for lag or analytic.
      assert_eq(
        @pipeline_typing.logical_order(p, Step(1)) is Some(_),
        kind == "top_k_by",
      )
      let used = @pipeline_typing.usage(p)
      let exact = {
        ..limits(),
        max_work: used.work,
        max_text_bytes: used.text_bytes,
        max_nodes: used.nodes,
        max_tokens: used.tokens,
      }
      assert_true(
        @pipeline_typing.check_with_evidence(source, inputs, None, None, exact)
        is Ok(_),
      )
      assert_true(
        @pipeline_typing.check_with_evidence(source, inputs, None, None, {
          ..exact,
          max_work: used.work - 1,
        })
        is Err(_),
      )
      assert_true(
        @pipeline_typing.check_with_evidence(source, inputs, None, None, {
          ..exact,
          max_text_bytes: used.text_bytes - 1,
        })
        is Err(_),
      )
    }
  }
}
