///|
// Structural selection data is not a target Reference or execution grant.
fn published_store_header(target : String) -> Program raise {
  effect_program(
    "    create: {command: {from: {result: rows}, target: " +
    target +
    ", contract: command:storage.upload.v1, input: {}}}",
  )
}

///|
test "published STORE Command target retains its original closed selector" {
  let program = published_store_header(
    "{published_store: {target_ref: 'connector://storage/objects', mapping_ref: 'mapping:storage.upload.v1'}}",
  )
  let headers = collect_effect_headers(program, 1, 1).unwrap()
  let header = effect_header_at(headers, 0).unwrap()
  assert_eq(effect_header_kind(header), "command")
  assert_eq(effect_header_source_result(header), Some("rows"))
  assert_eq(effect_header_contract_ref(header), "command:storage.upload.v1")
  assert_eq(effect_headers_work(headers), 1)
  assert_true(collect_effect_headers(program, 1, 0) is Err(_))
}

///|
test "published STORE target does not relax the original Command field form" {
  let headers = collect_effect_headers(
    published_store_header("{field: destination}"),
    1,
    1,
  ).unwrap()
  assert_eq(
    effect_header_kind(effect_header_at(headers, 0).unwrap()),
    "command",
  )
  assert_eq(effect_headers_work(headers), 1)
  for
    target in [
      "{}", "{field: ''}", "{field: null}", "{field: destination, extra: true}",
    ] {
    assert_eq(effect_header_error(published_store_header(target)), InvalidBody)
  }
}

///|
test "published STORE target rejects incomplete mixed and foreign structural forms" {
  for
    target in [
      "{published_store: null}", "{published_store: {}}", "{published_store: {target_ref: 'connector://storage/objects'}}",
      "{published_store: {mapping_ref: 'mapping:storage.upload.v1'}}", "{published_store: {target_ref: '', mapping_ref: 'mapping:storage.upload.v1'}}",
      "{published_store: {target_ref: 'other', mapping_ref: 'mapping:storage.upload.v1'}}",
      "{published_store: {target_ref: 'connector://storage/objects', mapping_ref: ''}}",
      "{published_store: {target_ref: 'connector://storage/objects', mapping_ref: 'command:storage.upload.v1'}}",
      "{published_store: {target_ref: 'connector://storage/objects', mapping_ref: 'mapping:storage.upload'}}",
      "{published_store: {target_ref: 'connector://storage/objects', mapping_ref: 'mapping:storage.upload.v1', extra: true}}",
      "{published_store: {target_ref: 'connector://storage/objects', mapping_ref: 'mapping:storage.upload.v1'}, field: destination}",
      "{published_store: {target_ref: 'connector://storage/objects', mapping_ref: 'mapping:storage.upload.v1'}, extra: true}",
    ] {
    assert_eq(effect_header_error(published_store_header(target)), InvalidBody)
  }
}
