///|
fn limits() -> DescriptionLimits {
  {
    max_bytes: 16384,
    max_nodes: 2000,
    max_depth: 32,
    max_fields: 32,
    max_name_bytes: 4096,
    max_schema_bytes: 8192,
  }
}

///|
fn target() -> TableTarget {
  table_target("acme-project", "product", "usage", 1024).unwrap()
}

///|
fn field(
  name : String,
  kind : String,
  mode? : String? = None,
  precision? : Json? = None,
  scale? : Json? = None,
  max_length? : Json? = None,
  children? : Array[Json]? = None,
) -> Json {
  let values = Map([("name", name.to_json()), ("type", kind.to_json())])
  if mode is Some(value) {
    values["mode"] = value.to_json()
  }
  if precision is Some(value) {
    values["precision"] = value
  }
  if scale is Some(value) {
    values["scale"] = value
  }
  if max_length is Some(value) {
    values["maxLength"] = value
  }
  if children is Some(value) {
    values["fields"] = value.to_json()
  }
  Json::object(values)
}

///|
fn body(
  fields : Array[Json],
  project? : String = "acme-project",
  dataset? : String = "product",
  table? : String = "usage",
  key? : Array[String]? = None,
) -> Bytes {
  let value = Map([
    ("kind", "bigquery#table".to_json()),
    ("etag", "original-etag".to_json()),
    ("type", "TABLE".to_json()),
    (
      "tableReference",
      Json::object(
        Map([
          ("projectId", project.to_json()),
          ("datasetId", dataset.to_json()),
          ("tableId", table.to_json()),
        ]),
      ),
    ),
    ("schema", Json::object(Map([("fields", fields.to_json())]))),
    // Actual tables.get has other output fields. Ignoring unused descriptive
    // metadata is not permission to ignore an invalid used type or target.
    ("creationTime", "1700000000000".to_json()),
  ])
  if key is Some(columns) {
    value["tableConstraints"] = Json::object(
      Map([("primaryKey", Json::object(Map([("columns", columns.to_json())])))]),
    )
  }
  @utf8.encode(Json::object(value).stringify())
}

///|
fn describe(fields : Array[Json]) -> TableDescription {
  project_table_description(target(), body(fields), limits()).unwrap()
}

///|
fn hero() -> Array[Json] {
  [
    field("account_id", "STRING", mode=Some("REQUIRED")),
    field("sessions_30d", "NUMERIC", precision=Some("29".to_json())),
    field("trend", "STRING"),
  ]
}

///|
test "metadata binds the exact project dataset table and response observation" {
  let selected = target()
  let raw = body(hero())
  let value = project_table_description(selected, raw, limits()).unwrap()
  assert_true(description_matches_target(value, selected))
  assert_false(description_matches_target(value, target()))
  assert_eq(
    description_original(value),
    ("original-etag", "TABLE", @sha.hex(raw)),
  )
  assert_eq(description_column_count(value), 3)
  assert_eq(column_name(description_column(value, 0).unwrap()), "account_id")
  assert_eq(column_mode(description_column(value, 0).unwrap()), "REQUIRED")
  assert_eq(column_mode(description_column(value, 2).unwrap()), "NULLABLE")
  assert_true(description_column(value, -1) is None)
  assert_true(description_column(value, 3) is None)
  for
    raw in [
      body(hero(), project="other"),
      body(hero(), dataset="other"),
      body(hero(), table="other"),
    ] {
    assert_true(
      project_table_description(selected, raw, limits()) is Err(ForeignTarget),
    )
  }
}

///|
test "selected field order and Common canonical schema order are distinct" {
  let value = describe(hero())
  let projection = prepare_read_projection(
    value,
    ["trend", "sessions_30d", "account_id"],
    limits(),
  ).unwrap()
  assert_true(read_projection_matches_description(projection, value))
  assert_false(
    read_projection_matches_description(projection, describe(hero())),
  )
  let (wire, cid) = read_projection_schema(projection)
  assert_eq(
    wire,
    (
      #|{"account_id":{"nullable":false,"type":"string"},"sessions_30d":{"nullable":true,"precision":29,"scale":0,"type":"decimal"},"trend":{"nullable":true,"type":"string"}}
    ),
  )
  // Independently fixed canonical bytes; digest pinned outside the product.
  assert_eq(
    cid, "sha256:dd8e6277969bc5e4c50bc0a74c17500f21ff004bf2e8b7f43c6f544f9d9415af",
  )
  let copied = read_projection_fields(projection)
  copied[0] = "foreign"
  assert_eq(read_projection_fields(projection), [
    "trend", "sessions_30d", "account_id",
  ])
}

///|
test "existing Common row declaration owns schema and Catalog issuance" {
  let value = describe(hero())
  let projection = prepare_read_projection(
    value,
    ["account_id", "sessions_30d", "trend"],
    limits(),
  ).unwrap()
  let declaration = generate_read_declaration(
    projection,
    "usage",
    "bq-example",
    "bigquery/0.1",
    {
      max_bytes: 32768,
      max_nodes: 4000,
      max_depth: 32,
      max_views: 1,
      max_fields: 32,
    },
  ).unwrap()
  let view = @rows.row_declaration_view(
    declaration, "connector://bq-example/usage#records",
  ).unwrap()
  assert_eq(view.fields, ["account_id", "sessions_30d", "trend"])
  let (schemas, capabilities) = @rows.row_declaration_evidence_members(
    declaration,
  )
  assert_eq(schemas.length(), 1)
  assert_eq(capabilities.length(), 1)
  assert_true(declaration.catalog.contains("\"precision\":29"))
  assert_true(declaration.catalog.contains("\"classification\":\"unknown\""))
  assert_false(declaration.catalog.contains("\"unique\":true"))
}

///|
test "unenforced primary keys remain claims and defensive data copies" {
  let value = project_table_description(
    target(),
    body(hero(), key=Some(["account_id"])),
    limits(),
  ).unwrap()
  let key = description_declared_key(value)
  key[0] = "foreign"
  assert_eq(description_declared_key(value), ["account_id"])
  for keys in [[], ["missing"], ["account_id", "account_id"]] {
    assert_true(
      project_table_description(
        target(),
        body(hero(), key=Some(keys)),
        limits(),
      )
      is Err(InvalidDeclaredKey),
    )
  }
}

///|
test "NUMERIC defaults and parameterized precision are exact" {
  let value = describe([
    field("default", "NUMERIC"),
    field(
      "scaled",
      "DECIMAL",
      precision=Some("32".to_json()),
      scale=Some("3".to_json()),
    ),
    field(
      "big_but_fits",
      "BIGNUMERIC",
      precision=Some("38".to_json()),
      scale=Some("10".to_json()),
    ),
  ])
  assert_true(
    column_contract(description_column(value, 0).unwrap()).unwrap().shape
    is @contract.Decimal(precision=38, scale=9),
  )
  assert_true(
    column_contract(description_column(value, 1).unwrap()).unwrap().shape
    is @contract.Decimal(precision=32, scale=3),
  )
  assert_true(
    column_contract(description_column(value, 2).unwrap()).unwrap().shape
    is @contract.Decimal(precision=38, scale=10),
  )
  assert_eq(
    column_constraints(description_column(value, 0).unwrap()),
    (None, None, None, None),
  )
}

///|
test "invalid decimal metadata is refused before contract issuance" {
  let cases = [
    field("bad", "NUMERIC", scale=Some("1".to_json())),
    field("bad", "NUMERIC", precision=Some("0".to_json())),
    field("bad", "NUMERIC", precision=Some("30".to_json())),
    field(
      "bad",
      "NUMERIC",
      precision=Some("39".to_json()),
      scale=Some("10".to_json()),
    ),
    field(
      "bad",
      "NUMERIC",
      precision=Some("8".to_json()),
      scale=Some("9".to_json()),
    ),
    field(
      "bad",
      "BIGNUMERIC",
      precision=Some("77".to_json()),
      scale=Some("38".to_json()),
    ),
    field("bad", "NUMERIC", precision=Some(Json::number(29))),
    field("bad", "NUMERIC", precision=Some(Json::boolean(true))),
    field("bad", "NUMERIC", precision=Some("-0".to_json())),
    field("bad", "NUMERIC", precision=Some("029".to_json())),
    field("bad", "NUMERIC", precision=Some("9223372036854775808".to_json())),
    field("bad", "STRING", precision=Some("2".to_json())),
  ]
  for value in cases {
    assert_true(
      project_table_description(target(), body([value]), limits())
      is Err(InvalidColumn("bad")),
    )
  }
}

///|
test "missing lossless carriers stay explicit and never become string or float" {
  for
    kind in [
      "INTEGER", "INT64", "BYTES", "TIME", "DATETIME", "TIMESTAMP", "BIGNUMERIC",
      "GEOGRAPHY", "INTERVAL", "RANGE", "future-provider-type",
    ] {
    let value = describe([field("value", kind)])
    assert_eq(column_type(description_column(value, 0).unwrap()), kind)
    assert_true(column_contract(description_column(value, 0).unwrap()) is None)
    assert_true(
      prepare_read_projection(value, ["value"], limits())
      is Err(UnsupportedColumn("value", _)),
    )
  }
  let value = describe([
    field(
      "large",
      "BIGNUMERIC",
      precision=Some("76".to_json()),
      scale=Some("38".to_json()),
    ),
  ])
  assert_true(
    prepare_read_projection(value, ["large"], limits())
    is Err(UnsupportedColumn("large", "BIGNUMERIC")),
  )
}

///|
test "record and repeated fields retain nested nullability" {
  let value = describe([
    field(
      "record",
      "RECORD",
      children=Some([
        field("required", "BOOL", mode=Some("REQUIRED")),
        field("optional", "STRING"),
        field("tags", "STRING", mode=Some("REPEATED")),
      ]),
    ),
  ])
  let column = description_column(value, 0).unwrap()
  let children = column_children(column)
  assert_eq(children.length(), 3)
  assert_eq(column_mode(children[2]), "REPEATED")
  let projection = prepare_read_projection(value, ["record"], limits()).unwrap()
  assert_eq(
    read_projection_schema(projection).0,
    (
      #|{"record":{"additional_properties":false,"fields":{"optional":{"nullable":true,"type":"string"},"required":{"nullable":false,"type":"boolean"},"tags":{"items":{"nullable":false,"type":"string"},"nullable":false,"type":"array"}},"nullable":true,"type":"object"}}
    ),
  )
  children[0] = children[1]
  assert_eq(column_name(column_children(column)[0]), "required")
}

///|
test "nested unsupported fields cannot issue a partial record schema" {
  let value = describe([
    field(
      "record",
      "STRUCT",
      mode=Some("REPEATED"),
      children=Some([field("good", "STRING"), field("large", "INT64")]),
    ),
  ])
  assert_true(column_contract(description_column(value, 0).unwrap()) is None)
  assert_true(
    prepare_read_projection(value, ["record"], limits())
    is Err(UnsupportedColumn("record", "STRUCT")),
  )
}

///|
test "provider maxLength is retained without inventing a length unit or write proof" {
  let value = describe([
    field("text", "STRING", max_length=Some("20".to_json())),
  ])
  assert_eq(
    column_constraints(description_column(value, 0).unwrap()),
    (None, None, Some(20L), None),
  )
  assert_true(
    column_contract(description_column(value, 0).unwrap()).unwrap().shape
    is @contract.Text(_),
  )
  for
    value in [
      field("bad", "STRING", max_length=Some("0".to_json())),
      field("bad", "BOOL", max_length=Some("20".to_json())),
    ] {
    assert_true(
      project_table_description(target(), body([value]), limits())
      is Err(InvalidColumn("bad")),
    )
  }
}

///|
test "duplicate field names are refused at every nesting level" {
  for
    fields in [
      [field("same", "STRING"), field("same", "BOOL")],
      [
        field(
          "parent",
          "RECORD",
          children=Some([field("same", "STRING"), field("same", "STRING")]),
        ),
      ],
    ] {
    assert_true(
      project_table_description(target(), body(fields), limits())
      is Err(DuplicateColumn("same")),
    )
  }
}

///|
test "unsupported column need not corrupt an independent selected supported column" {
  let value = describe([
    field("supported", "STRING"),
    field("unavailable", "INT64"),
  ])
  assert_true(prepare_read_projection(value, ["supported"], limits()) is Ok(_))
  assert_true(
    prepare_read_projection(value, ["supported", "unavailable"], limits())
    is Err(UnsupportedColumn("unavailable", "INT64")),
  )
}

///|
test "used metadata null or contradictory fields do not become omitted defaults" {
  for
    value in [
      field("bad", "STRING", mode=Some("nullable")),
      field("bad", "STRING", children=Some([])),
      field("bad", "RECORD"),
      field("bad", "STRING", max_length=Some(Json::null())),
    ] {
    assert_true(
      project_table_description(target(), body([value]), limits()) is Err(_),
    )
  }
  let invalid = @utf8.encode(
    (
      #|{"kind":"bigquery#table","etag":"a","type":"TABLE","tableReference":{"projectId":"acme-project","datasetId":"product","tableId":"usage"},"schema":{"fields":[{"name":"a","type":"STRING","mode":null}]}}
    ),
  )
  assert_true(
    project_table_description(target(), invalid, limits())
    is Err(InvalidColumn("a")),
  )
}

///|
test "source duplicate JSON keys are refused rather than last-wins" {
  let raw = @utf8.encode(
    (
      #|{"kind":"bigquery#table","etag":"a","etag":"b","type":"TABLE","tableReference":{"projectId":"acme-project","datasetId":"product","tableId":"usage"},"schema":{"fields":[]}}
    ),
  )
  assert_true(
    project_table_description(target(), raw, limits()) is Err(InvalidResponse),
  )
}

///|
test "bounded input nodes names and aggregate nested fields refuse before output" {
  let raw = body(hero())
  assert_true(
    project_table_description(target(), raw, {
      ..limits(),
      max_bytes: raw.length() - 1,
    })
    is Err(DescriptionLimit),
  )
  assert_true(
    project_table_description(target(), raw, { ..limits(), max_nodes: 3, })
    is Err(DescriptionLimit),
  )
  assert_true(
    project_table_description(target(), raw, { ..limits(), max_name_bytes: 3, })
    is Err(DescriptionLimit),
  )
  assert_true(
    project_table_description(target(), raw, { ..limits(), max_fields: 2, })
    is Err(DescriptionLimit),
  )
  let nested = body([
    field(
      "parent",
      "RECORD",
      children=Some([field("a", "STRING"), field("b", "STRING")]),
    ),
  ])
  assert_true(
    project_table_description(target(), nested, { ..limits(), max_fields: 2, })
    is Err(DescriptionLimit),
  )
  assert_true(
    project_table_description(target(), nested, { ..limits(), max_depth: 3, })
    is Err(DescriptionLimit),
  )
  assert_true(
    prepare_read_projection(describe(hero()), ["account_id"], {
      ..limits(),
      max_schema_bytes: 3,
    })
    is Err(DescriptionLimit),
  )
}

///|
test "target Unicode is exact bounded and never normalized" {
  assert_true(table_target("", "d", "t", 30) is Err(InvalidTarget))
  assert_true(table_target("p", "d", "\u0000", 30) is Err(InvalidTarget))
  assert_true(table_target("p", "d", "😀", 5) is Err(InvalidTarget))
  let selected = table_target("p", "d", "😀", 6).unwrap()
  let value = project_table_description(
    selected,
    body([field("列", "STRING")], project="p", dataset="d", table="😀"),
    limits(),
  ).unwrap()
  assert_true(description_matches_target(value, selected))
  assert_eq(column_name(description_column(value, 0).unwrap()), "列")
}

///|
test "selected names use the existing Common canonical name law" {
  let value = describe([
    field("é", "STRING"),
    field("é", "STRING"),
    field("a.b", "STRING"),
  ])
  assert_true(prepare_read_projection(value, ["é"], limits()) is Ok(_))
  assert_true(
    prepare_read_projection(value, ["é"], limits()) is Err(InvalidContract(_)),
  )
  assert_true(
    prepare_read_projection(value, ["a.b"], limits()) is Err(InvalidContract(_)),
  )
}

///|
test "empty foreign and duplicate selections do not issue declaration candidates" {
  let value = describe(hero())
  assert_true(
    prepare_read_projection(value, [], limits()) is Err(InvalidSelection),
  )
  assert_true(
    prepare_read_projection(value, ["missing"], limits())
    is Err(UnknownColumn("missing")),
  )
  assert_true(
    prepare_read_projection(value, ["trend", "trend"], limits())
    is Err(DuplicateColumn("trend")),
  )
}

///|
test "collation remains provider metadata without granting comparison pushdown" {
  let value = field("text", "STRING")
  guard value is Object(fields) else { abort("fixture object required") }
  fields["collation"] = "und:ci".to_json()
  let described = describe([Json::object(fields)])
  assert_eq(
    column_constraints(description_column(described, 0).unwrap()),
    (None, None, None, Some("und:ci")),
  )
  fields["type"] = "BOOL".to_json()
  assert_true(
    project_table_description(target(), body([Json::object(fields)]), limits())
    is Err(InvalidColumn("text")),
  )
}

///|
test "parameterized SQL decimal permits zero integer digits without widening" {
  // GoogleSQL's semantic type range is max(1,S) <= P <= S+29/S+38.
  // The REST field reference's stricter P-S >= 1 disagrees at P=S. Keep an
  // independent counter instead of inheriting either current implementation.
  let value = describe([
    field(
      "fraction",
      "NUMERIC",
      precision=Some("9".to_json()),
      scale=Some("9".to_json()),
    ),
    field(
      "big_fraction",
      "BIGNUMERIC",
      precision=Some("38".to_json()),
      scale=Some("38".to_json()),
    ),
  ])
  assert_true(
    column_contract(description_column(value, 0).unwrap()).unwrap().shape
    is @contract.Decimal(precision=9, scale=9),
  )
  assert_true(
    column_contract(description_column(value, 1).unwrap()).unwrap().shape
    is @contract.Decimal(precision=38, scale=38),
  )
}
