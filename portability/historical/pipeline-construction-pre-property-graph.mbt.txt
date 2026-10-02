///|
fn graph_rows_input() -> @carrier.Carrier {
  let number = @contract.primitive(NumberType, nullable=false)
  @carrier.relation(
    @carrier.rows(
      [
        (Unqualified("id"), Some(number)),
        (Unqualified("src_id"), Some(number)),
        (Unqualified("dst_id"), Some(number)),
        (Unqualified("weight"), Some(number)),
      ],
      field_set=Closed,
      max_fields=4,
      max_name_bytes=100,
    ).unwrap(),
  )
}

///|
test "named graph branches are ordered operands and bridge to relation consumers" {
  let input = graph_rows_input()
  let p = @pipeline_typing.check_carriers(
    cursor(
      (
        #|[{"graph":{"nodes":{"from":"rows","id":"id","fields":[]},"edges":{"from":"rows","source":"src_id","target":"dst_id","fields":["weight"]}},"as":"g"},
        #| {"node_rows":true},{"select":["id"]}]
      ),
    ),
    [("rows", input)],
    None,
    None,
    limits(),
  ).unwrap()
  let step = @pipeline_typing.step_at(p, 0).unwrap()
  assert_true(step.input is None)
  assert_true(
    step.operation
    is GraphConstruction(nodes=Some(Input(0)), edges=Input(0), ..),
  )
  let refs = @pipeline_typing.input_occurrences(step)
  assert_eq(refs.length(), 2)
  assert_true(refs[0] is { role: Left, target: Input(0), })
  assert_true(refs[1] is { role: Right, target: Input(0), })
  assert_true(@pipeline_typing.output_schema(p) is Some(_))
}

///|
test "concise graph consumes current while explicit branches reject conflicting from" {
  let input = graph_rows_input()
  assert_true(
    @pipeline_typing.check_carriers(
      cursor(
        "[{\"graph\":{\"source\":\"src_id\",\"target\":\"dst_id\"}},{\"degree\":{\"direction\":\"out\"}}]",
      ),
      [("r", input)],
      None,
      None,
      limits(),
    )
    is Ok(_),
  )
  for extra in ["", ",\"as\":\"g\",\"from\":\"r\""] {
    assert_true(
      @pipeline_typing.check_carriers(
        cursor(
          "[{\"graph\":{\"nodes\":{\"from\":\"r\",\"id\":\"id\"},\"edges\":{\"from\":\"r\",\"source\":\"src_id\",\"target\":\"dst_id\"}}" +
          extra +
          "}]",
        ),
        [("r", input)],
        None,
        None,
        limits(),
      )
      is Err(_),
    )
  }
}
