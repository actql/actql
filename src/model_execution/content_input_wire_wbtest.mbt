///|
fn model_content_wire_vector() -> String {
  (
    // Independent canonical ContentRef vector from the value contract, issued
    // by a trusted fixture authority, not constructed by a Program value.
    #|{"$actql_ref":"content","content_ref_cid":"sha256:15e902418023a2de574d29d716f3b643825e19afa1fa3a5a46e049ffb1606eff","media_type":"application/json","metadata":{"availability_evidence_cid":"sha256:8888888888888888888888888888888888888888888888888888888888888888","capture_authority":"read_content","content_cid":"sha256:5555555555555555555555555555555555555555555555555555555555555555","content_store_id":"fixture","data_classification":"internal","effective_data_policy_cid":"sha256:6666666666666666666666666666666666666666666666666666666666666666","issuer_evidence":{},"media_type":"application/json","retention_class":"fixture","size_bytes":3,"storage_scope":"workspace","truncated":false},"version":"actql-content-ref/0.1"}
  )
}

///|
fn model_content_wire_fixture(live : Ref[Bool]) -> @admitted.CheckedValue {
  let wire = model_content_wire_vector()
  @admitted.issue_reference(
    @admitted.bind_reference_issuer((_, actual) => actual == wire, _ => live.val),
    @contract.content_reference_contract(
      Some("application/json"),
      nullable=false,
      max_name_bytes=128,
    ).unwrap(),
    wire,
    { max_bytes: 4096, max_nodes: 100, max_depth: 8, max_text_units: 4096, },
  ).unwrap()
}

///|
test "Model input wire refuses a revoked original ContentRef in every container" {
  for wrapper in 0..<3 {
    let live = Ref(true)
    let content = model_content_wire_fixture(live)
    let value = match wrapper {
      0 => content.value
      1 => @admitted.array_value([content.value])
      _ => @admitted.object_value([("attachment", content.value)]).unwrap()
    }
    let writer = @encode.writer(8192, 256, 16)
    let cursor = @admitted.start_wire_emit(value, writer)
    // Stop at the actual reference frame, after any container prefix, then
    // revoke the very same issuer occurrence before the owner advances it.
    let mut reached = false
    for _ in 0..<16 {
      if @admitted.wire_emit_next_reference(cursor) is Some(_) {
        reached = true
        break
      }
      assert_false(advance_model_input_wire(cursor).unwrap())
    }
    assert_true(reached)
    live.val = false
    assert_true(
      advance_model_input_wire(cursor) is Err(InputReferenceUnavailable),
    )
    @admitted.cancel_wire_emit(cursor)
  }
}

///|
test "Model input wire preserves an available ContentRef and explicit NULL" {
  let live = Ref(true)
  let content = model_content_wire_fixture(live)
  let value = @admitted.object_value([
    ("attachment", content.value),
    ("optional", @admitted.null_value()),
  ]).unwrap()
  let writer = @encode.writer(8192, 256, 16)
  let cursor = @admitted.start_wire_emit(value, writer)
  let mut finished = false
  for _ in 0..<512 {
    if advance_model_input_wire(cursor).unwrap() {
      finished = true
      break
    }
  }
  assert_true(finished)
  assert_eq(
    @encode.finish(writer),
    "{\"attachment\":" + model_content_wire_vector() + ",\"optional\":null}",
  )
  assert_true(live.val)
}
