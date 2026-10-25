///|
// Independent DATA bytes derived from the existing fixed original vector.
// The parked record has a completed-output tuple with a null holding serial,
// exercising the deepest generated alternative. It is not a live Ledger,
// authenticated Store observation, current-cut receipt or restoration grant.
fn original_protocol_frontier_wire() -> String {
  original_resource_document_vector()
  .replace(
    old="\"cut\":null",
    new=(
      #|"cut":{"continuation":null,"fixed_input_receipt_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","input_artifact_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","run_version":1,"scope_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","slots":[{"attempt_index":0,"entry_identity_cid":null,"ordinal":0,"settlement_identity_cid":null,"slot_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","state":"Unsent"}]}
    ),
  )
  .replace(
    old="\"resource_phase\":\"preparation_base\"",
    new="\"resource_phase\":\"parked\"",
  )
  .replace(old="false,\"reading\",true", new="false,\"parked\",true")
  .replace(
    old="[[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false]],[],[]]",
    new="[[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],[null,\"7\",\"5\"],false,false]],[],[]]",
  )
  .replace(
    old="7ed6db2394d7eaa87d65b022a6bc78f722efaf7a0293115de52c09a89893aae9",
    new="b3634928020e48a45973a4a7499890ecc0037ed354d61c8dc7e64eea78bd2097",
  )
}

///|
fn original_protocol_frontier_finish(
  cursor : ProtocolValidationCursor,
) -> (Bool, Int) raise {
  let mut peak = cursor.pending.length()
  for _ in 0..<10000 {
    let (done, used) = cursor.advance(1)
    assert_eq(used, 1)
    peak = Int::max(peak, cursor.pending.length())
    // The actual generated rule DAG has depth nine. Sibling/alternative
    // iteration replaces a continuation rather than queueing all siblings.
    assert_true(peak <= 9)
    if done {
      return (cursor.result, peak)
    }
  }
  fail("original protocol validation did not terminate")
}

///|
test "original resource protocol keeps generated pending frontier independent of tuple width" {
  let wire = original_protocol_frontier_wire()
  assert_eq(@utf8.encode(wire).length(), 2227)
  assert_eq(
    @sha.hex(@utf8.encode(wire)),
    "106d906a66a9054ad305e41b81c6dfbb249a14c3b64b9d501a8561b43896e87a",
  )
  let document = read_model_original_resource_document(wire, 2227, 215, 5).unwrap()
  let root = generated_protocol_schema_root(
    "model_original_resource_state", true,
  ).unwrap()
  let nodes = protocol_schema_nodes()
  let cursor = start_protocol_validation(document.value, root, nodes, {
    remaining: 215 * 8,
    max_wire_bytes: 2227,
    max_nodes: 215,
    max_depth: 5,
  })
  assert_true(physical_equal(cursor.nodes, nodes))
  assert_eq(original_protocol_frontier_finish(cursor), (true, 9))
  let spent = cursor.budget.remaining
  cursor.cancel()
  cursor.cancel()
  assert_eq(cursor.pending.length(), 0)
  assert_eq(cursor.budget.remaining, spent)
  assert_eq(cursor.advance(1), (false, 0))
  // Cursor retirement neither mutates the borrowed DATA nor proves physical
  // cleanup, releases its original reservation or issues a Model grant.
  assert_eq(@json.stringify_value(document.value, 2227, 215, 5), wire)
}

///|
test "original resource malformed wide object reaches bounded admission before shape refusal" {
  let output = StringBuilder()
  output.write_string("{")
  for index in 0..<214 {
    if index != 0 {
      output.write_string(",")
    }
    output.write_string("\"a" + index.to_string() + "\":null")
  }
  output.write_string("}")
  let wire = output.to_string()
  let value = parse_contract_wire(wire, 8192, 215, 5, data_keys=true).unwrap()
  assert_eq(@json.object_field_count(value), Some(214))
  assert_true(parse_contract_wire(wire, 8192, 214, 5, data_keys=true) is Err(_))
  let cursor = start_protocol_validation(
    value,
    generated_protocol_schema_root("model_original_resource_state", true).unwrap(),
    protocol_schema_nodes(),
    { remaining: 215 * 8, max_wire_bytes: 8192, max_nodes: 215, max_depth: 5, },
  )
  assert_eq(original_protocol_frontier_finish(cursor).0, false)
  cursor.cancel()
  assert_eq(cursor.pending.length(), 0)
  assert_eq(@json.object_field_count(value), Some(214))
  guard read_model_original_resource_document(wire, 8192, 215, 5) is Err(issue) else {
    fail("malformed original document was admitted")
  }
  assert_eq(issue, InvalidField("model_original_resource_state"))
  // Closed-shape failure occurs after Source and Canonical admission. A
  // successful-body field count cannot price this malformed-input workspace.
}
