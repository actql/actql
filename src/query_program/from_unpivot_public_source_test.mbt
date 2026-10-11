///|
fn from_unpivot_public_cursor(text : String) -> @wire.Cursor {
  @wire.admit(
    @source.parse_json(text, construction_limits().source.source).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
}

///|
test "submitted FROM UNPIVOT sources reach normal parameter checking without fixture repair" {
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"rows\":{\"type\":\"array\",\"nullable\":false,\"max_items\":3,\"items\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"jan\":{\"type\":\"number\",\"nullable\":true},\"feb\":{\"type\":\"number\",\"nullable\":true}}}}}",
      ),
    ),
    { max_parameters: 10, max_nodes: 128, max_depth: 16, max_text_bytes: 4096, },
  ).unwrap()
  let context = @frontend.bind_query_context(
    [],
    "fixture.environment",
    parameter_declarations=Some(declarations),
  ).unwrap()
  let cases : Array[(String, String, String)] = [
    (
      "from-unpivot-default", "SELECT id,amount,month FROM (SELECT item.id AS id,item.jan AS jan,item.feb AS feb FROM UNNEST(@rows) item) UNPIVOT(amount FOR month IN(jan,feb)) ORDER BY id,month",
      "{\"rows\":[{\"id\":2,\"jan\":7,\"feb\":null},{\"id\":1,\"jan\":null,\"feb\":5},{\"id\":2,\"jan\":7,\"feb\":null}]}",
    ),
    (
      "from-unpivot-include-alias", "SELECT shaped.id,shaped.amount,shaped.month FROM (SELECT item.id AS id,item.jan AS jan,item.feb AS feb FROM UNNEST(@rows) item) original UNPIVOT INCLUDE NULLS(amount FOR month IN(jan,feb)) AS shaped ORDER BY id,month",
      "{\"rows\":[{\"id\":2,\"jan\":7,\"feb\":null},{\"id\":1,\"jan\":null,\"feb\":5},{\"id\":2,\"jan\":7,\"feb\":null}]}",
    ),
    (
      "from-unpivot-pipe-head", "FROM (SELECT item.id AS id,item.jan AS jan,item.feb AS feb FROM UNNEST(@rows) item) UNPIVOT INCLUDE NULLS(amount FOR month IN(jan,feb)) AS shaped |> SELECT shaped.id,shaped.amount,shaped.month |> ORDER BY id,month",
      "{\"rows\":[{\"id\":2,\"jan\":7,\"feb\":null},{\"id\":1,\"jan\":null,\"feb\":5},{\"id\":2,\"jan\":7,\"feb\":null}]}",
    ),
    (
      "from-unpivot-filtered-limit-offset", "SELECT id,amount,month FROM (SELECT item.id AS id,item.jan AS jan,item.feb AS feb FROM UNNEST(@rows) item) UNPIVOT INCLUDE NULLS(amount FOR month IN(jan,feb)) WHERE amount>5 ORDER BY id,month LIMIT 1 OFFSET 1",
      "{\"rows\":[{\"id\":2,\"jan\":7,\"feb\":null},{\"id\":1,\"jan\":null,\"feb\":5},{\"id\":2,\"jan\":7,\"feb\":null}]}",
    ),
    (
      "from-unpivot-empty", "SELECT id,amount,month FROM (SELECT item.id AS id,item.jan AS jan,item.feb AS feb FROM UNNEST(@rows) item) UNPIVOT INCLUDE NULLS(amount FOR month IN(jan,feb)) ORDER BY id,month",
      "{\"rows\":[]}",
    ),
    (
      "from-unpivot-left-join-port", "SELECT shaped.id,shaped.amount,shaped.month,p.marker FROM (SELECT item.id AS id,item.jan AS jan,item.feb AS feb FROM UNNEST(@rows) item) UNPIVOT INCLUDE NULLS(amount FOR month IN(jan,feb)) shaped JOIN (SELECT 2 AS id,100 AS marker) p ON shaped.id=p.id MAX_OUTPUT_ROWS 10 ORDER BY id,month",
      "{\"rows\":[{\"id\":2,\"jan\":7,\"feb\":null},{\"id\":1,\"jan\":null,\"feb\":5},{\"id\":2,\"jan\":7,\"feb\":null}]}",
    ),
    (
      "from-unpivot-right-join-port", "SELECT shaped.id,shaped.amount,shaped.month,p.marker FROM (SELECT 2 AS id,100 AS marker) p JOIN (SELECT item.id AS id,item.jan AS jan,item.feb AS feb FROM UNNEST(@rows) item) UNPIVOT INCLUDE NULLS(amount FOR month IN(jan,feb)) shaped ON p.id=shaped.id MAX_OUTPUT_ROWS 10 ORDER BY id,month",
      "{\"rows\":[{\"id\":2,\"jan\":7,\"feb\":null},{\"id\":1,\"jan\":null,\"feb\":5},{\"id\":2,\"jan\":7,\"feb\":null}]}",
    ),
  ]
  for (name, source, values) in cases {
    let lowered = match @frontend.lower(source, Text, Some(context)) {
      Ok(value) => value
      Err(QueryLowering(UnsupportedCte)) => fail(name + ": UnsupportedCte")
      Err(QueryLowering(UnsupportedJoin)) => fail(name + ": UnsupportedJoin")
      Err(QueryLowering(UnknownColumn)) => fail(name + ": UnknownColumn")
      Err(QueryLowering(Expression({ issue: UnknownReference, .. }))) =>
        fail(name + ": UnknownReference")
      Err(_) => fail(name + ": source lowering refusal")
    }
    let program = lowered.program.unwrap()
    match
      @check.check_parsed(
        program,
        check_environment(numeric=true),
        Some(from_unpivot_public_cursor(values)),
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail(name + ": all supplied parameters must close")
    }
    if source.contains("MAX_OUTPUT_ROWS 10") {
      assert_true(lowered.document.contains("\"max_output_rows\":10"), msg=name)
    }
  }
}

///|
test "authored FROM UNPIVOT JSON controls pass the same common checker" {
  for
    source in [
      "{\"version\":\"actql/0.1\",\"id\":\"fixture.from_unpivot\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"jan\":{\"type\":\"number\",\"nullable\":true},\"feb\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"id\":2,\"jan\":7,\"feb\":null},{\"id\":1,\"jan\":null,\"feb\":5},{\"id\":2,\"jan\":7,\"feb\":null}]},\"as\":\"wide\"},{\"from\":\"wide\",\"unpivot\":{\"columns\":[\"jan\",\"feb\"],\"keep\":[\"id\"],\"value_column\":\"amount\",\"name_column\":\"month\"}},{\"filter\":{\"not\":{\"is_null\":{\"field\":\"amount\"}}}},{\"sort\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"month\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[\"id\",\"amount\",\"month\"],\"as\":\"out\"}],\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[\"id\",\"amount\",\"month\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
      "{\"version\":\"actql/0.1\",\"id\":\"fixture.from_unpivot\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"jan\":{\"type\":\"number\",\"nullable\":true},\"feb\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"id\":2,\"jan\":7,\"feb\":null},{\"id\":1,\"jan\":null,\"feb\":5},{\"id\":2,\"jan\":7,\"feb\":null}]},\"as\":\"wide\"},{\"from\":\"wide\",\"unpivot\":{\"columns\":[\"jan\",\"feb\"],\"keep\":[\"id\"],\"value_column\":\"amount\",\"name_column\":\"month\"}},{\"sort\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"month\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[\"id\",\"amount\",\"month\"],\"as\":\"out\"}],\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[\"id\",\"amount\",\"month\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    ] {
    let machine = @frontend.lower(source, Json, None).unwrap()
    assert_true(machine.program is None)
    let program = @program.parse(
      machine.document,
      construction_limits().program,
      format=machine.format,
    ).unwrap()
    match
      @check.check_parsed(
        program,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) =>
        fail("authored Values controls require no external input")
    }
  }
}
