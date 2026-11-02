///|
fn sf_initialization_test_limits() -> DescribeLimits {
  {
    max_bytes: 4000000,
    max_nodes: 400000,
    max_depth: 32,
    max_fields: 1000,
    max_name_units: 200000,
  }
}

///|
fn sf_initialization_test_quote(
  body : String,
  max_fields? : Int = 1000,
) -> @execution.ExecutionCapacity {
  let bytes = @utf8.encode(body).length()
  initialization_construction_capacity(
    [bytes],
    4 * ((bytes + 2) / 3),
    2000,
    [9],
    3000,
    8,
    14,
    { ..sf_initialization_test_limits(), max_fields, },
    8000000,
    { max_bytes: 4000000, max_nodes: 400000, max_depth: 64, },
  ).unwrap()
}

///|
test "Salesforce original Describe static declaration quote uses actual input not maxFields" {
  let body = declared_record_describe()
  let quote = sf_initialization_test_quote(body)
  let peak = @execution.execution_capacity_execution_bytes(quote)
  println(
    "Salesforce static constructor body_bytes=\{@utf8.encode(body).length()} peak_bytes=\{peak}",
  )
  // A Source uses provider and Common restoration independently. Both fit
  // the unchanged operator budget, before the remaining common stages.
  assert_true(2L * peak < 536870912L)
  assert_eq(@execution.execution_capacity_retained_bytes(quote), peak)
  assert_eq(
    @execution.execution_capacity_execution_bytes(
      sf_initialization_test_quote(body, max_fields=10000),
    ),
    peak,
  )
  let declaration = declared_for(body)
  assert_true(declaration.writables.length() > 0)
  assert_true(declaration.exclusions.length() > 0)
  assert_true(
    static_declaration_json(declaration, declaration_limits()) is Some(_),
  )
}

///|
test "Salesforce quote covers ten-role Address and malformed Describe prefixes" {
  let body = address_describe(codes=true)
  assert_true(
    @execution.execution_capacity_execution_bytes(
      sf_initialization_test_quote(body),
    ) <
    268435456L,
  )
  let declaration = declared_for(body)
  assert_true(declaration.catalog.contains("countryCode"))
  assert_true(declaration.catalog.contains("geocodeAccuracy"))
  assert_true(declaration.catalog.contains("\"precision\":18"))
  let bad = "{\"name\":\"Record__c\",\"fields\":[{\"name\":\"First\",\"type\":\"string\"},{\"name\":\"Second\",\"type\":\"double\",\"precision\":\"bad\"}]}"
  assert_true(
    @execution.execution_capacity_execution_bytes(
      sf_initialization_test_quote(bad),
    ) >
    0L,
  )
  assert_true(
    project_describe(
      @utf8.encode(bad),
      "Record__c",
      sf_initialization_test_limits(),
    )
    is Err(_),
  )
  assert_true(
    initialization_construction_capacity(
      [-1],
      0,
      0,
      [9],
      0,
      8,
      14,
      sf_initialization_test_limits(),
      8000000,
      declaration_limits(),
    )
    is None,
  )
  // Writer failure happens after metadata/raw schema allocation: its quote
  // remains nonzero and metadata-dependent even with one-byte emitters.
  let tiny = initialization_construction_capacity(
    [body.length()],
    0,
    2000,
    [9],
    3000,
    8,
    14,
    sf_initialization_test_limits(),
    8000000,
    { max_bytes: 1, max_nodes: 1, max_depth: 1, },
  ).unwrap()
  assert_true(@execution.execution_capacity_execution_bytes(tiny) > 100000L)
}

///|
test "Salesforce execution mapping quote preserves actual result and external key producers" {
  let body = declared_record_describe()
  let source_units = "Name".length() +
    "result_name".length() +
    "write_null".length() +
    "External_Key__c".length() +
    "external_key".length() +
    "reject".length()
  let quote = execution_mapping_construction_capacity(
    0,
    0,
    2,
    source_units,
    0,
    9,
    8,
    14,
    body.length(),
    1000,
    declaration_limits(),
  ).unwrap()
  println(
    "Salesforce execution mapping peak_bytes=\{@execution.execution_capacity_execution_bytes(quote)}",
  )
  assert_true(@execution.execution_capacity_execution_bytes(quote) < 536870912L)
  let declaration = declared_for(body)
  let mapped = execution(
    declaration,
    CreateFromResult([
      { target: "Name", source: "result_name", null_behavior: "write_null", },
      {
        target: "External_Key__c",
        source: "external_key",
        null_behavior: "reject",
      },
    ]),
  ).unwrap()
  assert_true(mapped.body.contains("row_mapping"))
  assert_true(
    execution_mapping_construction_capacity(
      1,
      "Name".length(),
      0,
      0,
      "External_Key__c".length(),
      9,
      8,
      14,
      body.length(),
      1000,
      declaration_limits(),
    )
    is Some(_),
  )
  let upsert = execution(
    declaration,
    UpsertByExternalId("External_Key__c", ["Name"]),
  ).unwrap()
  assert_true(upsert.body.contains("External_Key__c"))
}
