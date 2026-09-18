///|
fn lag_domain_owner(
  payload : @contract.Contract,
  partition : @contract.Contract,
  order : @contract.Contract,
) -> @lower.BoundPrepared {
  let id = @contract.primitive(NumberType, nullable=false)
  let schema = @schema.from_fields(
    [
      (@schema.Unqualified("id"), id),
      (@schema.Unqualified("ord"), order),
      (@schema.Unqualified("part"), partition),
      (@schema.Unqualified("payload"), payload),
    ],
    max_fields=4,
    max_name_bytes=100,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(schema))
  let key = @evidence.declare_primary_key(input_cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 100,
  }).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"lag\":{\"partition_by\":[\"part\"]," +
      "\"order_by\":[{\"ord\":\"asc\"}],\"field\":\"payload\"," +
      "\"output\":\"previous\"}}]",
    ),
    [("seed", @pipeline.KeyedInput(key))],
    None,
    Some(input_cursor("\"seed\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn run_lag_domains(
  owner : @lower.BoundPrepared,
  rows : Array[Array[Value]],
) -> Table {
  let kernel = row_kernel(owner, 0)
  let input : Table = {
    owner,
    id: @lower.kernel_input(kernel),
    names: ["id", "ord", "part", "payload"],
    rows,
  }
  evaluate_lag_rows(
    kernel,
    input,
    "lagged",
    rows.length(),
    { remaining: 100000, max_frames: 100, },
    value_budget(run_limits().output_values).unwrap(),
    { limit: 10000, live: 0, peak: 0, },
  ).unwrap()
}

///|
fn lag_domain_value(
  body : String,
  wire : String,
  kind : String,
  live : Ref[Bool],
) -> (@contract.Contract, Value) {
  let contract = select_checked_contract(body)
  (contract, assertion_admitted_value(contract, wire, kind, live))
}

///|
fn lag_reference_lifetime(value : Value, live : Ref[Bool]) -> Unit raise {
  guard value is Captured(@admitted.Reference(reference)) else {
    fail("lag lost owned reference")
  }
  assert_true(@admitted.reference_available(reference))
  live.val = false
  assert_false(@admitted.reference_available(reference))
}

///|
test "lag preserves every result domain and owned-reference lifetime" {
  let cases = [
    ("{\"type\":\"string\",\"nullable\":true}", "\"é\"", "ordinary"),
    ("{\"type\":\"number\",\"nullable\":true}", "1", "ordinary"),
    (
      "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":true}", "\"1.20\"",
      "ordinary",
    ),
    ("{\"type\":\"boolean\",\"nullable\":true}", "true", "ordinary"),
    (
      "{\"type\":\"timestamp\",\"nullable\":true}", "\"2000-02-29T12:30:00.000Z\"",
      "ordinary",
    ),
    ("{\"type\":\"date\",\"nullable\":true}", "\"0000-02-29\"", "ordinary"),
    (
      "{\"type\":\"json\",\"nullable\":true}", "{\"z\":[1,null],\"a\":\"x\"}", "ordinary",
    ),
    (
      "{\"type\":\"object\",\"nullable\":true,\"additional_properties\":false,\"fields\":{\"x\":{\"type\":\"string\",\"nullable\":false}}}",
      "{\"x\":\"v\"}", "ordinary",
    ),
    (
      "{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"number\",\"nullable\":true},\"max_items\":2}",
      "[1,null]", "ordinary",
    ),
    (
      "{\"type\":\"vector\",\"nullable\":true,\"dimensions\":2,\"element_type\":\"f32\"}",
      "[1,2]", "ordinary",
    ),
    (
      "{\"type\":\"resource_ref\",\"nullable\":true,\"resource_kind\":\"mail/message\"}",
      "", "resource",
    ),
    (
      "{\"type\":\"artifact_ref\",\"nullable\":true,\"media_type\":\"application/json\"}",
      "", "artifact",
    ),
  ]
  let partition = select_checked_contract(
    "{\"type\":\"string\",\"nullable\":false}",
  )
  let order = select_checked_contract(
    "{\"type\":\"number\",\"nullable\":false}",
  )
  for (body, wire, kind) in cases {
    let live = Ref(true)
    let (payload, value) = lag_domain_value(body, wire, kind, live)
    let result = run_lag_domains(lag_domain_owner(payload, partition, order), [
      [Number(1), Number(1), Text("p"), value],
      [Number(2), Number(2), Text("p"), Null],
    ])
    assert_eq(result.names, ["id", "ord", "part", "payload", "previous"])
    assert_true(result.rows[0][4] is Null)
    assert_true(append_value_equal(result.rows[1][4], value))
    if kind != "ordinary" {
      lag_reference_lifetime(result.rows[1][4], live)
    }
  }
}

///|
test "lag partitions across every key-comparable domain" {
  let cases = [
    ("{\"type\":\"string\",\"nullable\":false}", "\"p\"", "ordinary"),
    ("{\"type\":\"number\",\"nullable\":false}", "1", "ordinary"),
    (
      "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":false}", "\"1.20\"",
      "ordinary",
    ),
    ("{\"type\":\"boolean\",\"nullable\":false}", "true", "ordinary"),
    (
      "{\"type\":\"timestamp\",\"nullable\":false}", "\"2000-02-29T12:30:00.000Z\"",
      "ordinary",
    ),
    ("{\"type\":\"date\",\"nullable\":false}", "\"0000-02-29\"", "ordinary"),
    (
      "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
      "", "resource",
    ),
    (
      "{\"type\":\"artifact_ref\",\"nullable\":false,\"media_type\":\"application/json\"}",
      "", "artifact",
    ),
  ]
  let payload = select_checked_contract(
    "{\"type\":\"number\",\"nullable\":false}",
  )
  let order = select_checked_contract(
    "{\"type\":\"number\",\"nullable\":false}",
  )
  for (body, wire, kind) in cases {
    let live = Ref(true)
    let (partition, value) = lag_domain_value(body, wire, kind, live)
    let result = run_lag_domains(lag_domain_owner(payload, partition, order), [
      [Number(1), Number(1), value, Number(10)],
      [Number(2), Number(2), value, Number(20)],
    ])
    assert_true(result.rows[0][4] is Null)
    assert_true(result.rows[1][4] is Number(10))
    if kind != "ordinary" {
      lag_reference_lifetime(result.rows[1][2], live)
    }
  }
}

///|
test "lag orders across every author-orderable domain" {
  let cases = [
    ("{\"type\":\"string\",\"nullable\":false}", "\"a\"", "\"b\""),
    ("{\"type\":\"number\",\"nullable\":false}", "1", "2"),
    (
      "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":false}", "\"1.00\"",
      "\"2.00\"",
    ),
    ("{\"type\":\"boolean\",\"nullable\":false}", "false", "true"),
    (
      "{\"type\":\"timestamp\",\"nullable\":false}", "\"2000-01-01T00:00:00.000Z\"",
      "\"2001-01-01T00:00:00.000Z\"",
    ),
    (
      "{\"type\":\"date\",\"nullable\":false}", "\"2000-01-01\"", "\"2001-01-01\"",
    ),
  ]
  let payload = select_checked_contract(
    "{\"type\":\"string\",\"nullable\":false}",
  )
  let partition = select_checked_contract(
    "{\"type\":\"number\",\"nullable\":false}",
  )
  for (body, first, second) in cases {
    let live = Ref(true)
    let (order, first_value) = lag_domain_value(body, first, "ordinary", live)
    let (_, second_value) = lag_domain_value(body, second, "ordinary", live)
    let result = run_lag_domains(lag_domain_owner(payload, partition, order), [
      [Number(1), first_value, Number(1), Text("first")],
      [Number(2), second_value, Number(1), Text("second")],
    ])
    assert_true(result.rows[0][4] is Null)
    assert_true(result.rows[1][4] is Text("first"))
  }
}
