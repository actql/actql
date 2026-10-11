///|
fn check_unpivot_row_label_source(
  source : String,
  format : @frontend.Format,
  values : String?,
) -> Unit raise {
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"rows\":{\"type\":\"array\",\"nullable\":false,\"max_items\":3,\"items\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"jan\":{\"type\":\"number\",\"nullable\":true},\"feb\":{\"type\":\"number\",\"nullable\":true}}}}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(declarations),
  }
  let lowered = @frontend.lower(
    source,
    format,
    if format == Json {
      None
    } else {
      Some(context)
    },
  ).unwrap()
  let program = match lowered.program {
    Some(program) => program
    None =>
      @program.parse(
        lowered.document,
        construction_limits().program,
        format=Json,
      ).unwrap()
  }
  match
    @check.check_parsed(
      program,
      check_environment(numeric=true),
      values.map(value => from_unpivot_public_cursor(value)),
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("every authored row-label input must close")
  }
}

///|
test "submitted UNPIVOT row-label unpivot-row-label-json-control" {
  check_unpivot_row_label_source(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.unpivot_row_labels\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"jan\":{\"type\":\"number\",\"nullable\":true},\"feb\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"id\":2,\"jan\":7,\"feb\":null},{\"id\":1,\"jan\":null,\"feb\":5},{\"id\":2,\"jan\":7,\"feb\":null}]},\"as\":\"wide\"},{\"from\":\"wide\",\"select\":[\"id\",\"feb\",{\"first_input\":\"jan\"},{\"second_input\":\"jan\"}]},{\"unpivot\":{\"columns\":[\"first_input\",\"second_input\"],\"keep\":[\"id\",\"feb\"],\"value_column\":\"amount\",\"name_column\":\"private_name\"}},{\"derive\":{\"month\":{\"if\":[{\"eq\":[{\"field\":\"private_name\"},{\"literal\":\"first_input\"}]},{\"literal\":\"first\"},{\"literal\":\"second\"}]}}},{\"sort\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"month\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[\"id\",\"amount\",\"month\"],\"as\":\"out\"}],\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[\"id\",\"amount\",\"month\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    Json,
    None,
  )
}

///|
test "submitted UNPIVOT row-label unpivot-row-label-from-repeated" {
  check_unpivot_row_label_source(
    "SELECT id,amount,month FROM (SELECT item.id AS id,item.jan AS jan,item.feb AS feb FROM UNNEST(@rows) item) UNPIVOT INCLUDE NULLS(amount FOR month IN(jan AS 'first',jan 'second')) ORDER BY id,month",
    Text,
    Some(
      "{\"rows\":[{\"id\":2,\"jan\":7,\"feb\":null},{\"id\":1,\"jan\":null,\"feb\":5},{\"id\":2,\"jan\":7,\"feb\":null}]}",
    ),
  )
}

///|
test "submitted UNPIVOT row-label unpivot-row-label-pipe-excluded" {
  check_unpivot_row_label_source(
    "FROM (SELECT item.id AS id,item.jan AS jan,item.feb AS feb FROM UNNEST(@rows) item) |> UNPIVOT(amount FOR month IN(jan AS 'first',jan AS 'second')) |> SELECT id,amount,month |> ORDER BY id,month",
    Text,
    Some(
      "{\"rows\":[{\"id\":2,\"jan\":7,\"feb\":null},{\"id\":1,\"jan\":null,\"feb\":5},{\"id\":2,\"jan\":7,\"feb\":null}]}",
    ),
  )
}

///|
test "submitted UNPIVOT row-label unpivot-row-label-renamed-default" {
  check_unpivot_row_label_source(
    "FROM (SELECT item.id AS id,item.jan AS jan,item.feb AS feb FROM UNNEST(@rows) item) |> RENAME feb AS current |> UNPIVOT INCLUDE NULLS(amount FOR month IN(jan AS 'first',current)) |> SELECT id,amount,month |> ORDER BY id,month",
    Text,
    Some(
      "{\"rows\":[{\"id\":2,\"jan\":7,\"feb\":null},{\"id\":1,\"jan\":null,\"feb\":5},{\"id\":2,\"jan\":7,\"feb\":null}]}",
    ),
  )
}

///|
test "submitted UNPIVOT row-label unpivot-row-label-empty" {
  check_unpivot_row_label_source(
    "SELECT id,amount,month FROM (SELECT item.id AS id,item.jan AS jan,item.feb AS feb FROM UNNEST(@rows) item) UNPIVOT INCLUDE NULLS(amount FOR month IN(jan AS 'first',jan 'second')) ORDER BY id,month",
    Text,
    Some("{\"rows\":[]}"),
  )
}

///|
test "submitted UNPIVOT row-label unpivot-row-label-same-label" {
  check_unpivot_row_label_source(
    "SELECT id,amount,month FROM (SELECT item.id AS id,item.jan AS jan,item.feb AS feb FROM UNNEST(@rows) item) UNPIVOT INCLUDE NULLS(amount FOR month IN(jan AS 'same',jan AS 'same')) ORDER BY id,month",
    Text,
    Some(
      "{\"rows\":[{\"id\":2,\"jan\":7,\"feb\":null},{\"id\":1,\"jan\":null,\"feb\":5},{\"id\":2,\"jan\":7,\"feb\":null}]}",
    ),
  )
}
