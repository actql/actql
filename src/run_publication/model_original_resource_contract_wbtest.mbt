///|
fn original_resource_binding_shape_fixture() -> String {
  // Original independent 406-byte resource fixture. No candidate Writer,
  // installation aggregate, restoration issuer or send permission is used.
  let state = "[\"actql-original-ledger-state/0.1\",[\"17\",\"2\",\"3\",\"11\",\"10\",\"7\"],[\"17\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"10\",\"7\",\"10\",\"0\",\"2\",\"0\"],[\"0\",\"0\",\"0\"],null,[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]],[\"-3\",\"0\",\"0\"],[\"1\",\"0\",\"0\",true,true,false,\"reading\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false]],[],[]]"
  let cid = "sha256:" + "1".repeat(64)
  let fields = [
    "run_definition_cid", "prepared_invocation_cid", "host_policy_cid", "execution_context_cid",
    "program_definition_cid", "parameter_values_cid", "barrier_cid", "runtime_artifact_cid",
    "layout_artifact_cid", "response_profile_cid", "storage_binding_cid",
  ]
  let origin = "{\"run_id\":\"original-é\\r\\n\"," +
    fields.map(name => "\"" + name + "\":\"" + cid + "\"").join(",") +
    "}"
  "{\"version\":\"actql-model-original-resource-state/0.1\",\"origin\":" +
  origin +
  ",\"resource_state\":" +
  state +
  ",\"resource_state_cid\":\"sha256:7ed6db2394d7eaa87d65b022a6bc78f722efaf7a0293115de52c09a89893aae9\",\"resource_phase\":\"preparation_base\",\"cut\":null}"
}

///|
fn original_resource_binding_shape(wire : String) -> Bool {
  let value = match parse_contract_wire(wire, 10000, 1000, 16, data_keys=true) {
    Ok(value) => value
    Err(_) => return false
  }
  validate_generated_protocol_shape(
    "model_original_resource_state", value, true, 10000, 1000, 16,
  )
}

///|
test "original resource registered shape accepts exact saved record and preserves raw origin" {
  let wire = original_resource_binding_shape_fixture()
  assert_true(original_resource_binding_shape(wire))
  let value = parse_contract_wire(wire, 10000, 1000, 16, data_keys=true).unwrap()
  let origin = @json.object_field(value, "origin").unwrap()
  assert_eq(
    optional_string(@json.object_field(origin, "run_id")),
    Some("original-é\r\n"),
  )
  // A valid data shape is explicitly NOT an authenticated resource restoration.
  assert_eq(
    generated_protocol_schema_root("model_original_resource_state", false),
    None,
  )
}

///|
test "original resource registered shape refuses extra fields and wrong positional types" {
  let wire = original_resource_binding_shape_fixture()
  for
    changed in [
      wire.replace(
        old="\"cut\":null",
        new="\"cut\":null,\"self_cid\":\"sha256:" + "1".repeat(64) + "\"",
      ),
      wire.replace(
        old="\"run_id\":\"original-é\\r\\n\"",
        new="\"run_id\":null",
      ),
      wire.replace(
        old="[\"17\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"10\",\"7\",\"10\",\"0\",\"2\",\"0\"]",
        new="[\"17\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"10\",\"7\",\"10\"]",
      ),
      wire.replace(old="[\"-3\",\"0\",\"0\"]", new="\"-3\""),
      wire.replace(old=",null,false,false]", new=",null]"),
      wire.replace(old="\"-3\"", new="-3"),
      wire.replace(old="\"-3\"", new="\"-0\""),
      wire.replace(old="\"-3\"", new="\"-03\""),
      wire.replace(
        old="true,true,false,\"reading\",true",
        new="true,true,false,\"reading\",true,null",
      ),
    ] {
    assert_true(!original_resource_binding_shape(changed))
  }
}

///|
test "original resource registered shape does not promote preparation basis to current cut" {
  let wire = original_resource_binding_shape_fixture()
  for phase in ["parked", "stopping"] {
    assert_true(
      !original_resource_binding_shape(
        wire.replace(old="preparation_base", new=phase),
      ),
    )
  }
  assert_true(
    !original_resource_binding_shape(
      wire.replace(old="\"cut\":null", new="\"cut\":{}"),
    ),
  )
}
