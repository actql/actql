///|
fn write_body_test_limits() -> WriteBodyLimits {
  { max_bytes: 1000, max_nodes: 20, max_depth: 2, }
}

///|
test "write body sorts exact fields and distinguishes omitted from null" {
  let (observation, binding) = write_test_observation()
  let with_optional = prepare_write_projection(
    observation,
    binding,
    "ActQL_Test_Record__c",
    WriteCreate,
    ["Optional_Value__c", "External_Key__c"],
    2,
  ).unwrap()
  let body = prepare_write_body(
    with_optional,
    @utf8.encode("{\"Optional_Value__c\":null,\"External_Key__c\":\"one\"}"),
    write_body_test_limits(),
  ).unwrap()
  assert_eq(
    write_body_json(body),
    "{\"External_Key__c\":\"one\",\"Optional_Value__c\":null}",
  )
  assert_eq(write_projection_fields(write_body_projection(body)), [
    "Optional_Value__c", "External_Key__c",
  ])
  let without_optional = prepare_write_projection(
    observation,
    binding,
    "ActQL_Test_Record__c",
    WriteCreate,
    ["External_Key__c"],
    1,
  ).unwrap()
  assert_eq(
    write_body_json(
      prepare_write_body(
        without_optional,
        @utf8.encode("{\"External_Key__c\":\"one\"}"),
        write_body_test_limits(),
      ).unwrap(),
    ),
    "{\"External_Key__c\":\"one\"}",
  )
  assert_true(
    prepare_write_body(
      with_optional,
      @utf8.encode("{\"External_Key__c\":\"one\"}"),
      write_body_test_limits(),
    )
    is Err(MissingField("Optional_Value__c")),
  )
}

///|
test "write body rejects foreign fields invalid values and undersized budgets" {
  let (observation, binding) = write_test_observation()
  let plan = prepare_write_projection(
    observation,
    binding,
    "ActQL_Test_Record__c",
    WriteUpdateById,
    ["Optional_Value__c"],
    1,
  ).unwrap()
  assert_true(
    prepare_write_body(
      plan,
      @utf8.encode("{\"Other__c\":\"x\"}"),
      write_body_test_limits(),
    )
    is Err(UnexpectedField("Other__c")),
  )
  assert_true(
    prepare_write_body(
      plan,
      @utf8.encode("{\"Optional_Value__c\":1}"),
      write_body_test_limits(),
    )
    is Err(InvalidValue("Optional_Value__c")),
  )
  assert_true(
    prepare_write_body(
      plan,
      @utf8.encode("{\"Optional_Value__c\":\"a\",\"Optional_Value__c\":\"b\"}"),
      write_body_test_limits(),
    )
    is Err(InvalidBody),
  )
  assert_true(
    prepare_write_body(plan, @utf8.encode("{\"Optional_Value__c\":\"x\"}"), {
      ..write_body_test_limits(),
      max_bytes: 2,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_write_body(plan, @utf8.encode("{\"Optional_Value__c\":\"x\"}"), {
      ..write_body_test_limits(),
      max_nodes: 1,
    })
    is Err(BudgetExceeded),
  )
}

///|
test "write body admits bounded boolean integer and finite double cells" {
  let binding = observation_test_binding()
  let description = @utf8.encode(
    (
      #|{"name":"ActQL_Test_Record__c","queryable":true,"createable":true,"updateable":true,"fields":[{"name":"Flag__c","type":"boolean","nillable":false,"createable":true,"updateable":true},{"name":"Count__c","type":"int","nillable":false,"createable":true,"updateable":true},{"name":"Score__c","type":"double","nillable":true,"createable":true,"updateable":true}]}
    ),
  )
  let observation = write_test_observation_with(description, binding)
  let plan = prepare_write_projection(
    observation,
    binding,
    "ActQL_Test_Record__c",
    WriteUpdateById,
    ["Score__c", "Count__c", "Flag__c"],
    3,
  ).unwrap()
  assert_eq(
    write_body_json(
      prepare_write_body(
        plan,
        @utf8.encode("{\"Score__c\":1.5,\"Flag__c\":true,\"Count__c\":3}"),
        write_body_test_limits(),
      ).unwrap(),
    ),
    "{\"Count__c\":3,\"Flag__c\":true,\"Score__c\":1.5}",
  )
  assert_true(
    prepare_write_body(
      plan,
      @utf8.encode(
        "{\"Score__c\":1.5,\"Flag__c\":true,\"Count__c\":2147483648}",
      ),
      write_body_test_limits(),
    )
    is Err(InvalidValue("Count__c")),
  )
  assert_true(
    prepare_write_body(
      plan,
      @utf8.encode("{\"Score__c\":1.5,\"Flag__c\":null,\"Count__c\":3}"),
      write_body_test_limits(),
    )
    is Err(NullNotAllowed("Flag__c")),
  )
}
