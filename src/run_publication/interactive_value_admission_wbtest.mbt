///|
test "interactive value admission retains wire shape and self identity checks" {
  let wire = "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"self_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"version\":\"actql-control-profile/0.1\"}"
  let value = parse_contract_wire(wire, 20000, 2000, 32, data_keys=true).unwrap()
  assert_true(
    admit_interactive_run_control_value(
      "control_profile", wire, value, 20000, 2000, 32,
    )
    is Ok(_),
  )
  let original = admit_run_evidence_value(
    "control_profile", wire, 20000, 2000, 32,
  ).unwrap()
  let admitted = admit_interactive_run_evidence_value(
    "control_profile", value, 20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(admitted),
    run_evidence_value_identity(original),
  )
  assert_eq(run_evidence_value_json(admitted), wire)
  assert_true(
    admit_interactive_run_control_value(
      "control_profile",
      " " + wire,
      value,
      20000,
      2000,
      32,
    )
    is Err(InvalidWire),
  )
  assert_true(
    admit_interactive_run_control_value(
      "control_profile",
      wire,
      value,
      wire.length() - 1,
      2000,
      32,
    )
    is Err(_),
  )
  assert_true(
    admit_interactive_run_evidence_value(
      "control_profile",
      value,
      wire.length() - 1,
      2000,
      32,
    )
    is Err(_),
  )
  let changed = @json.object_with_string_field(
    @json.object_without_field(value, "self_cid").unwrap(),
    "self_cid",
    "sha256:" + "0".repeat(64),
  ).unwrap()
  assert_true(
    admit_interactive_run_evidence_value(
      "control_profile", changed, 20000, 2000, 32,
    )
    is Err(RunEvidenceIdentityMismatch),
  )
  assert_true(
    admit_interactive_run_evidence_value(
      "run_definition", value, 20000, 2000, 32,
    )
    is Err(UnknownRunEvidence),
  )
}

///|
test "interactive admission cannot retain mutable source or detached collection aliases" {
  let wire = "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"self_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"version\":\"actql-control-profile/0.1\"}"
  let source = @source.parse_json(wire, {
    max_input_bytes: 20000,
    max_nodes: 2000,
    max_depth: 32,
  }).unwrap()
  let value = @json.from_source(source, 2000, 32, 20000, data_keys=true)
  let admitted = admit_interactive_run_evidence_value(
    "control_profile", value, 20000, 2000, 32,
  ).unwrap()
  match source.value {
    @source.Object(fields) => fields.clear()
    _ => fail("fixture root")
  }
  let detached = @json.object_fields(value).unwrap()
  detached.clear()
  let execution = @json.object_field(value, "execution").unwrap()
  guard @json.object_field(execution, "breakpoints")
    is Some(@json.Array(breakpoints)) else {
    fail("fixture array")
  }
  let detached_items = @json.array_values(breakpoints)
  detached_items.push(
    @json.from_json(Json::string("changed"), 1, 0, 100, data_keys=true),
  )
  assert_eq(@json.stringify_value(value, 20000, 2000, 32), wire)
  assert_eq(run_evidence_value_json(admitted), wire)
  assert_eq(
    run_evidence_value_identity(admitted),
    "sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50",
  )
}
