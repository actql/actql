///|
fn clear_owned_binding(
  binding_cid? : String = "sha256:" + "b".repeat(64),
  command_cid? : String = "sha256:" + "c".repeat(64),
) -> ClearRangeBinding {
  // Provider-only handles are not Common References or approval capabilities.
  admit_clear_range_binding(
    owned_configuration(),
    command_cid,
    binding_cid,
    owned_target(binding_cid),
    owned_limits(),
  ).unwrap()
}

///|
fn clear_owned_request(binding : ClearRangeBinding) -> ClearRangeRequest {
  prepare_clear_range_request(
    binding,
    "{}",
    binding.original.target_wire,
    clear_fixed_marker(),
  ).unwrap()
}

///|
fn clear_saved_effect(binding : ClearRangeBinding) -> Json {
  let target = @json.parse(binding.original.target_wire) catch {
    _ => abort("fixed provider target")
  }
  {
    "effect_id": "clear",
    "effect_kind": "command",
    "resolved_command_contract_cid": binding.original.command_cid.to_json(),
    "changes": [
      { "intended_changes": { "value": {} }, "target_row_identity": target },
    ],
  }
}

///|
fn clear_saved_entry(binding : ClearRangeBinding) -> Json {
  let wire = clear_range_recovery_entry(binding, "clear", [
    clear_owned_request(binding),
  ]).unwrap()
  let value = @json.parse(wire) catch { _ => abort("fixed provider entry") }
  guard value is Object(fields) else { abort("fixed provider entry") }
  fields["memberIndex"] = 0
  Json::object(fields)
}

///|
test "clear retains the exact nominal binding and original request body" {
  let binding = clear_owned_binding()
  let request = clear_owned_request(binding)
  assert_true(admit_clear_range_request(binding, request) is Ok(_))
  assert_eq(clear_range_request_body(binding, request), Ok(clear_fixed_body()))
  assert_eq(
    clear_range_request_identity(binding, request),
    Ok(
      "sha256:81315af16226c59724b599898ad401dae6b8e15410312e4d2de4fc23a3d42fd3",
    ),
  )
  let duplicate = clear_owned_binding()
  assert_eq(
    admit_clear_range_request(duplicate, request).unwrap_err().code,
    "ForeignSheetsClearRequest",
  )
  let foreign = clear_owned_binding(binding_cid="sha256:" + "d".repeat(64))
  assert_eq(
    admit_clear_range_request(foreign, request).unwrap_err().code,
    "SheetsRangeReferenceUnavailable",
  )
  assert_true(clear_range_request_body(duplicate, request) is Err(_))
  assert_true(
    clear_range_request_outcome(
      duplicate,
      request,
      200,
      @utf8.encode(clear_fixed_reply()),
    )
    is Err(_),
  )
}

///|
test "clear never treats omitted input null partial update or a foreign target as clearing" {
  let binding = clear_owned_binding()
  for value in ["null", "[]", "{\"rows\":[]}", "{\"values\":null}"] {
    assert_eq(
      prepare_clear_range_request(
        binding,
        value,
        binding.original.target_wire,
        clear_fixed_marker(),
      ).unwrap_err().code,
      "InvalidSheetsClearInput",
    )
  }
  assert_eq(
    prepare_clear_range_request(binding, "{}", "{}", clear_fixed_marker()).unwrap_err().code,
    "SheetsRangeReferenceUnavailable",
  )
  let request = clear_owned_request(binding)
  assert_true(
    clear_range_request_outcome(
      binding,
      request,
      200,
      @utf8.encode(clear_fixed_reply()),
    )
    is Ok(Applied),
  )
  assert_true(
    clear_range_request_outcome(binding, request, 200, @utf8.encode("{}"))
    is Ok(Unknown),
  )
}

///|
test "cold clear reconstruction retains original markers and claims must retain request identity" {
  let binding = clear_owned_binding()
  let original = clear_owned_request(binding)
  let entry = clear_saved_entry(binding)
  let effects : Json = [clear_saved_effect(binding)]
  let saved : Json = [entry]
  let reopened = clear_owned_binding()
  let restored = recover_clear_range_requests(
    reopened,
    effects.stringify(),
    saved.stringify(),
    owned_limits(),
  ).unwrap()
  assert_eq(restored.length(), 1)
  assert_eq(restored[0].length(), 1)
  assert_eq(
    clear_range_request_identity(reopened, restored[0][0]),
    clear_range_request_identity(binding, original),
  )
  assert_eq(
    clear_range_request_body(reopened, restored[0][0]),
    clear_range_request_body(binding, original),
  )
  // Recovery DATA alone is not a grant. The existing claim Owner separately
  // compares this identity with its durable original canonicalRequestCid.
  let replacement = prepare_clear_range_request(
    reopened,
    "{}",
    reopened.original.target_wire,
    "12345678-1234-4234-8234-123456789abd",
  ).unwrap()
  assert_not_eq(
    clear_range_request_identity(reopened, replacement),
    clear_range_request_identity(binding, original),
  )
  assert_true(
    recover_clear_range_requests(
      clear_owned_binding(command_cid="sha256:" + "d".repeat(64)),
      effects.stringify(),
      saved.stringify(),
      owned_limits(),
    )
    is Err(_),
  )
  assert_true(
    recover_clear_range_requests(
      clear_owned_binding(binding_cid="sha256:" + "d".repeat(64)),
      effects.stringify(),
      saved.stringify(),
      owned_limits(),
    )
    is Err(_),
  )
}

///|
test "clear recovery requires bounded complete coverage and exact original request handles" {
  let binding = clear_owned_binding()
  let request = clear_owned_request(binding)
  assert_true(
    clear_range_recovery_entry(binding, "clear", [request, request]) is Err(_),
  )
  assert_true(
    clear_range_recovery_entry(binding, "clear", [
      clear_owned_request(clear_owned_binding()),
    ])
    is Err(_),
  )
  let effects : Json = [clear_saved_effect(binding)]
  for saved in ["[]", "null", "{}"] {
    assert_true(
      recover_clear_range_requests(
        binding,
        effects.stringify(),
        saved,
        owned_limits(),
      )
      is Err(_),
    )
  }
  let entry = clear_saved_entry(binding)
  let duplicate : Json = [entry, entry]
  assert_true(
    recover_clear_range_requests(
      binding,
      effects.stringify(),
      duplicate.stringify(),
      owned_limits(),
    )
    is Err(_),
  )
  let duplicate_effects : Json = [
    clear_saved_effect(binding),
    clear_saved_effect(binding),
  ]
  assert_true(
    recover_clear_range_requests(
      binding,
      duplicate_effects.stringify(),
      duplicate.stringify(),
      owned_limits(),
    )
    is Err(_),
  )
  let saved : Json = [entry]
  assert_true(
    recover_clear_range_requests(
      binding,
      effects.stringify(),
      saved.stringify(),
      { ..owned_limits(), max_bytes: 1, },
    )
    is Err(_),
  )
}
