///|
fn unpivot_domain_owner(payload : @contract.Contract) -> @lower.BoundPrepared {
  let id = @contract.primitive(NumberType, nullable=false)
  let schema = @schema.from_fields(
    [
      (@schema.Unqualified("id"), id),
      (@schema.Unqualified("a"), payload),
      (@schema.Unqualified("b"), payload),
    ],
    max_fields=3,
    max_name_bytes=100,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(schema))
  let key = @evidence.declare_primary_key(input_cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 100,
  }).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"unpivot\":{\"columns\":[\"a\",\"b\"]," +
      "\"keep\":[\"id\"],\"name_column\":\"metric\"," +
      "\"value_column\":\"value\"}}]",
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
fn unpivot_admitted_value(
  contract : @contract.Contract,
  wire : String,
  kind : String,
  live : Ref[Bool],
) -> @admitted.Value {
  match kind {
    "resource" =>
      issued_resource_value(
        contract, "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
        live,
      ).value
    "artifact" => issued_artifact_value(contract, live).value
    _ =>
      @admitted.admit(contract, input_cursor(wire), {
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 1000,
      }).unwrap().value
  }
}

///|
fn unpivot_domain_column(names : Array[String], wanted : String) -> Int {
  for index, name in names {
    if name == wanted {
      return index
    }
  }
  abort("unpivot output column")
}

///|
test "unpivot expands every relation value domain into sealed columns" {
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
  for (body, wire, kind) in cases {
    let payload = select_checked_contract(body)
    let owner = unpivot_domain_owner(payload)
    let kernel = row_kernel(owner, 0)
    let schema = @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      Input(0),
    ).unwrap()
    let names = Array::makei(@schema.field_count(schema), i => {
      @schema.reference_name(@schema.field_at(schema, i).unwrap().name)
    })
    let live = Ref(true)
    let value = unpivot_admitted_value(payload, wire, kind, live)
    let null = @admitted.admit(payload, input_cursor("null"), {
        max_nodes: 1,
        max_depth: 0,
        max_text_bytes: 0,
      }).unwrap().value
    let id = @admitted.number_value(1).unwrap()
    let row = names.map(name => {
      match name {
        "a" => value
        "b" => null
        "id" => id
        _ => abort("unpivot input column")
      }
    })
    let input : CompletedTable = AdmittedTable({
      owner,
      id: @lower.kernel_input(kernel),
      names,
      rows: [row],
    })
    let result = evaluate_completed_rows(
      kernel,
      input,
      2,
      { remaining: 100000, max_frames: 100, },
      value_budget(run_limits().output_values).unwrap(),
      { limit: 10000, live: 0, peak: 0, },
      None,
    ).unwrap()
    guard result is ColumnTable(table) else {
      fail("unpivot materialized row storage")
    }
    assert_eq(table.count, 2)
    let metric = unpivot_domain_column(table.names, "metric")
    let output = unpivot_domain_column(table.names, "value")
    assert_true(IndexedRows::read_cell(result, 0, metric) is Text("a"))
    assert_true(IndexedRows::read_cell(result, 1, metric) is Text("b"))
    assert_true(
      append_value_equal(
        IndexedRows::read_cell(result, 0, output),
        capture(value),
      ),
    )
    assert_true(IndexedRows::read_cell(result, 1, output) is Null)
    let output_schema = @lower.kernel_output_schema(kernel)
    let output_contract = @schema.lookup_reference(output_schema, "value").unwrap().contract
    assert_true(@contract.type_equal(output_contract, payload, 100))
    if kind != "ordinary" {
      guard IndexedRows::read_cell(result, 0, output)
        is Captured(@admitted.Reference(reference)) else {
        fail("unpivot lost owned reference")
      }
      assert_true(@admitted.reference_available(reference))
      live.val = false
      assert_false(@admitted.reference_available(reference))
    }
  }
}
