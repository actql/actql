///|
// Called by the existing independently pinned Catalog/parameter fixtures.
// No synthetic request owner or diagnostic-only constructor is introduced.
fn check_keyed_request_wire_cursor(
  request : KeyedRowRequest,
  expected : String,
) -> Unit raise {
  let initial = keyed_request_wire_start_inventory()
  assert_true(initial.record_headers > 0L)
  let cursor = start_keyed_request_wire(request, 10000, 1000, 30).unwrap()
  assert_true(physical_equal(keyed_request_wire_owner(cursor), request))
  let pieces = []
  let mut turns = 0
  while true {
    let next = keyed_request_wire_next_inventory(cursor).unwrap()
    let before = keyed_request_wire_progress(cursor)
    assert_eq(next.generation, before.0)
    let result = advance_keyed_request_wire(cursor)
    let after = keyed_request_wire_progress(cursor)
    assert_true(after.0 > before.0)
    assert_true(after.1 - before.1 <= next.fragment_bytes)
    turns += 1
    match result {
      WireContinue => ()
      WireFragment(value) => pieces.push(value)
      WireComplete(bytes, _, _) => {
        assert_eq(pieces.join(""), expected)
        assert_eq(bytes, @utf8.encode(expected).length())
        break
      }
      WireFailed(_) => fail("same original wire cursor unexpectedly failed")
    }
    if turns > 1000 {
      fail("request wire cursor failed to progress")
    }
  }
  assert_true(keyed_request_wire_next_inventory(cursor) is None)
  assert_true(advance_keyed_request_wire(cursor) is WireFailed(_))
  let cancelled = start_keyed_request_wire(request, 10000, 1000, 30).unwrap()
  let prepared = keyed_request_wire_next_inventory(cancelled).unwrap()
  cancel_keyed_request_wire(cancelled)
  assert_true(keyed_request_wire_progress(cancelled).0 != prepared.generation)
  assert_true(keyed_request_wire_next_inventory(cancelled) is None)
  assert_true(advance_keyed_request_wire(cancelled) is WireFailed(_))
  let short = start_keyed_request_wire(request, 1, 1000, 30).unwrap()
  let mut failed = false
  for _ in 0..<20 {
    if advance_keyed_request_wire(short) is WireFailed(_) {
      failed = true
      break
    }
  }
  assert_true(failed)
  assert_true(keyed_request_wire_next_inventory(short) is None)
  assert_eq(keyed_row_request_wire(request, 10000, 1000, 30).unwrap(), expected)
}

///|
test "keyed request fragments include large authored and parameter values from original Catalog" {
  let payload = "x".repeat(2048)
  for parameter in [false, true] {
    let input = "{\"connector\":\"crm/main\",\"resource\":\"r\",\"request\":{\"tenant\":" +
      (if parameter {
        "{\"$param\":\"tenant\"}"
      } else {
        "\"" + payload + "\""
      }) +
      "}}"
    let inputs = fixture_inputs(
      input,
      declarations=if parameter {
        "\"params\":{\"tenant\":{\"type\":\"string\"}},"
      } else {
        ""
      },
    )
    let resolved = resolve(inputs, source_acquisition_catalog(), caps()).unwrap()
    let context = prepare_requests(resolved, request_slots(inputs), 1000000).unwrap()
    let request = check_keyed_request(
      context,
      at(resolved, 0).unwrap(),
      request_caps(),
    ).unwrap()
    let parameters = prepare_request_parameters(
      context,
      supplied_values(
        inputs,
        if parameter {
          "{\"tenant\":\"" + payload + "\"}"
        } else {
          "{}"
        },
      ),
      1000000,
    ).unwrap()
    let selected = bind_keyed_request_parameters(parameters, request, 1000000).unwrap()
    let preparation = start_keyed_row_request(
      selected,
      [@value.number_value(7.0).unwrap()],
      request_caps(),
    ).unwrap()
    let mut completed = None
    for _ in 0..<100 {
      match advance_keyed_row_request(preparation) {
        KeyedRowRequestContinue => ()
        KeyedRowRequestComplete(value) => {
          completed = Some(value)
          break
        }
        KeyedRowRequestFailed(_) => fail("original request preparation failed")
      }
    }
    let request = completed.unwrap()
    assert_eq(parameterized_keyed_static_request_wire(selected, 10000, 1000, 30).unwrap(),
      "{\"tenant\":\"" + payload + "\"}")
    let expected = "{\"tenant\":\"" + payload + "\",\"id\":7}"
    let retained = keyed_row_request_retained_inventory(request).unwrap()
    // Two actual field pairs, one correlated CheckedValue, original Request
    // and one fields Array. The large Text itself is borrowed, never copied.
    assert_eq(retained.record_headers, 7L)
    assert_eq(retained.reference_slots, 27L)
    assert_eq(retained.scalar_words, 5L)
    assert_eq(keyed_row_request_usage(request).1, 1)
    assert_eq(keyed_row_request_usage(request).2, 0)
    check_keyed_request_wire_cursor(request, expected)
  }
}
