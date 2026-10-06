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
test "named Graph definitions retain ordered repeated operands through MATCH" {
  let p = @pipeline_typing.check_carriers(
    cursor(
      (
        #|[{"values":{"schema":{"id":{"type":"number","nullable":false},"src_id":{"type":"number","nullable":false},"dst_id":{"type":"number","nullable":false},"weight":{"type":"number","nullable":false}},"rows":[{"id":1,"src_id":1,"dst_id":1,"weight":2}]},"as":"rows"},
        #| {"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"rows","key":["id"],"labels":[{"name":"Node","properties":{"mode":"no_properties"}}]}],"edges":[{"name":"E","from":"rows","key":["id"],"source":{"definition":"N","key":["src_id"]},"target":{"definition":"N","key":["dst_id"]},"labels":[{"name":"Edge","properties":{"mode":"columns","columns":[{"from":"weight","to":"weight"}]}}]}]},"as":"g"},
        #| {"match_nodes":{"definition":"N","bindings":{"identity":"element"},"where":"true","fields":["element"]}},{"select":["element"]}]
      ),
    ),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  let step = @pipeline_typing.step_at(p, 1).unwrap()
  assert_true(step.input is None)
  assert_true(
    step.operation is GraphConstruction(inputs=[Step(0), Step(0)], ..),
  )
  let refs = @pipeline_typing.input_occurrences(step)
  assert_eq(refs.length(), 2)
  assert_true(refs[0] is { role: Sample(0), target: Step(0), })
  assert_true(refs[1] is { role: Sample(1), target: Step(0), })
  assert_eq(@schema.field_count(@pipeline_typing.output_schema(p).unwrap()), 1)
  assert_true(@pipeline_typing.output_schema(p) is Some(_))
}

///|
test "retired Graph constructors are refused without issuing a compatible Graph" {
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
    is Err(
      {
        kind: Graph(@graph.UnsupportedGraphOperation),
        path: [Index(0), Key("graph")],
        ..
      }
    ),
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
