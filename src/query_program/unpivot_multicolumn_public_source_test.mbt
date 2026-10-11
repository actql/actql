///|
fn check_multicolumn_unpivot_source(
  source : String,
  format : @frontend.Format,
  declarations_json : String?,
  values : String?,
) -> Unit raise {
  let declarations = @parameters.read_declarations(
    declarations_json.map(from_unpivot_public_cursor),
    {max_parameters: 10, max_nodes: 1000, max_depth: 100, max_text_bytes: 10000},
  ).unwrap()
  let context = {..fixture_context(), inputs: [], parameter_declarations: Some(declarations)}
  let lowered = @frontend.lower(source, format, if format == Json { None } else { Some(context) }).unwrap()
  let program = match lowered.program {
    Some(program) => program
    None => @program.parse(lowered.document, construction_limits().program, format=Json).unwrap()
  }
  match @check.check_parsed(program, check_environment(numeric=true),
    values.map(from_unpivot_public_cursor), check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the authored tuple input must close")
  }
}

///|
test "submitted multi-column UNPIVOT unpivot-multicolumn-json-exclude-control" {
  check_multicolumn_unpivot_source(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.multi_column_unpivot\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"jan_amount\":{\"type\":\"number\",\"nullable\":true},\"jan_note\":{\"type\":\"string\",\"nullable\":true},\"feb_amount\":{\"type\":\"number\",\"nullable\":true},\"feb_note\":{\"type\":\"string\",\"nullable\":true}},\"rows\":[{\"id\":2,\"jan_amount\":null,\"jan_note\":null,\"feb_amount\":7,\"feb_note\":\"B\"},{\"id\":1,\"jan_amount\":5,\"jan_note\":null,\"feb_amount\":null,\"feb_note\":\"kept\"},{\"id\":2,\"jan_amount\":null,\"jan_note\":null,\"feb_amount\":7,\"feb_note\":\"B\"}]},\"as\":\"wide\"},{\"from\":\"wide\",\"derive\":{\"private_jan\":{\"object\":{\"amount\":{\"field\":\"jan_amount\"},\"note\":{\"field\":\"jan_note\"}}},\"private_feb\":{\"object\":{\"amount\":{\"field\":\"feb_amount\"},\"note\":{\"field\":\"feb_note\"}}}}},{\"select\":[\"id\",\"private_jan\",\"private_feb\"]},{\"unpivot\":{\"columns\":[\"private_jan\",\"private_feb\"],\"keep\":[\"id\"],\"name_column\":\"private_name\",\"value_column\":\"private_bundle\"}},{\"derive\":{\"amount\":{\"property\":{\"value\":{\"field\":\"private_bundle\"},\"name\":\"amount\"}},\"note\":{\"property\":{\"value\":{\"field\":\"private_bundle\"},\"name\":\"note\"}},\"month\":{\"if\":[{\"eq\":[{\"field\":\"private_name\"},{\"literal\":\"private_jan\"}]},{\"literal\":\"Jan\"},{\"literal\":\"Feb\"}]}}},{\"filter\":{\"or\":[{\"not\":{\"is_null\":{\"field\":\"amount\"}}},{\"not\":{\"is_null\":{\"field\":\"note\"}}}]}},{\"sort\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"month\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[\"id\",\"amount\",\"note\",\"month\"],\"as\":\"out\"}],\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[\"id\",\"amount\",\"note\",\"month\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    Json,
    None,
    None,
  )
}

///|
test "submitted multi-column UNPIVOT unpivot-multicolumn-json-include-control" {
  check_multicolumn_unpivot_source(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.multi_column_unpivot\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"jan_amount\":{\"type\":\"number\",\"nullable\":true},\"jan_note\":{\"type\":\"string\",\"nullable\":true},\"feb_amount\":{\"type\":\"number\",\"nullable\":true},\"feb_note\":{\"type\":\"string\",\"nullable\":true}},\"rows\":[{\"id\":2,\"jan_amount\":null,\"jan_note\":null,\"feb_amount\":7,\"feb_note\":\"B\"},{\"id\":1,\"jan_amount\":5,\"jan_note\":null,\"feb_amount\":null,\"feb_note\":\"kept\"},{\"id\":2,\"jan_amount\":null,\"jan_note\":null,\"feb_amount\":7,\"feb_note\":\"B\"}]},\"as\":\"wide\"},{\"from\":\"wide\",\"derive\":{\"private_jan\":{\"object\":{\"amount\":{\"field\":\"jan_amount\"},\"note\":{\"field\":\"jan_note\"}}},\"private_feb\":{\"object\":{\"amount\":{\"field\":\"feb_amount\"},\"note\":{\"field\":\"feb_note\"}}}}},{\"select\":[\"id\",\"private_jan\",\"private_feb\"]},{\"unpivot\":{\"columns\":[\"private_jan\",\"private_feb\"],\"keep\":[\"id\"],\"name_column\":\"private_name\",\"value_column\":\"private_bundle\"}},{\"derive\":{\"amount\":{\"property\":{\"value\":{\"field\":\"private_bundle\"},\"name\":\"amount\"}},\"note\":{\"property\":{\"value\":{\"field\":\"private_bundle\"},\"name\":\"note\"}},\"month\":{\"if\":[{\"eq\":[{\"field\":\"private_name\"},{\"literal\":\"private_jan\"}]},{\"literal\":\"Jan\"},{\"literal\":\"Feb\"}]}}},{\"sort\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"month\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[\"id\",\"amount\",\"note\",\"month\"],\"as\":\"out\"}],\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[\"id\",\"amount\",\"note\",\"month\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    Json,
    None,
    None,
  )
}

///|
test "submitted multi-column UNPIVOT unpivot-multicolumn-data-from-exclude" {
  check_multicolumn_unpivot_source(
    "DATA wide = SELECT item.id AS id,item.jan_amount AS jan_amount,item.jan_note AS jan_note,item.feb_amount AS feb_amount,item.feb_note AS feb_note FROM UNNEST(@rows) item; SELECT id,amount,note,month FROM wide UNPIVOT ((amount,note) FOR month IN ((jan_amount,jan_note) AS 'Jan',(feb_amount,feb_note) AS 'Feb')) ORDER BY id,month",
    Text,
    Some("{\"rows\":{\"type\":\"array\",\"nullable\":false,\"max_items\":3,\"items\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"jan_amount\":{\"type\":\"number\",\"nullable\":true},\"jan_note\":{\"type\":\"string\",\"nullable\":true},\"feb_amount\":{\"type\":\"number\",\"nullable\":true},\"feb_note\":{\"type\":\"string\",\"nullable\":true}}}}}"),
    Some("{\"rows\":[{\"id\":2,\"jan_amount\":null,\"jan_note\":null,\"feb_amount\":7,\"feb_note\":\"B\"},{\"id\":1,\"jan_amount\":5,\"jan_note\":null,\"feb_amount\":null,\"feb_note\":\"kept\"},{\"id\":2,\"jan_amount\":null,\"jan_note\":null,\"feb_amount\":7,\"feb_note\":\"B\"}]}"),
  )
}

///|
test "submitted multi-column UNPIVOT unpivot-multicolumn-pipe-include-fresh-range" {
  check_multicolumn_unpivot_source(
    "FROM (SELECT item.id AS id,item.jan_amount AS jan_amount,item.jan_note AS jan_note,item.feb_amount AS feb_amount,item.feb_note AS feb_note FROM UNNEST(@rows) item) original |> UNPIVOT INCLUDE NULLS ((amount,note) FOR month IN ((jan_amount,jan_note) AS 'Jan',(feb_amount,feb_note) AS 'Feb')) |> AS shaped |> SELECT shaped.id,shaped.amount,shaped.note,shaped.month |> ORDER BY id,month",
    Text,
    Some("{\"rows\":{\"type\":\"array\",\"nullable\":false,\"max_items\":3,\"items\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"jan_amount\":{\"type\":\"number\",\"nullable\":true},\"jan_note\":{\"type\":\"string\",\"nullable\":true},\"feb_amount\":{\"type\":\"number\",\"nullable\":true},\"feb_note\":{\"type\":\"string\",\"nullable\":true}}}}}"),
    Some("{\"rows\":[{\"id\":2,\"jan_amount\":null,\"jan_note\":null,\"feb_amount\":7,\"feb_note\":\"B\"},{\"id\":1,\"jan_amount\":5,\"jan_note\":null,\"feb_amount\":null,\"feb_note\":\"kept\"},{\"id\":2,\"jan_amount\":null,\"jan_note\":null,\"feb_amount\":7,\"feb_note\":\"B\"}]}"),
  )
}

///|
test "submitted multi-column UNPIVOT unpivot-multicolumn-default-labels" {
  check_multicolumn_unpivot_source(
    "FROM (SELECT item.id AS id,item.jan_amount AS jan_amount,item.jan_note AS jan_note,item.feb_amount AS feb_amount,item.feb_note AS feb_note FROM UNNEST(@rows) item) |> UNPIVOT ((amount,note) FOR month IN ((jan_amount,jan_note),(feb_amount,feb_note))) |> ORDER BY id,month",
    Text,
    Some("{\"rows\":{\"type\":\"array\",\"nullable\":false,\"max_items\":3,\"items\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"jan_amount\":{\"type\":\"number\",\"nullable\":true},\"jan_note\":{\"type\":\"string\",\"nullable\":true},\"feb_amount\":{\"type\":\"number\",\"nullable\":true},\"feb_note\":{\"type\":\"string\",\"nullable\":true}}}}}"),
    Some("{\"rows\":[{\"id\":2,\"jan_amount\":null,\"jan_note\":null,\"feb_amount\":7,\"feb_note\":\"B\"},{\"id\":1,\"jan_amount\":5,\"jan_note\":null,\"feb_amount\":null,\"feb_note\":\"kept\"},{\"id\":2,\"jan_amount\":null,\"jan_note\":null,\"feb_amount\":7,\"feb_note\":\"B\"}]}"),
  )
}

///|
test "submitted multi-column UNPIVOT unpivot-multicolumn-renamed-default-labels" {
  check_multicolumn_unpivot_source(
    "FROM (SELECT item.id AS id,item.jan_amount AS jan_amount,item.jan_note AS jan_note,item.feb_amount AS feb_amount,item.feb_note AS feb_note FROM UNNEST(@rows) item) |> RENAME jan_note AS first_note |> UNPIVOT ((amount,note) FOR month IN ((jan_amount,first_note),(feb_amount,feb_note))) |> ORDER BY id,month",
    Text,
    Some("{\"rows\":{\"type\":\"array\",\"nullable\":false,\"max_items\":3,\"items\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"jan_amount\":{\"type\":\"number\",\"nullable\":true},\"jan_note\":{\"type\":\"string\",\"nullable\":true},\"feb_amount\":{\"type\":\"number\",\"nullable\":true},\"feb_note\":{\"type\":\"string\",\"nullable\":true}}}}}"),
    Some("{\"rows\":[{\"id\":2,\"jan_amount\":null,\"jan_note\":null,\"feb_amount\":7,\"feb_note\":\"B\"},{\"id\":1,\"jan_amount\":5,\"jan_note\":null,\"feb_amount\":null,\"feb_note\":\"kept\"},{\"id\":2,\"jan_amount\":null,\"jan_note\":null,\"feb_amount\":7,\"feb_note\":\"B\"}]}"),
  )
}

///|
test "submitted multi-column UNPIVOT unpivot-multicolumn-typed-empty" {
  check_multicolumn_unpivot_source(
    "DATA wide = SELECT item.id AS id,item.jan_amount AS jan_amount,item.jan_note AS jan_note,item.feb_amount AS feb_amount,item.feb_note AS feb_note FROM UNNEST(@rows) item; SELECT id,amount,note,month FROM wide UNPIVOT ((amount,note) FOR month IN ((jan_amount,jan_note) AS 'Jan',(feb_amount,feb_note) AS 'Feb')) ORDER BY id,month",
    Text,
    Some("{\"rows\":{\"type\":\"array\",\"nullable\":false,\"max_items\":3,\"items\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"jan_amount\":{\"type\":\"number\",\"nullable\":true},\"jan_note\":{\"type\":\"string\",\"nullable\":true},\"feb_amount\":{\"type\":\"number\",\"nullable\":true},\"feb_note\":{\"type\":\"string\",\"nullable\":true}}}}}"),
    Some("{\"rows\":[]}"),
  )
}
