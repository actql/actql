///|
fn limits() -> DescriptionLimits {
  {
    max_columns: 16,
    max_name_bytes: 4096,
    max_schema_bytes: 4096,
    max_nodes: 1000,
    max_depth: 16,
  }
}

///|
fn response_limits() -> @response.ResponseLimits {
  {
    max_bytes: 16384,
    max_nodes: 2000,
    max_depth: 16,
    max_columns: 16,
    max_name_units: 256,
    max_handle_units: 128,
    max_partitions: 4,
    max_rows: 16,
    max_total_rows: 16L,
  }
}

///|
fn target() -> TableTarget {
  table_target("PRODUCT", "USAGE", "USAGE_30D", 4096).unwrap()
}

///|
fn metadata_row(
  name : String,
  ordinal : Int,
  kind : String,
  nullable? : Bool = false,
  precision? : Int? = None,
  scale? : Int? = None,
  length? : Int? = None,
  database? : String = "PRODUCT",
  schema? : String = "USAGE",
  table? : String = "USAGE_30D",
) -> Json {
  Json::array([
    Json::string(database),
    Json::string(schema),
    Json::string(table),
    Json::string(name),
    Json::string(ordinal.to_string()),
    Json::string(if nullable { "YES" } else { "NO" }),
    Json::string(kind),
    match precision {
      Some(value) => Json::string(value.to_string())
      None => Json::null()
    },
    match scale {
      Some(value) => Json::string(value.to_string())
      None => Json::null()
    },
    match length {
      Some(value) => Json::string(value.to_string())
      None => Json::null()
    },
  ])
}

///|
fn hero_rows() -> Array[Json] {
  [
    metadata_row("ACCOUNT_ID", 1, "TEXT", length=Some(256)),
    metadata_row("ACTIVE_USERS", 2, "NUMBER", precision=Some(38), scale=Some(0)),
    metadata_row("TREND", 3, "TEXT", nullable=true, length=Some(32)),
  ]
}

///|
fn metadata_response(
  data : Array[Json],
  total? : Int = 3,
  partition_counts? : Array[Int] = [3],
) -> @response.ResultSet {
  let headers = [
    "TABLE_CATALOG", "TABLE_SCHEMA", "TABLE_NAME", "COLUMN_NAME", "ORDINAL_POSITION",
    "IS_NULLABLE", "DATA_TYPE", "NUMERIC_PRECISION", "NUMERIC_SCALE", "CHARACTER_MAXIMUM_LENGTH",
  ]
  let columns = []
  for index, name in headers {
    let numeric = [4, 7, 8, 9].contains(index)
    let fields : Map[String, Json] = Map([
      ("name", Json::string(name)),
      ("type", Json::string(if numeric { "FIXED" } else { "TEXT" })),
      ("nullable", Json::boolean(index >= 7)),
    ])
    if numeric {
      fields["precision"] = Json::number(38)
      fields["scale"] = Json::number(0)
    }
    columns.push(Json::object(fields))
  }
  let body = Json::object(
    Map([
      ("statementHandle", Json::string("description-original")),
      ("sqlState", Json::string("00000")),
      (
        "resultSetMetaData",
        Json::object(
          Map([
            ("format", Json::string("jsonv2")),
            ("numRows", total.to_json()),
            ("rowType", Json::array(columns)),
            (
              "partitionInfo",
              Json::array(
                partition_counts.map(value => {
                  Json::object(Map([("rowCount", value.to_json())]))
                }),
              ),
            ),
          ]),
        ),
      ),
      ("data", Json::array(data)),
    ]),
  )
  @response.project_result_set(
    @utf8.encode(body.stringify()),
    response_limits(),
  ).unwrap()
}

///|
fn description() -> TableDescription {
  project_table_description(
    target(),
    metadata_response(hero_rows()),
    [],
    limits(),
  ).unwrap()
}

///|
test "information schema keeps physical table and exact precision38 description" {
  let original = metadata_response(hero_rows())
  let selected = target()
  let value = project_table_description(selected, original, [], limits()).unwrap()
  assert_true(description_matches_target(value, selected))
  assert_true(description_matches_response(value, original))
  assert_false(description_matches_target(value, target()))
  assert_eq(description_column_count(value), 3)
  assert_eq(description_column_name(value, 0), Some("ACCOUNT_ID"))
  assert_eq(
    description_column_numeric_properties(value, 1),
    Some((Some(38L), Some(0L))),
  )
  assert_eq(description_column_nullable(value, 2), Some(true))
  assert_eq(description_column_max_characters(value, 0), Some(256L))
  assert_true(
    description_column_contract(value, 1).unwrap().shape
    is @contract.Decimal(precision=38, scale=0),
  )
}

///|
test "selected SQL order and independent canonical schema identity are distinct" {
  let material = description()
  let plan = prepare_read_projection(
    material,
    ["TREND", "ACCOUNT_ID", "ACTIVE_USERS"],
    limits(),
  ).unwrap()
  assert_true(read_projection_matches_description(plan, material))
  assert_false(read_projection_matches_description(plan, description()))
  assert_eq(
    read_projection_statement(plan),
    "SELECT \"TREND\",\"ACCOUNT_ID\",\"ACTIVE_USERS\" FROM \"PRODUCT\".\"USAGE\".\"USAGE_30D\"",
  )
  let (schema, cid) = read_projection_schema(plan)
  assert_eq(
    schema,
    (
      #|{"ACCOUNT_ID":{"nullable":false,"type":"string"},"ACTIVE_USERS":{"nullable":false,"precision":38,"scale":0,"type":"decimal"},"TREND":{"nullable":true,"type":"string"}}
    ),
  )
  // Independent fixed field-map bytes, hashed outside the product.
  assert_eq(
    cid, "sha256:156f4cca36cc640eb60268ce4786b7a24b78df17dc7a3d2be587ea5e282d7b95",
  )
  let fields = read_projection_fields(plan)
  fields[0] = "foreign"
  assert_eq(read_projection_fields(plan), [
    "TREND", "ACCOUNT_ID", "ACTIVE_USERS",
  ])
}

///|
test "existing Common owner issues the complete decimal relation declaration" {
  let plan = prepare_read_projection(
    description(),
    ["ACCOUNT_ID", "ACTIVE_USERS", "TREND"],
    limits(),
  ).unwrap()
  let declaration = generate_read_declaration(
    plan,
    "usage_30d",
    "snowflake-example",
    "snowflake/0.1",
    {
      max_bytes: 32768,
      max_nodes: 4000,
      max_depth: 32,
      max_views: 1,
      max_fields: 16,
    },
  ).unwrap()
  let declared = @rows.row_declaration_view(
    declaration, "connector://snowflake-example/usage_30d#records",
  ).unwrap()
  assert_eq(declared.fields, ["ACCOUNT_ID", "ACTIVE_USERS", "TREND"])
  let (schemas, capabilities) = @rows.row_declaration_evidence_members(
    declaration,
  )
  assert_eq(schemas.length(), 1)
  assert_eq(capabilities.length(), 1)
  assert_true(declaration.catalog.contains("\"precision\":38"))
  assert_true(declaration.catalog.contains("\"classification\":\"unknown\""))
  assert_true(
    generate_read_declaration(
      plan,
      "usage_30d",
      "snowflake-example",
      "other/0.1",
      {
        max_bytes: 32768,
        max_nodes: 4000,
        max_depth: 32,
        max_views: 1,
        max_fields: 16,
      },
    )
    is Err(_),
  )
}

///|
test "foreign database schema and table cannot reuse matching column shapes" {
  for
    row in [
      metadata_row("ACCOUNT_ID", 1, "TEXT", database="FOREIGN"),
      metadata_row("ACCOUNT_ID", 1, "TEXT", schema="FOREIGN"),
      metadata_row("ACCOUNT_ID", 1, "TEXT", table="FOREIGN"),
    ] {
    assert_true(
      project_table_description(
        target(),
        metadata_response([row], total=1, partition_counts=[1]),
        [],
        limits(),
      )
      is Err(ForeignTarget),
    )
  }
}

///|
test "partitions must be complete ordered and the same original response" {
  let data = hero_rows()
  let original = metadata_response([data[0]], partition_counts=[1, 1, 1])
  let second = @response.project_partition(
    @utf8.encode(
      Json::object(Map([("data", Json::array([data[1]]))])).stringify(),
    ),
    original,
    1,
    response_limits(),
  ).unwrap()
  let third = @response.project_partition(
    @utf8.encode(
      Json::object(Map([("data", Json::array([data[2]]))])).stringify(),
    ),
    original,
    2,
    response_limits(),
  ).unwrap()
  assert_true(
    project_table_description(target(), original, [second], limits())
    is Err(IncompleteDescription),
  )
  assert_true(
    project_table_description(target(), original, [third, second], limits())
    is Err(ForeignPartition),
  )
  assert_true(
    project_table_description(target(), original, [second, second], limits())
    is Err(ForeignPartition),
  )
  let foreign = metadata_response([data[0]], partition_counts=[1, 1, 1])
  assert_true(
    project_table_description(target(), foreign, [second, third], limits())
    is Err(ForeignPartition),
  )
  let parts = [second, third]
  let material = project_table_description(target(), original, parts, limits()).unwrap()
  parts.clear()
  assert_eq(description_response_count(material), 3)
  assert_eq(description_column_count(material), 3)
}

///|
test "ordinal gaps are not repaired but duplicate or reversed ordinals fail" {
  let good = [
    metadata_row("A", 1, "TEXT"),
    metadata_row("B", 3, "TEXT"),
    metadata_row("C", 8, "TEXT"),
  ]
  assert_true(
    project_table_description(target(), metadata_response(good), [], limits())
    is Ok(_),
  )
  for
    rows in [
      [metadata_row("A", 1, "TEXT"), metadata_row("B", 1, "TEXT")],
      [metadata_row("A", 2, "TEXT"), metadata_row("B", 1, "TEXT")],
    ] {
    assert_true(
      project_table_description(
        target(),
        metadata_response(rows, total=2, partition_counts=[2]),
        [],
        limits(),
      )
      is Err(InvalidColumn("B")),
    )
  }
}

///|
test "duplicate unknown and empty selections do not produce SQL" {
  let value = description()
  assert_true(
    prepare_read_projection(value, [], limits()) is Err(InvalidSelection),
  )
  assert_true(
    prepare_read_projection(value, ["ACCOUNT_ID", "ACCOUNT_ID"], limits())
    is Err(DuplicateColumn("ACCOUNT_ID")),
  )
  assert_true(
    prepare_read_projection(value, ["account_id"], limits())
    is Err(UnknownColumn("account_id")),
  )
  let duplicate = [metadata_row("A", 1, "TEXT"), metadata_row("A", 2, "TEXT")]
  assert_true(
    project_table_description(
      target(),
      metadata_response(duplicate, total=2, partition_counts=[2]),
      [],
      limits(),
    )
    is Err(DuplicateColumn("A")),
  )
}

///|
test "unsupported temporal binary columns stay explicit without disguising them" {
  for kind in ["DATE", "TIME", "TIMESTAMP_NTZ", "TIMESTAMP_TZ", "BINARY"] {
    let rows = [
      metadata_row("ACCOUNT_ID", 1, "TEXT"),
      metadata_row("UNFINISHED", 2, kind),
    ]
    let value = project_table_description(
      target(),
      metadata_response(rows, total=2, partition_counts=[2]),
      [],
      limits(),
    ).unwrap()
    assert_eq(description_column_type(value, 1), Some(kind))
    assert_true(description_column_contract(value, 1) is None)
    assert_true(
      match prepare_read_projection(value, ["UNFINISHED"], limits()) {
        Err(issue) => issue == UnsupportedType("UNFINISHED", kind)
        Ok(_) => false
      },
    )
    assert_true(
      prepare_read_projection(value, ["ACCOUNT_ID"], limits()) is Ok(_),
    )
  }
}

///|
test "numeric range and scale must be a Common exact contract" {
  for
    row in [
      metadata_row("N", 1, "NUMBER", precision=Some(0), scale=Some(0)),
      metadata_row("N", 1, "NUMBER", precision=Some(39), scale=Some(0)),
      metadata_row("N", 1, "NUMBER", precision=Some(4), scale=Some(5)),
      metadata_row("N", 1, "NUMBER", precision=Some(4)),
    ] {
    assert_true(
      project_table_description(
        target(),
        metadata_response([row], total=1, partition_counts=[1]),
        [],
        limits(),
      )
      is Err(InvalidColumn("N")),
    )
  }
  let float = metadata_row("F", 1, "FLOAT", precision=Some(53))
  let value = project_table_description(
    target(),
    metadata_response([float], total=1, partition_counts=[1]),
    [],
    limits(),
  ).unwrap()
  assert_true(
    description_column_contract(value, 0).unwrap().shape is @contract.Number,
  )
  assert_eq(
    description_column_numeric_properties(value, 0),
    Some((Some(53L), None)),
  )
}

///|
test "nullability is explicit metadata and not SQL NULL or absence" {
  let row = metadata_row("N", 1, "TEXT", nullable=true)
  let value = project_table_description(
    target(),
    metadata_response([row], total=1, partition_counts=[1]),
    [],
    limits(),
  ).unwrap()
  assert_true(description_column_contract(value, 0).unwrap().nullable)
  let missing = Json::array([
    Json::string("PRODUCT"),
    Json::string("USAGE"),
    Json::string("USAGE_30D"),
    Json::string("N"),
    Json::string("1"),
    Json::string("UNKNOWN"),
    Json::string("TEXT"),
    Json::null(),
    Json::null(),
    Json::null(),
  ])
  assert_true(
    project_table_description(
      target(),
      metadata_response([missing], total=1, partition_counts=[1]),
      [],
      limits(),
    )
    is Err(WrongDescriptionShape),
  )
}

///|
test "zero rows cannot claim an observed table exists or is readable" {
  assert_true(
    project_table_description(
      target(),
      metadata_response([], total=0, partition_counts=[0]),
      [],
      limits(),
    )
    is Err(IncompleteDescription),
  )
}

///|
test "caller limits are not enlarged by prior descriptor or provider sizes" {
  let original = metadata_response(hero_rows())
  let base = limits()
  assert_true(
    project_table_description(target(), original, [], {
      ..base,
      max_columns: 2,
    })
    is Err(DescriptionLimit),
  )
  assert_true(
    project_table_description(target(), original, [], {
      ..base,
      max_name_bytes: 3,
    })
    is Err(DescriptionLimit),
  )
  let value = description()
  assert_true(
    prepare_read_projection(value, ["ACCOUNT_ID"], { ..base, max_columns: 2, })
    is Err(InvalidSelection),
  )
  assert_true(
    prepare_read_projection(value, ["ACCOUNT_ID"], {
      ..base,
      max_name_bytes: 3,
    })
    is Err(DescriptionLimit),
  )
  assert_true(
    prepare_read_projection(value, ["ACCOUNT_ID"], {
      ..base,
      max_schema_bytes: 8,
    })
    is Err(DescriptionLimit),
  )
  assert_true(
    prepare_read_projection(value, ["ACCOUNT_ID"], { ..base, max_nodes: 1, })
    is Err(DescriptionLimit),
  )
  assert_true(
    prepare_read_projection(value, ["ACCOUNT_ID"], { ..base, max_depth: 1, })
    is Err(DescriptionLimit),
  )
}

///|
test "quoted physical names cannot become SQL syntax and Unicode stays exact" {
  let physical = table_target("P\";DROP TABLE x;--", "S", "T", 4096).unwrap()
  let row = metadata_row(
    "名\"",
    1,
    "TEXT",
    database="P\";DROP TABLE x;--",
    schema="S",
    table="T",
  )
  let value = project_table_description(
    physical,
    metadata_response([row], total=1, partition_counts=[1]),
    [],
    limits(),
  ).unwrap()
  let plan = prepare_read_projection(value, ["名\""], limits()).unwrap()
  assert_eq(
    read_projection_statement(plan),
    "SELECT \"名\"\"\" FROM \"P\"\";DROP TABLE x;--\".\"S\".\"T\"",
  )
  assert_eq(description_column_name(value, 0), Some("名\""))
  assert_true(table_target("P\u0000X", "S", "T", 4096) is Err(InvalidTarget))
}
