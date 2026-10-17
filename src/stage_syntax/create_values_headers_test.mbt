///|
fn create_values_header(body : String) -> Program raise {
  effect_program(
    "    create: {create: {target: crm, mapping: mapping:crm.create.v1, " +
    body +
    "}}",
  )
}

///|
test "create values keep original Result occurrence and exact field literal map" {
  let program = create_values_header(
    "from: {result: rows}, values: {Name: {field: name}, City: {literal: null}}",
  )
  let headers = collect_effect_headers(program, 1, 3).unwrap()
  let header = effect_header_at(headers, 0).unwrap()
  assert_eq(effect_header_stage(header), 0)
  assert_eq(effect_header_source_result(header), Some("rows"))
  assert_eq(effect_header_contract_ref(header), "mapping:crm.create.v1")
  let values = effect_header_create_values(header).unwrap()
  assert_eq(@wire.object_length(values), Some(2))
  let fields = @wire.open_object(values).unwrap()
  let name = @wire.open_object(@wire.lookup(fields, "Name").unwrap()).unwrap()
  assert_eq(@wire.text(@wire.lookup(name, "field").unwrap()), Ok("name"))
  let city = @wire.open_object(@wire.lookup(fields, "City").unwrap()).unwrap()
  assert_true(@wire.is_null(@wire.lookup(city, "literal").unwrap()))
  assert_eq(effect_headers_work(headers), 3)
  assert_eq(
    effect_header_issue_kind(collect_effect_headers(program, 1, 2).unwrap_err()),
    BudgetExceeded,
  )
}

///|
test "create values allow empty structural map without granting Mapping requirements" {
  let headers = collect_effect_headers(
    create_values_header("from: {result: rows}, values: {}"),
    1,
    1,
  ).unwrap()
  let header = effect_header_at(headers, 0).unwrap()
  assert_eq(
    @wire.object_length(effect_header_create_values(header).unwrap()),
    Some(0),
  )
  assert_eq(effect_headers_work(headers), 1)
}

///|
test "create values require Result and cannot reinterpret or accompany raw payload" {
  for
    body in [
      "values: {Name: {literal: original}}", "payload: {Name: original}, values: {Name: {literal: other}}",
      "from: {result: rows}, payload: {Name: original}, values: {}",
    ] {
    assert_eq(
      effect_header_error(create_values_header(body)),
      InvalidSourceResult,
    )
  }
  for
    body in [
      "from: {result: rows}, values: null", "from: {result: rows}, values: []", "from: {result: rows}, values: {Name: name}",
      "from: {result: rows}, values: {Name: {field: name, literal: original}}", "from: {result: rows}, values: {Name: {unknown: original}}",
      "from: {result: rows}, values: {Name: {field: ''}}",
    ] {
    assert_eq(effect_header_error(create_values_header(body)), InvalidBody)
  }
}

///|
test "legacy create absence and raw business payload keep their original work and optional getter" {
  for
    body in [
      "from: {result: rows}", "payload: {Name: {$param: business}, values: {field: business}, nested: {literal: business}}",
    ] {
    let headers = collect_effect_headers(create_values_header(body), 1, 1).unwrap()
    assert_eq(effect_headers_work(headers), 1)
    assert_true(
      effect_header_create_values(effect_header_at(headers, 0).unwrap()) is None,
    )
  }
}
