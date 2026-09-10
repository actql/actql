///|
fn target(value : @pipeline_typing.Target) -> String {
  match value {
    Input(i) => "input:" + i.to_string()
    Step(i) => "step:" + i.to_string()
  }
}

///|
fn corpus_accepted(
  source : String,
  names : Array[String],
  from : String?,
  current : String?,
  edges : Array[String],
  fields : Array[String],
) -> Unit raise {
  let p = @pipeline_typing.check(
    cursor(source),
    names.map(n => (n, schema())),
    None,
    from.map(cursor),
    limits(),
  ).unwrap()
  assert_eq(@pipeline_typing.current(p).map(target), current)
  assert_eq(@pipeline_typing.step_count(p), edges.length())
  for i in 0..<edges.length() {
    assert_eq(
      target(@pipeline_typing.step_at(p, i).unwrap().input.unwrap()),
      edges[i],
    )
  }
  if current is None {
    assert_true(@pipeline_typing.output_carrier(p) is None)
    assert_true(@pipeline_typing.output_schema(p) is None)
    return
  }
  let expected = @contract.object_contract(
    fields.map(name => {
      let kind = match name {
        "amount" => @contract.NumberType
        "flag" => BooleanType
        _ => StringType
      }
      (name, @contract.primitive(kind, nullable=name == "flag"))
    }),
    nullable=false,
    max_fields=100,
    max_name_bytes=10000,
  ).unwrap()
  assert_true(
    @contract.type_equal(
      @schema.as_object(@pipeline_typing.output_schema(p).unwrap()).unwrap(),
      expected,
      1000,
    ),
  )
}

///|
fn corpus_rejected(
  source : String,
  names : Array[String],
  from : String?,
  issue : String,
) -> Unit raise {
  let result = @pipeline_typing.check(
    cursor(source),
    names.map(n => (n, schema())),
    None,
    from.map(cursor),
    limits(),
  ).unwrap_err()
  let actual = match result.kind {
    MissingCurrent => "MissingCurrent"
    DuplicateName(_) => "DuplicateName"
    UnknownName(_) => "UnknownName"
    UnsupportedOperation(_) => "UnsupportedOperation"
    Operation(_) => "Operation"
    InvalidBody => "InvalidBody"
    ReservedMetadataKey(_) => "ReservedMetadataKey"
    _ => "unexpected"
  }
  assert_eq(actual, issue)
}
