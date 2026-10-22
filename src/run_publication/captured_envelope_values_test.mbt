///|
test "issued captured envelope matches the unchanged external sealer byte for byte" {
  let preparation = captured_preparation_test_start(with_model=true)
  let mut done = false
  for _ in 0..<500000 {
    if preparation.advance(64).unwrap().0 {
      done = true
      break
    }
  }
  assert_true(done)
  let contract = preparation.finish().unwrap()
  let wire = publication_contract_json(contract)
  let source = @source.parse_json(wire, {
    max_input_bytes: 65536,
    max_nodes: 4096,
    max_depth: 32,
  }).unwrap()
  let value = @json.from_source(source, 4096, 32, 65536, data_keys=true) catch {
    _ => abort("Invalid captured contract")
  }
  let body = @json.object_without_field(
    value,
    publication_contract_identity_field(contract),
  ).unwrap()
  let preimage = @json.stringify_value(body, 65536, 4095, 32)
  let external = seal_publication_contract(
    "captured_run", preimage, 65536, 4096, 32,
  ).unwrap()
  assert_eq(publication_contract_json(external), wire)
  assert_eq(
    publication_contract_identity(external),
    publication_contract_identity(contract),
  )
}
