///|
fn owned_limits() -> Limits {
  { max_bytes: 300000, max_nodes: 200000, max_depth: 32, max_cells: 6400, }
}

///|
test "Sheets append preimage remains exact and target independent of update domain" {
  let body = append_request(
    7,
    [
      { name: "text", cell_type: Text, nullable: false, },
      { name: "number", cell_type: Number, nullable: true, },
      { name: "flag", cell_type: Boolean, nullable: true, },
    ],
    ["=é\r\n".to_json(), (-2.5).to_json(), false.to_json()],
    owned_limits(),
  ).unwrap()
  let origin = "https://sheets.example.test"
  let path = "/v4/spreadsheets/book:batchUpdate"
  let expected = "sha256:781fc348a15e612ff4b0bbec9d7309981e1b5151ccebcbc377c56cc47cab8d5a"
  assert_eq(append_request_identity(origin, path, body), Ok(expected))
  assert_not_eq(
    append_request_identity(origin, path, body + "\n"),
    Ok(expected),
  )
  assert_not_eq(
    append_request_identity(origin, path + "?foreign=1", body),
    Ok(expected),
  )
  assert_not_eq(
    append_request_identity(origin + "/foreign", path, body),
    Ok(expected),
  )
  assert_not_eq(range_request_cid(origin, path, body, "{}"), Ok(expected))
}

///|
fn owned_configuration() -> String {
  "{\"origin\":\"https://sheets.example.test\",\"spreadsheetId\":\"book\",\"range\":{\"sheetId\":7,\"startRow\":2,\"endRow\":4,\"startColumn\":1,\"endColumn\":3},\"columns\":[{\"name\":\"text\",\"type\":\"string\",\"nullable\":false},{\"name\":\"flag\",\"type\":\"boolean\",\"nullable\":true}]}"
}

///|
fn owned_target(binding_cid : String) -> String {
  range_reference(
    "https://sheets.example.test",
    "book",
    { sheet_id: 7, start_row: 2, end_row: 4, start_column: 1, end_column: 3, },
    "sha256:" + "a".repeat(64),
    binding_cid,
    owned_limits(),
  )
  .unwrap()
  .stringify()
}

///|
fn owned_binding(
  binding_cid? : String = "sha256:" + "b".repeat(64),
) -> RangeBinding {
  admit_range_binding(
    owned_configuration(),
    "sha256:e3b7d39898d2037cffd055b1c51f24c66e616d2bb8ae3d4a34529515c26196ab",
    binding_cid,
    owned_target(binding_cid),
    owned_limits(),
  ).unwrap()
}

///|
fn owned_value() -> String {
  "{\"rows\":[{\"text\":\"=é\\r\\n\",\"flag\":false},{\"text\":\"second\",\"flag\":true}]}"
}

///|
fn owned_effect(
  binding : RangeBinding,
  effect_id? : String = "replace",
) -> String raise {
  let value = @json.parse(owned_value()) catch { _ => fail("fixed value") }
  let target = @json.parse(binding.target_wire) catch {
    _ => fail("fixed target")
  }
  let body : Json = [
    {
      "effect_id": effect_id.to_json(),
      "effect_kind": "command",
      "resolved_command_contract_cid": binding.command_cid.to_json(),
      "changes": [
        {
          "intended_changes": { "value": value },
          "target_row_identity": target,
        },
      ],
    },
  ]
  body.stringify()
}

///|
fn owned_recovery(binding : RangeBinding) -> String raise {
  let entry = range_recovery_entry(binding, "replace").unwrap()
  let value = @json.parse(entry) catch { _ => fail("fixed entry") }
  guard value is Object(fields) else { fail("entry object") }
  fields["memberIndex"] = (0).to_json()
  Json::array([Json::object(fields)]).stringify()
}

///|
test "Sheets owned request matches immutable pre-migration bytes and CID on every target" {
  let binding = owned_binding()
  let request = prepare_range_request(
    binding,
    owned_value(),
    binding.target_wire,
  ).unwrap()
  let expected : Json = {
    "requests": [
      {
        "updateCells": {
          "range": {
            "sheetId": 7,
            "startRowIndex": 2,
            "endRowIndex": 4,
            "startColumnIndex": 1,
            "endColumnIndex": 3,
          },
          "rows": [
            {
              "values": [
                { "userEnteredValue": { "stringValue": "=é\r\n" } },
                { "userEnteredValue": { "boolValue": false } },
              ],
            },
            {
              "values": [
                { "userEnteredValue": { "stringValue": "second" } },
                { "userEnteredValue": { "boolValue": true } },
              ],
            },
          ],
          "fields": "userEnteredValue",
        },
      },
    ],
  }
  assert_eq(range_request_body(request), expected.stringify())
  assert_eq(
    range_request_identity(request),
    "sha256:5ba9eddd97003fa7e4341324589b449134332400a662262039776cff24004f21",
  )
  assert_true(range_request_body(request).contains("=é\\r\\n"))
}

///|
test "Sheets owned reference uses unchanged provider range and authority identities" {
  let target = owned_target("sha256:" + "b".repeat(64))
  assert_true(
    target.contains(
      "sha256:d7482f414734110c3d1775460ab9c00fd769271779374b48ceef7bf4ecc73845",
    ),
  )
  assert_true(
    target.contains(
      "sha256:3df522c65a0e49bd6aa3b16c946d9b5f587b824800bbdc6e021654f4a524042d",
    ),
  )
  let binding = owned_binding()
  for
    field in [
      "provider_namespace", "resource_kind", "provider_identity_cid", "identity_cid",
      "authority_scope_cid", "boundary_cid",
    ] {
    let target = @json.parse(binding.target_wire) catch {
      _ => fail("fixed target")
    }
    guard target is Object(fields) else { fail("target object") }
    fields[field] = "foreign".to_json()
    let result = prepare_range_request(
      binding,
      owned_value(),
      Json::object(fields).stringify(),
    )
    guard result is Err(issue) else { fail("foreign target admitted") }
    assert_eq(range_failure_code(issue), "SheetsRangeReferenceUnavailable")
  }
}

///|
test "Sheets same physical bytes do not make a foreign permission or nominal installation current" {
  let original = owned_binding()
  let request = prepare_range_request(
    original,
    owned_value(),
    original.target_wire,
  ).unwrap()
  let foreign = owned_binding(binding_cid="sha256:" + "c".repeat(64))
  let other = prepare_range_request(foreign, owned_value(), foreign.target_wire).unwrap()
  assert_eq(range_request_body(request), range_request_body(other))
  assert_not_eq(range_request_identity(request), range_request_identity(other))
  assert_eq(
    admit_range_request(foreign, request),
    Err(range_failure("SheetsRangeReferenceUnavailable")),
  )
  let copied_binding = owned_binding()
  assert_eq(
    admit_range_request(copied_binding, request),
    Err(range_failure("ForeignSheetsRangeRequest")),
  )
  assert_eq(admit_range_request(original, request), Ok(()))
}

///|
test "Sheets owned recovery preserves original request and recovery observation identity" {
  let binding = owned_binding()
  let entry = range_recovery_entry(binding, "replace").unwrap()
  assert_true(
    entry.contains(
      "sha256:af8322924b910fde0e1bfd46a909921fcd7039f869969b8e94ce0c23aa738e6e",
    ),
  )
  let restored = recover_range_requests(
    binding,
    owned_effect(binding),
    owned_recovery(binding),
    owned_limits(),
  ).unwrap()
  assert_eq(restored.length(), 1)
  assert_eq(restored[0].length(), 1)
  assert_eq(
    range_request_identity(restored[0][0]),
    "sha256:5ba9eddd97003fa7e4341324589b449134332400a662262039776cff24004f21",
  )
  assert_eq(admit_range_request(binding, restored[0][0]), Ok(()))
}

///|
test "Sheets owned recovery rejects foreign effect config range and duplicate retained records" {
  let binding = owned_binding()
  let recovery = owned_recovery(binding)
  let duplicate = @json.parse(recovery) catch { _ => fail("fixed recovery") }
  guard duplicate is Array(entries) else { fail("recovery array") }
  for
    changed in [
      "[]",
      Json::array([entries[0], entries[0]]).stringify(),
      recovery.replace(old="\"memberIndex\":0", new="\"memberIndex\":1"),
      recovery.replace(old="sheets-range-request", new="foreign-request"),
      recovery.replace(old="replace", new="foreign-effect"),
      recovery.replace(old="bbbbbbbb", new="cccccccc"),
      recovery.replace(old="startRow\\\":2", new="startRow\\\":1"),
    ] {
    assert_not_eq(changed, recovery)
    guard recover_range_requests(
        binding,
        owned_effect(binding),
        changed,
        owned_limits(),
      )
      is Err(issue) else {
      fail("foreign recovery admitted")
    }
    assert_eq(range_failure_code(issue), "SheetsRangeRecoveryMismatch")
  }
  for
    effects in [
      owned_effect(binding, effect_id="different-effect"),
      owned_effect(binding).replace(
        old="\"effect_kind\":\"command\"",
        new="\"effect_kind\":\"update\"",
      ),
      owned_effect(binding).replace(
        old=binding.command_cid,
        new="sha256:" + "d".repeat(64),
      ),
    ] {
    guard recover_range_requests(binding, effects, recovery, owned_limits())
      is Err(issue) else {
      fail("foreign effect admitted")
    }
    assert_eq(range_failure_code(issue), "SheetsRangeRecoveryMismatch")
  }
}

///|
test "Sheets original range input refusal codes and scalar cell reasons are preserved" {
  let binding = owned_binding()
  for value in ["{}", "{\"rows\":[],\"extra\":0}"] {
    guard prepare_range_request(binding, value, binding.target_wire)
      is Err(issue) else {
      fail("open input admitted")
    }
    assert_eq(range_failure_code(issue), "InvalidSheetsRangeInput")
  }
  for
    value in [
      "{\"rows\":[]}", "{\"rows\":[{\"text\":null,\"flag\":true},{\"text\":\"b\",\"flag\":true}]}",
    ] {
    guard prepare_range_request(binding, value, binding.target_wire)
      is Err(issue) else {
      fail("partial or null input admitted")
    }
    assert_eq(range_failure_code(issue), "SheetsContractRefused")
    assert_true(range_failure_refusal(issue) is Some(_))
  }
}

///|
test "original canonical target facts are reused without restricting equivalent noncanonical input" {
  let binding = owned_binding()
  assert_true(range_target_matches(binding, binding.target_wire))
  assert_true(
    range_target_matches(binding, " \n" + binding.target_wire + " \r\n"),
  )
  assert_false(range_target_matches(binding, binding.target_wire + "0"))
  assert_false(range_target_matches(binding, "{}"))
  let foreign = owned_binding(binding_cid="sha256:" + "c".repeat(64))
  assert_false(range_target_matches(binding, foreign.target_wire))
  let request = prepare_range_request(
    binding,
    owned_value(),
    binding.target_wire,
  ).unwrap()
  // Same data equality is not an original request/installation admission.
  let equal = owned_binding()
  assert_true(range_target_matches(equal, binding.target_wire))
  assert_true(admit_range_request(equal, request) is Err(_))
}

///|
test "range write construction templates bound original update and clear bodies without changing identities" {
  let binding = owned_binding()
  let metadata = range_construction_metadata(binding)
  let request = prepare_range_request(
    binding,
    owned_value(),
    binding.target_wire,
  ).unwrap()
  let selected = range_write_construction_bounds(
    metadata,
    owned_value().length(),
    false,
  ).unwrap()
  assert_true(request.body.length() <= selected.body_bytes)
  let parsed = @json.parse(request.body) catch { _ => fail("original body") }
  assert_true(range_template_nodes(parsed) <= selected.body_nodes)
  assert_true(range_template_depth(parsed) <= selected.body_depth)
  let marker = "00000000-0000-4000-8000-000000000000"
  let original = clear_request(
    binding.range,
    binding.columns,
    marker,
    binding.limits,
  ).unwrap()
  let clear = range_write_construction_bounds(metadata, 2, true).unwrap()
  assert_true(original.length() <= clear.body_bytes)
  assert_true(range_write_construction_bounds(metadata, 0, false) is None)
  assert_eq(metadata.rows, 2)
  assert_eq(metadata.columns, 2)
}

///|
// Exact previous range_parse path, retained only as a migration oracle.
fn range_parse_indexed_before(
  wire : String,
  limits : Limits,
) -> Result[Json, RangeFailure] {
  guard admit(@utf8.encode(wire), limits) is Ok(_) else {
    return Err(range_failure("same-original-refusal"))
  }
  Ok(@json.parse(wire)) catch {
    _ => Err(range_failure("same-original-refusal"))
  }
}

///|
test "range parser keeps the original full refusal boundary without constructing an unused index" {
  let bodies = [
    "{\"text\":\"e\u0301\\r\\n\",\"n\":1,\"b\":true,\"nil\":null}", "{\"a\":[1,2,{\"emoji\":\"😀\"}],\"empty\":{}}",
    "{\"escaped\":\"\\u00e9\\n\\uD83D\\uDE00\"}", "-0", "{\"a\":1,\"a\":2}", "{\"a\":[1,]}",
    "1e400", "\"\\uD800\"", "[[]] trailing",
  ]
  let limits : Array[Limits] = [
    { max_bytes: 1024, max_nodes: 64, max_depth: 8, max_cells: 6400, },
    { max_bytes: 16, max_nodes: 64, max_depth: 8, max_cells: 6400, },
    { max_bytes: 1024, max_nodes: 2, max_depth: 8, max_cells: 6400, },
    { max_bytes: 1024, max_nodes: 64, max_depth: 1, max_cells: 6400, },
    { max_bytes: 0, max_nodes: 64, max_depth: 8, max_cells: 6400, },
    { max_bytes: 1024, max_nodes: 0, max_depth: 8, max_cells: 6400, },
    { max_bytes: 1024, max_nodes: 64, max_depth: 0, max_cells: 6400, },
    { max_bytes: 1024, max_nodes: 64, max_depth: 8, max_cells: 0, },
  ]
  for body in bodies {
    for bound in limits {
      match
        (
          range_parse_indexed_before(body, bound),
          range_parse(body, bound, "same-original-refusal"),
        ) {
        (Ok(before), Ok(after)) => assert_eq(before, after)
        (Err(before), Err(after)) =>
          assert_eq(range_failure_code(before), range_failure_code(after))
        _ => fail("original parser/refusal boundary changed")
      }
    }
  }
  guard range_parse(bodies[0], limits[0], "same-original-refusal").unwrap()
    is Object(kept) else {
    fail("same object")
  }
  assert_eq(kept.get("text"), Some("e\u0301\r\n".to_json()))
  assert_eq(kept.get("b"), Some(true.to_json()))
}

///|
test "original request material survives repeated facts without admitting a copied binding" {
  let binding = owned_binding()
  let request = prepare_range_request(
    binding,
    owned_value(),
    binding.target_wire,
  ).unwrap()
  let value = request.value
  let target = binding.target
  let identity = range_request_identity(request)
  let first = range_request_json(binding, request).unwrap()
  let second = range_request_json(binding, request).unwrap()
  assert_eq(first, second)
  assert_eq(range_request_identity(request), identity)
  assert_true(physical_equal(request.value, value))
  assert_true(physical_equal(binding.target, target))
  // A consumer may mutate its separately parsed public facts. It never gets
  // the private original native Json retained by this binding/request.
  let public_copy = @json.parse(first) catch { _ => fail("fixed facts") }
  guard public_copy is Object(fields) else { fail("facts object") }
  fields.set("value", "foreign consumer copy".to_json())
  fields.set("target", Json::null())
  assert_eq(range_request_json(binding, request), Ok(first))
  let foreign = owned_binding()
  assert_eq(
    range_request_json(foreign, request).map_err(range_failure_code),
    Err("ForeignSheetsRangeRequest"),
  )
}
