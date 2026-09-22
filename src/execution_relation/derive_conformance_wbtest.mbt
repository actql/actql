///|
fn derive_contract_owner(
  payload : @contract.Contract,
  ordered : Bool,
) -> @lower.BoundPrepared {
  let schema = @schema.from_fields(
    [(@schema.Unqualified("payload"), payload)],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(schema))
  let source = if ordered {
    "[{\"derive\":[{\"copy\":\"payload\"},{\"payload\":\"copy\"}]}]"
  } else {
    "[{\"derive\":{\"copy\":\"payload\"}}]"
  }
  let checked = @pipeline.check_with_evidence(
    input_cursor(source),
    [("seed", @pipeline.CarrierInput(carrier))],
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
fn run_derive_contract_value(
  owner : @lower.BoundPrepared,
  value : Value,
  ordered : Bool,
) -> Result[Table, RowIssue] {
  let kernel = row_kernel(owner, 0)
  let input : Table = {
    owner,
    id: @lower.kernel_input(kernel),
    names: ["payload"],
    rows: [[value]],
  }
  let control = { remaining: 100000, max_frames: 100, }
  let output = value_budget(run_limits().output_values).unwrap()
  let workspace = row_workspace(10000)
  if ordered {
    let logical = logical_budget(
      {
        max_input_rows: 1L,
        max_value_bytes: 10000L,
        max_live_value_bytes: 100000L,
        max_work: 100000L,
      },
      10000,
      1000,
      100,
    ).unwrap()
    evaluate_rows_with_workspace(
      kernel,
      input,
      1,
      control,
      output,
      workspace,
      ordered_budget=Some(logical),
    )
  } else {
    evaluate_rows_with_workspace(kernel, input, 1, control, output, workspace)
  }
}

///|
test "derive preserves every result domain across snapshot and ordered forms" {
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
    ("{\"type\":\"number\",\"nullable\":true}", "null", "ordinary"),
  ]
  for ordered in [false, true] {
    for (body, wire, kind) in cases {
      let contract = select_checked_contract(body)
      let live = Ref(true)
      let value = assertion_admitted_value(contract, wire, kind, live)
      let output = run_derive_contract_value(
        derive_contract_owner(contract, ordered),
        value,
        ordered,
      ).unwrap()
      assert_eq(output.names, ["payload", "copy"])
      assert_eq(output.rows.length(), 1)
      assert_true(append_value_equal(output.rows[0][0], value))
      assert_true(append_value_equal(output.rows[0][1], value))
      if kind != "ordinary" {
        guard output.rows[0][1] is Captured(@admitted.Reference(reference)) else {
          fail("derive lost owned reference")
        }
        assert_true(@admitted.reference_available(reference))
        live.val = false
        assert_false(@admitted.reference_available(reference))
      }
    }
  }
}
