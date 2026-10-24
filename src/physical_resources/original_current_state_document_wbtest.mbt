///|
fn current_document_test_wire() -> String {
  // Independent 411-byte current vector, not obtained from the product Writer.
  "[\"actql-original-ledger-state/0.1\",[\"17\",\"16\",\"16\",\"100\",\"256\",\"256\"],[\"17\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"10\",\"7\",\"10\",\"0\",\"2\",\"0\"],[\"0\",\"0\",\"0\"],null,[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]],[\"-3\",\"0\",\"0\"],[\"4\",\"0\",\"0\",true,true,false,\"parked\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false]],[],[]]"
}

///|
fn current_document_test_limits() -> @decode.Limits {
  {
    max_nodes: 400,
    max_depth: 10,
    max_string_bytes: 100,
    max_total_string_bytes: 4000,
  }
}

///|
test "current document independently preserves actual holding and delegation" {
  // Sixteen headers/containers + three reservations + one holding + one
  // delegation = 21 writer units. Both Reader and comparison require seven.
  let wire = "[\"actql-original-ledger-state/0.1\",[\"100\",\"16\",\"16\",\"100\",\"256\",\"256\"],[\"21\",\"0\",\"1\",\"0\",\"0\",\"8\",\"3\",\"16\",\"14\",\"19\",\"2\",\"4\",\"1\"],[\"2\",\"1\",\"1\"],null,[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]],[\"-3\",\"2\",\"1\"],[\"4\",\"1\",\"1\",true,true,false,\"parked\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"0\",\"5\",\"4\",\"5\",true,false,null,null,[false,false,false],null,true,false],[\"1\",\"3\",\"2\",\"2\",true,false,null,null,[false,false,false],null,true,false],[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false]],[[\"0\",\"0\",\"3\",true]],[[\"1\",[\"2\",\"1\",\"1\",\"3\",\"2\",\"2\"],[\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\"]]]]"
  let ledger = resource_park_test_ledger()
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 4, 1, 1).unwrap()
  let attempt = reserve_attempt(ledger, 5L, 7L, 5L).unwrap()
  let holding = retain_allocation(ledger, attempt, 3L).unwrap()
  let delegation = reserve_execution_delegation(
    ledger,
    {
      planning_work: 2,
      attempts: 1,
      holdings: 1,
      transfer_bytes: 3L,
      retained_bytes: 2L,
      execution_bytes: 2L,
    },
    2L,
    2L,
  ).unwrap()
  let (_, consumer) = resource_park_test_consumer(identity, origin)
  let park = park_original_resource_consumer_for_state_write(consumer, origin).unwrap()
  let source = original_document_test_cursor(wire)
  assert_true(
    start_original_current_state_document_read(
      source,
      4,
      1,
      1,
      6,
      current_document_test_limits(),
    )
    is Err(WorkLimit),
  )
  let read = start_original_current_state_document_read(
    source,
    4,
    1,
    1,
    7,
    current_document_test_limits(),
  ).unwrap()
  let document = match advance_original_current_state_document_read(read, 7) {
    CurrentDocumentComplete(value, work=7) => value
    _ => abort("independent complete current inventory failed")
  }
  assert_true(
    start_original_current_state_comparison(park, origin, document, 6)
    is Err(WorkLimit),
  )
  let compare = start_original_current_state_comparison(
    park, origin, document, 7,
  ).unwrap()
  assert_true(
    advance_original_current_state_comparison(compare, 7)
    is ComparisonComplete(work=7),
  )
  assert_eq(quantity_usage(ledger).uncertain, zero_quantities())
  assert_eq(ledger_usage(ledger).planning_work, 21)
  assert_eq(
    (
      ledger.delegated_planning,
      ledger.delegated_attempts,
      ledger.delegated_holdings,
    ),
    (2, 1, 1),
  )
  retire_original_current_state_document(document)
  resource_park_test_invalidate(park)
  release_allocation(ledger, holding).unwrap()
  settle_execution_delegation(ledger, delegation, None).unwrap()
  settle_reservation(ledger, attempt).unwrap()
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
}

///|
fn current_document_test_read(wire : String) -> OriginalCurrentStateDocument {
  let read = start_original_current_state_document_read(
    original_document_test_cursor(wire),
    4,
    0,
    0,
    3,
    current_document_test_limits(),
  ).unwrap()
  for _ in 0..<3 {
    match advance_original_current_state_document_read(read, 1) {
      CurrentDocumentContinue(..) => ()
      CurrentDocumentComplete(document, ..) => return document
      _ => abort("current fixed Reader failed")
    }
  }
  abort("current fixed Reader did not complete")
}

///|
test "current document independently preserves unknown quantity on its original ledger" {
  // Quantity-configured attempts require explicit quantities. The existing
  // delegation API has no such parameter: do not fabricate a mixed fixture
  // or weaken that contract to make this data-only codec pass.
  let wire = "[\"actql-original-ledger-state/0.1\",[\"100\",\"16\",\"16\",\"100\",\"256\",\"256\"],[\"18\",\"1\",\"0\",\"0\",\"0\",\"0\",\"0\",\"10\",\"7\",\"10\",\"0\",\"3\",\"0\"],[\"0\",\"0\",\"0\"],[\"13\",\"17\",\"19\"],[[\"0\",\"0\",\"0\"],[\"13\",\"17\",\"19\"],[\"0\",\"0\",\"0\"]],[\"-3\",\"1\",\"0\"],[\"3\",\"0\",\"0\",true,true,false,\"parked\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"0\",\"0\",\"0\",\"0\",true,false,null,[\"13\",\"17\",\"19\"],[false,false,false],null,false,true],[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false]],[],[]]"
  let ledger = resource_park_test_ledger()
  let origin = original_read_test_origin()
  let amounts : QuantityAmounts = {
    tokens: 13L,
    cost_units: 17L,
    duration_ms: 19L,
  }
  configure_quantities(ledger, amounts).unwrap()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 3, 0, 0).unwrap()
  let attempt = reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(amounts)).unwrap()
  mark_quantities_uncertain(ledger, attempt).unwrap()
  let (_, consumer) = resource_park_test_consumer(identity, origin)
  let park = park_original_resource_consumer_for_state_write(consumer, origin).unwrap()
  let read = start_original_current_state_document_read(
    original_document_test_cursor(wire),
    3,
    0,
    0,
    4,
    current_document_test_limits(),
  ).unwrap()
  let document = match advance_original_current_state_document_read(read, 4) {
    CurrentDocumentComplete(value, work=4) => value
    _ => abort("independent unknown quantity document failed")
  }
  let comparison = start_original_current_state_comparison(
    park, origin, document, 4,
  ).unwrap()
  assert_true(
    advance_original_current_state_comparison(comparison, 4)
    is ComparisonComplete(work=4),
  )
  assert_eq(quantity_usage(ledger).uncertain, amounts)
  assert_eq(quantity_usage(ledger).reserved, zero_quantities())
  assert_eq(ledger_usage(ledger).planning_work, 18)
  retire_original_current_state_document(document)
  resource_park_test_invalidate(park)
  settle_reservation(ledger, attempt).unwrap()
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
}

///|
test "current document exact work and quantum preserve independent live census" {
  for quantum in [1, 2, 3, 50] {
    let (ledger, origin, _, consumer) = current_state_test_consumer(17)
    let park = park_original_resource_consumer_for_state_write(consumer, origin).unwrap()
    let read = start_original_current_state_document_read(
      original_document_test_cursor(current_document_test_wire()),
      4,
      0,
      0,
      3,
      current_document_test_limits(),
    ).unwrap()
    let mut work = 0
    let mut finished = None
    for _ in 0..<3 {
      match advance_original_current_state_document_read(read, quantum) {
        CurrentDocumentContinue(work=n) => work += n
        CurrentDocumentComplete(document, work=n) => {
          work += n
          finished = Some(document)
          break
        }
        _ => abort("current Reader refused exact bytes")
      }
    }
    assert_eq(work, 3)
    let document = finished.unwrap()
    let comparison = start_original_current_state_comparison(
      park, origin, document, 3,
    ).unwrap()
    let mut compared = 0
    for _ in 0..<3 {
      match advance_original_current_state_comparison(comparison, quantum) {
        ComparisonContinue(work=n) => compared += n
        ComparisonComplete(work=n) => {
          compared += n
          break
        }
        _ => abort("current census did not match")
      }
    }
    assert_eq(compared, 3)
    assert_true(comparison.park is None && comparison.document is None)
    assert_true(
      document.source is Some(_) &&
      original_resource_park_current(park, origin) is Some(_),
    )
    assert_eq(ledger_usage(ledger).planning_work, 17)
    retire_original_current_state_document(document)
    resource_park_test_invalidate(park)
    settle_funded_read_consumer(consumer, true).unwrap()
    assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
    retire_original_resource_park(park).unwrap()
  }
}

///|
test "current document refuses initial reading wrong phase canonical integers and one short" {
  let limits = current_document_test_limits()
  for
    wire in [
      original_document_test_wire(),
      current_document_test_wire().replace(old="\"parked\"", new="\"reading\""),
      current_document_test_wire().replace(old="\"parked\"", new="\"unknown\""),
      current_document_test_wire().replace(old="\"-3\"", new="\"-03\""),
      current_document_test_wire().replace(
        old="[\"17\",\"16\"",
        new="[17,\"16\"",
      ),
    ] {
    assert_true(
      start_original_current_state_document_read(
        original_document_test_cursor(wire),
        4,
        0,
        0,
        3,
        limits,
      )
      is Err(InvalidRecord),
    )
  }
  let source = original_document_test_cursor(current_document_test_wire())
  assert_true(
    start_original_current_state_document_read(source, 4, 0, 0, 2, limits)
    is Err(WorkLimit),
  )
  assert_true(
    start_original_current_state_document_read(source, 3, 0, 0, 3, limits)
    is Err(InvalidRecord),
  )
  assert_true(
    start_original_current_state_document_read(
      source, 2147483647, 0, 0, 3, limits,
    )
    is Err(InvalidBounds),
  )
  assert_true(
    start_original_state_document_read(source, 4, 0, 0, 3) is Err(InvalidRecord),
  )
}

///|
test "current document retains whole owned tree bounds and cancellation borrows" {
  let source = original_document_test_cursor(
    "[\"" + "x".repeat(65) + "\"," + current_document_test_wire() + "]",
  )
  let child = @decode.element_at(source, 1).unwrap()
  let usage = @decode.admission_usage(source)
  assert_eq(@decode.admission_usage(child), usage)
  let limits : @decode.Limits = {
    max_nodes: usage.nodes,
    max_depth: usage.depth,
    max_string_bytes: usage.largest_string_bytes,
    max_total_string_bytes: usage.total_string_bytes,
  }
  for
    short in [
      { ..limits, max_nodes: usage.nodes - 1, },
      { ..limits, max_depth: usage.depth - 1, },
      { ..limits, max_string_bytes: 64, },
      { ..limits, max_total_string_bytes: usage.total_string_bytes - 1, },
    ] {
    assert_true(
      start_original_current_state_document_read(child, 4, 0, 0, 3, short)
      is Err(InvalidBounds),
    )
  }
  let read = start_original_current_state_document_read(
    child, 4, 0, 0, 3, limits,
  ).unwrap()
  let borrowed = read.document.unwrap()
  assert_true(
    advance_original_current_state_document_read(read, 0)
    is CurrentDocumentFailed(InvalidQuantum, work=0),
  )
  assert_true(
    advance_original_current_state_document_read(read, 1)
    is CurrentDocumentContinue(work=1),
  )
  cancel_original_current_state_document_read(read)
  assert_true(read.document is None && borrowed.source is None)
  assert_eq(
    @decode.text(@decode.element_at(source, 0).unwrap()),
    Ok("x".repeat(65)),
  )
  assert_true(
    advance_original_current_state_document_read(read, 1)
    is CurrentDocumentFailed(Terminal, work=0),
  )
}

///|
test "current document comparison detects changed state record phase and foreign origin" {
  let (ledger, origin, _, consumer) = current_state_test_consumer(17)
  let park = park_original_resource_consumer_for_state_write(consumer, origin).unwrap()
  let document = current_document_test_read(current_document_test_wire())
  assert_true(
    start_original_current_state_comparison(
      park,
      original_read_test_origin(),
      document,
      3,
    )
    is Err(Original(ChangedOriginalState)),
  )
  assert_true(
    start_original_current_state_comparison(park, origin, document, 2)
    is Err(WorkLimit),
  )
  for
    wire in [
      current_document_test_wire().replace(
        old="\"10\",\"7\",\"10\"",
        new="\"11\",\"7\",\"10\"",
      ),
      current_document_test_wire().replace(
        old="[\"-2\",\"0\",\"7\",\"5\"",
        new="[\"-2\",\"0\",\"8\",\"5\"",
      ),
      current_document_test_wire().replace(old="\"parked\"", new="\"stopping\""),
    ] {
    let wrong = current_document_test_read(wire)
    let compare = start_original_current_state_comparison(
      park, origin, wrong, 3,
    ).unwrap()
    let mut refused = false
    for _ in 0..<3 {
      match advance_original_current_state_comparison(compare, 1) {
        ComparisonContinue(..) => ()
        ComparisonFailed(RecordMismatch, ..) => {
          refused = true
          break
        }
        _ => abort("foreign current data unexpectedly matched")
      }
    }
    assert_true(
      refused &&
      compare.park is None &&
      compare.document is None &&
      wrong.source is Some(_),
    )
    retire_original_current_state_document(wrong)
  }
  let compare = start_original_current_state_comparison(
    park, origin, document, 3,
  ).unwrap()
  assert_true(
    advance_original_current_state_comparison(compare, 1)
    is ComparisonContinue(work=1),
  )
  resource_park_test_invalidate(park)
  assert_true(
    advance_original_current_state_comparison(compare, 1)
    is ComparisonFailed(Original(ChangedOriginalState), work=1),
  )
  assert_true(
    compare.park is None &&
    compare.document is None &&
    document.source is Some(_),
  )
  retire_original_current_state_document(document)
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
}

///|
test "current document last attempt is not reinterpreted as the initial read token" {
  // Three current reservations: read (-2), Model capacity (-3), and an actual
  // pre-send attempt (0) with transfer 1 and zero retention. Five read/compare
  // blocks and nineteen writer blocks. The last record is NOT a byte read.
  let wire = "[\"actql-original-ledger-state/0.1\",[\"19\",\"16\",\"16\",\"100\",\"256\",\"256\"],[\"19\",\"0\",\"0\",\"0\",\"0\",\"1\",\"0\",\"12\",\"11\",\"12\",\"1\",\"4\",\"0\"],[\"0\",\"0\",\"0\"],null,[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]],[\"-4\",\"1\",\"0\"],[\"4\",\"0\",\"0\",true,true,false,\"parked\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false],[\"-3\",\"0\",\"2\",\"3\",true,false,null,null,[false,false,false],null,false,false],[\"0\",\"1\",\"0\",\"1\",true,false,null,null,[false,false,false],null,true,false]],[],[]]"
  let (ledger, origin, _, consumer) = current_state_test_consumer(19)
  let (_, capacity) = handoff_funded_read_consumer_capacity(
    consumer, origin, 2L, 3L,
  ).unwrap()
  let attempt = reserve_attempt(ledger, 1L, 0L, 1L).unwrap()
  let park = park_original_resource_consumer_for_state_write(consumer, origin).unwrap()
  let read = start_original_current_state_document_read(
    original_document_test_cursor(wire),
    4,
    0,
    0,
    5,
    current_document_test_limits(),
  ).unwrap()
  let document = match advance_original_current_state_document_read(read, 5) {
    CurrentDocumentComplete(value, work=5) => value
    _ => abort("current last attempt was treated as a read")
  }
  let compare = start_original_current_state_comparison(
    park, origin, document, 5,
  ).unwrap()
  assert_true(
    advance_original_current_state_comparison(compare, 5)
    is ComparisonComplete(work=5),
  )
  assert_eq(ledger_usage(ledger).planning_work, 19)
  retire_original_current_state_document(document)
  resource_park_test_invalidate(park)
  settle_reservation(ledger, attempt).unwrap()
  settle_capacity(ledger, capacity).unwrap()
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
}
