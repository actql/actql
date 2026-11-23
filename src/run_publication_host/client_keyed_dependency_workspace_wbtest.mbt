///|
fn dependency_workspace_remainder(max_bytes : Int) -> Int64 raise {
  let (lookup, cleanup) = keyed_wire_usage_fixture()
  defer assert_true(cleanup())
  let basis = lookup.retained_bytes
  let phase = grow_keyed_lookup_protocol_metadata(lookup, max_bytes, 16L).unwrap()
  let peak = lookup.retained_bytes
  let wire = "{\"text\":\"é😀\"}"
  let body = @publication.admit_captured_effect_dependency_body(
    "request_values",
    Some(
      "sha256:57b49edd43272356030c99e378b47a57afb9939853ca59a7c13975d5ce79b854",
    ),
    wire,
    1024,
    32,
    8,
  ).unwrap()
  let identity = @publication.captured_effect_dependency_body_cid(body)
  finish_keyed_lookup_protocol_metadata(
    lookup,
    phase,
    32,
    8,
    [],
    dependency_bodies=Some([body]),
  ).unwrap()
  assert_true(lookup.retained_bytes > basis)
  assert_true(lookup.retained_bytes < peak)
  assert_eq(@publication.captured_effect_dependency_body_json(body), wire)
  assert_eq(@publication.captured_effect_dependency_body_cid(body), identity)
  assert_true(@resources.reservation_open(lookup.reservation))
  lookup.retained_bytes - basis
}

///|
test "finished dependency collector retains the same original backing independent of its constructor ceiling" {
  assert_eq(
    dependency_workspace_remainder(8192),
    dependency_workspace_remainder(32768),
  )
}

///|
test "dependency extent refusal keeps its constructor backing until original cleanup" {
  let (lookup, cleanup) = keyed_wire_usage_fixture()
  defer assert_true(cleanup())
  let phase = grow_keyed_lookup_protocol_metadata(lookup, 8192, 16L).unwrap()
  let peak = lookup.retained_bytes
  let body = @publication.admit_captured_effect_dependency_body(
    "request_values",
    Some(
      "sha256:57b49edd43272356030c99e378b47a57afb9939853ca59a7c13975d5ce79b854",
    ),
    "{\"text\":\"é😀\"}",
    1024,
    32,
    8,
  ).unwrap()
  assert_true(
    finish_keyed_lookup_protocol_metadata(
      lookup,
      phase,
      1,
      8,
      [],
      dependency_bodies=Some([body]),
    )
    is Err(Identity(@publication.Contract(Encoding))),
  )
  assert_true(lookup.retained_bytes >= peak)
  assert_true(@resources.reservation_open(lookup.reservation))
}

///|
test "serial dependency admission retains adopted extent and reuses completed workspace at exact and one short" {
  for (deeper, short) in [(false, 0L), (false, 1L), (true, 0L), (true, 1L)] {
    let (lookup, cleanup) = keyed_wire_usage_fixture()
    let cursor = begin_keyed_dependency_serial_cursor(lookup).unwrap()
    let r = lookup.retained_bytes
    let e = lookup.execution_bytes
    let primary : Ref[ClientKeyedRequestIssue?] = Ref(None)
    let prepare = Some((bytes, nodes, depth) => {
      match
        grow_keyed_dependency_body(lookup, bytes, nodes, depth, Some(cursor)) {
        Ok(_) => true
        Err(issue) => {
          primary.val = Some(issue)
          false
        }
      }
    })
    let first = admit_client_effect_dependency_capture_body(
        "request_values",
        Some(
          "sha256:97f06f396a709c3a29824e1cc794eeb98e2d1a262d7d455439d286d42803f0fe",
        ),
        "{\"x\":\"é\"}",
        1024,
        32,
        8,
        prepare,
        () => true,
        wire_extent=Some((10, 2)),
      ).unwrap().0
    // Independent quote from the original tariff and fixture geometry.
    let first_retained = 2L * 3L * 256L + 10L * 7L * 8L + 4096L
    let first_cursor = (2L + 1L) * 2L * 256L
    // One root frame plus the bounded depth-two stack and conversion carriers.
    let first_stack = (4L * (2L + 1L) + 20L) * (16L + 4L * 8L + 4L * 8L)
    assert_eq(cursor.extent_workspace_depth, 2)
    assert_eq(lookup.retained_bytes, r + first_stack + first_retained)
    assert_eq(
      lookup.execution_bytes,
      e + first_stack + first_retained + first_cursor,
    )
    assert_eq(cursor.available_execution, 0L)
    assert_true(
      grow_keyed_dependency_body(lookup, 2, 1, 1, Some(cursor))
      is Err(Assembly("live_dependency_cursor")),
    )
    let bodies = [first]
    cursor.record_body(lookup, bodies, 32).unwrap()
    // Body/node, usage and empty edge Array (9H/9R/7W), plus the
    // two-node object, two strings and its one backing pair (8H/7R/6W).
    let first_extent = 17L * 16L + 16L * 8L + 13L * 8L + 96L * 2L
    let first_keep = 4096L + first_extent
    assert_eq(cursor.available_retained, first_retained - first_keep)
    assert_eq(
      cursor.available_execution,
      first_retained + first_cursor - first_keep,
    )
    let charged = @resources.ledger_usage(lookup.ledger)
    let limits = @resources.ledger_limits(lookup.ledger)
    let (wire, cid, second_bytes, second_nodes) = if deeper {
      (
        "{\"x\":{\"y\":\"é\"}}", "sha256:75a66b3f24b3ab631f3c1a7582c6da55ec0d4fa59a64227accbc3a66ba94c760",
        16, 3,
      )
    } else {
      (
        "{}", "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a",
        2, 1,
      )
    }
    let second_retained = second_nodes.to_int64() * 3L * 256L +
      second_bytes.to_int64() * 7L * 8L +
      4096L
    let second_stack = if deeper { 4L * (16L + 4L * 8L + 4L * 8L) } else { 0L }
    let requested_r = second_retained - (first_retained - first_keep)
    let requested_e = second_retained +
      (second_nodes.to_int64() + 1L) * 2L * 256L -
      (first_retained + first_cursor - first_keep)
    let grown_e = Int64::max(requested_r, requested_e)
    let blocker = @resources.reserve_capacity(
      lookup.ledger,
      0L,
      limits.execution_bytes -
      charged.reserved_execution_bytes -
      grown_e -
      second_stack +
      short,
    ).unwrap()
    let second = admit_client_effect_dependency_capture_body(
      "request_values",
      Some(cid),
      wire,
      1024,
      32,
      8,
      prepare,
      () => true,
      wire_extent=Some((second_bytes, second_nodes)),
    )
    if short == 0L {
      let (body, bytes) = second.unwrap()
      assert_eq(bytes, second_bytes)
      assert_eq(@publication.captured_effect_dependency_body_json(body), wire)
      assert_eq(
        lookup.retained_bytes,
        r + first_stack + first_retained + requested_r + second_stack,
      )
      assert_eq(
        lookup.execution_bytes,
        e + first_stack + first_retained + first_cursor + grown_e + second_stack,
      )
      assert_true(
        grow_keyed_dependency_body(lookup, 2, 1, 1, Some(cursor))
        is Err(Assembly("live_dependency_cursor")),
      )
      bodies.push(body)
      cursor.record_body(lookup, bodies, 32).unwrap()
      let ReturnedKeyedDependencyRange(end~, ..) = cursor.measured.unwrap()
      assert_eq(end, 2)
      assert_eq(cursor.extent_workspace_depth, if deeper { 3 } else { 2 })
    } else {
      assert_true(second is Err(ConstructionRefused))
      assert_true(primary.val is Some(Physical(@resources.ExecutionLimit)))
      assert_eq(lookup.retained_bytes, r + first_stack + first_retained)
      assert_eq(
        lookup.execution_bytes,
        e + first_stack + first_retained + first_cursor,
      )
      assert_eq(cursor.pending_retained, -1L)
      assert_eq(cursor.extent_workspace_depth, 2)
    }
    assert_eq(
      @publication.captured_effect_dependency_body_json(first),
      "{\"x\":\"é\"}",
    )
    assert_true(@resources.reservation_open(lookup.reservation))
    @resources.settle_capacity(lookup.ledger, blocker).unwrap()
    assert_true(cleanup())
  }
}

///|
test "measured dependency extent binds the adopted collector Array before settlement" {
  for foreign in [false, true] {
    let (lookup, cleanup) = keyed_wire_usage_fixture()
    let basis_r = lookup.retained_bytes
    let basis_e = lookup.execution_bytes
    let phase = grow_keyed_lookup_protocol_metadata(lookup, 8192, 16L).unwrap()
    let cursor = begin_keyed_dependency_serial_cursor(lookup).unwrap()
    let body = admit_client_effect_dependency_capture_body(
        "request_values",
        Some(
          "sha256:97f06f396a709c3a29824e1cc794eeb98e2d1a262d7d455439d286d42803f0fe",
        ),
        "{\"x\":\"é\"}",
        1024,
        32,
        8,
        Some((bytes, nodes, depth) => {
          grow_keyed_dependency_body(lookup, bytes, nodes, depth, Some(cursor))
          is Ok(_)
        }),
        () => true,
        wire_extent=Some((10, 2)),
      ).unwrap().0
    let bodies = [body]
    cursor.record_body(lookup, bodies, 32).unwrap()
    let adopted = if foreign { [body] } else { bodies }
    let peak_r = lookup.retained_bytes
    let peak_e = lookup.execution_bytes
    let done = finish_keyed_lookup_protocol_metadata(
      lookup,
      phase,
      32,
      8,
      [],
      dependencies=Measured(adopted, cursor.seal(lookup).unwrap().unwrap()),
    )
    if foreign {
      assert_true(done is Err(Assembly("foreign_dependency_body_extent")))
      assert_true(lookup.retained_bytes >= peak_r)
      assert_true(lookup.execution_bytes >= peak_e)
    } else {
      done.unwrap()
      // The original protocol controls, Array wrapper/backing with one
      // slot and owning alias (3H/4R/3W), then the single measured body.
      let keep = 16L * 128L +
        3L * 16L +
        4L * 8L +
        3L * 8L +
        17L * 16L +
        16L * 8L +
        13L * 8L +
        96L * 2L
      assert_eq(lookup.retained_bytes, basis_r + keep)
      assert_eq(lookup.execution_bytes, basis_e + keep)
    }
    assert_true(@resources.reservation_open(lookup.reservation))
    assert_true(cleanup())
  }
}

///|
test "policy batch keeps both construction quotes and settles disjoint adopted ranges" {
  let (lookup, cleanup) = keyed_wire_usage_fixture()
  defer assert_true(cleanup())
  let basis_r = lookup.retained_bytes
  let basis_e = lookup.execution_bytes
  let phase = grow_keyed_lookup_protocol_metadata(lookup, 8192, 16L).unwrap()
  let cursor = begin_keyed_dependency_serial_cursor(lookup).unwrap()
  let serial = Some(cursor)
  let bodies = Array(capacity=3)
  fn collect(
    wire : String,
    cid : String,
    bytes : Int,
    nodes : Int,
    meter : KeyedDependencySerialCursor?,
  ) -> Unit {
    let (body, _) = admit_client_effect_dependency_capture_body(
      "request_values",
      Some(cid),
      wire,
      1024,
      32,
      8,
      Some((b, n, d) => {
        grow_keyed_dependency_body(lookup, b, n, d, meter) is Ok(_)
      }),
      () => true,
      wire_extent=Some((bytes, nodes)),
    ).unwrap()
    bodies.push(body)
  }
  collect(
    "{}", "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a",
    2, 1, serial,
  )
  cursor.record_body(lookup, bodies, 32).unwrap()
  collect(
    "{\"x\":\"é\"}",
    "sha256:97f06f396a709c3a29824e1cc794eeb98e2d1a262d7d455439d286d42803f0fe",
    10,
    2,
    None,
  )
  cursor.begin_batch(lookup, bodies.length()).unwrap()
  grow_keyed_dependency_body(lookup, 16, 3, 3, serial).unwrap()
  // The writer offers immutable text to admission. Keep both peaks until the
  // external policy invocation returns and the body belongs to the collector.
  collect(
    "{\"x\":{\"y\":\"é\"}}", "sha256:75a66b3f24b3ab631f3c1a7582c6da55ec0d4fa59a64227accbc3a66ba94c760",
    16, 3, serial,
  )
  let retained = 3L * 3L * 256L + 16L * 7L * 8L + 4096L
  let execution = retained + (3L + 1L) * 2L * 256L
  assert_eq(cursor.pending_retained, 2L * retained)
  assert_eq(cursor.pending_execution, 2L * execution)
  let ReturnedKeyedDependencyRange(end~, ..) = cursor.measured.unwrap()
  assert_eq(end, 1)
  assert_eq(cursor.available_retained, 0L)
  assert_eq(cursor.available_execution, 0L)
  cursor.record_body(lookup, bodies, 32).unwrap()
  let measured = cursor.measured.unwrap()
  let ReturnedKeyedDependencyRange(start~, end~, previous~, ..) = measured
  assert_eq((start, end), (2, 3))
  let ReturnedKeyedDependencyRange(start~, end~, ..) = previous.unwrap()
  assert_eq((start, end), (0, 1))
  assert_eq(cursor.pending_retained, -1L)
  finish_keyed_lookup_protocol_metadata(
    lookup,
    phase,
    32,
    8,
    [],
    dependencies=Measured(bodies, cursor.seal(lookup).unwrap().unwrap()),
  ).unwrap()
  // Two measured bodies and the unmeasured gap, independently priced.
  // The outer Array is H3/R6/W3, including its adopted alias.
  let keep = 16L * 128L + 3L * 16L + 6L * 8L + 3L * 8L + 566L + 696L + 886L
  assert_eq(lookup.retained_bytes, basis_r + keep)
  assert_eq(lookup.execution_bytes, basis_e + keep)
}

///|
test "a foreign cursor and its completed proof cannot use another live lookup" {
  let (original, close_original) = keyed_wire_usage_fixture()
  defer assert_true(close_original())
  let (foreign, close_foreign) = keyed_wire_usage_fixture()
  defer assert_true(close_foreign())
  let cursor = begin_keyed_dependency_serial_cursor(original).unwrap()
  let body = admit_client_effect_dependency_capture_body(
      "request_values",
      Some(
        "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a",
      ),
      "{}",
      1024,
      32,
      8,
      Some((bytes, nodes, depth) => {
        grow_keyed_dependency_body(original, bytes, nodes, depth, Some(cursor))
        is Ok(_)
      }),
      () => true,
      wire_extent=Some((2, 1)),
    ).unwrap().0
  let bodies = [body]
  cursor.record_body(original, bodies, 32).unwrap()
  assert_true(cursor.available_retained > 0L && cursor.available_execution > 0L)
  let reusable = (cursor.available_retained, cursor.available_execution)
  let original_usage = @resources.ledger_usage(original.ledger)
  let phase = grow_keyed_lookup_protocol_metadata(foreign, 8192, 16L).unwrap()
  let foreign_usage = @resources.ledger_usage(foreign.ledger)
  let foreign_bytes = (foreign.retained_bytes, foreign.execution_bytes)
  assert_true(
    grow_keyed_dependency_body(foreign, 2, 1, 1, Some(cursor))
    is Err(Assembly("foreign_dependency_cursor")),
  )
  assert_true(
    cursor.begin_batch(foreign, 1) is Err(Assembly("foreign_dependency_cursor")),
  )
  assert_true(
    cursor.record_body(foreign, bodies, 32)
    is Err(Assembly("foreign_dependency_cursor")),
  )
  assert_true(
    cursor.seal(foreign) is Err(Assembly("foreign_dependency_cursor")),
  )
  assert_eq(cursor.batch_start, -1)
  assert_eq((cursor.available_retained, cursor.available_execution), reusable)
  assert_eq(@resources.ledger_usage(original.ledger), original_usage)
  let proof = cursor.seal(original).unwrap().unwrap()
  assert_true(
    cursor.seal(original) is Err(Assembly("retired_dependency_cursor")),
  )
  assert_true(
    finish_keyed_lookup_protocol_metadata(
      foreign,
      phase,
      32,
      8,
      [],
      dependencies=Measured(bodies, proof),
    )
    is Err(Assembly("foreign_dependency_cursor")),
  )
  assert_false(phase.finished)
  assert_eq((foreign.retained_bytes, foreign.execution_bytes), foreign_bytes)
  assert_eq(@resources.ledger_usage(foreign.ledger), foreign_usage)
  assert_eq(@resources.ledger_usage(original.ledger), original_usage)
}

///|
test "a stopped lookup keeps its original reservation but refuses cursor use" {
  let (lookup, cleanup) = keyed_wire_usage_fixture()
  defer assert_true(cleanup())
  let cursor = begin_keyed_dependency_serial_cursor(lookup).unwrap()
  grow_keyed_dependency_body(lookup, 2, 1, 1, Some(cursor)).unwrap()
  let original = (lookup.retained_bytes, lookup.execution_bytes)
  let usage = @resources.ledger_usage(lookup.ledger)
  let pending = cursor.pending_retained
  stop_client_keyed_lookup_input(lookup)
  assert_true(@resources.reservation_open(lookup.reservation))
  assert_true(
    begin_keyed_dependency_serial_cursor(lookup)
    is Err(Assembly("retired_dependency_cursor")),
  )
  assert_true(
    grow_keyed_dependency_body(lookup, 2, 1, 1, Some(cursor))
    is Err(Assembly("retired_dependency_cursor")),
  )
  assert_true(
    cursor.begin_batch(lookup, 0) is Err(Assembly("retired_dependency_cursor")),
  )
  assert_true(
    cursor.record_body(lookup, [], 32)
    is Err(Assembly("retired_dependency_cursor")),
  )
  assert_true(cursor.seal(lookup) is Err(Assembly("retired_dependency_cursor")))
  assert_eq(cursor.pending_retained, pending)
  assert_eq((lookup.retained_bytes, lookup.execution_bytes), original)
  assert_eq(@resources.ledger_usage(lookup.ledger), usage)
}

///|
test "the cursor factory funds control backing exactly or refuses before issuing" {
  // Original 43H/67R/71W, plus ownership and overlapping Result carriers:
  // four new headers, eight references and four scalar words.
  let required = 43L * 16L + (67L + 71L) * 8L + 4L * 16L + (8L + 4L) * 8L
  for short in [0L, 1L] {
    let (lookup, cleanup) = keyed_wire_usage_fixture()
    defer assert_true(cleanup())
    let before = @resources.ledger_usage(lookup.ledger)
    let limit = @resources.ledger_limits(lookup.ledger).execution_bytes
    let blocker = @resources.reserve_capacity(
      lookup.ledger,
      0L,
      limit - before.reserved_execution_bytes - required + short,
    ).unwrap()
    defer @resources.settle_capacity(lookup.ledger, blocker).unwrap()
    let charged = @resources.ledger_usage(lookup.ledger)
    let retained = lookup.retained_bytes
    let execution = lookup.execution_bytes
    let cursor = begin_keyed_dependency_serial_cursor(lookup)
    if short == 0L {
      let cursor = cursor.unwrap()
      assert_true(physical_equal(cursor.lookup, lookup))
      assert_true(physical_equal(cursor.reservation, lookup.reservation))
      assert_eq(lookup.retained_bytes, retained + required)
      assert_eq(lookup.execution_bytes, execution + required)
      assert_eq(
        @resources.ledger_usage(lookup.ledger).reserved_execution_bytes,
        limit,
      )
    } else {
      assert_true(cursor is Err(Physical(@resources.ExecutionLimit)))
      assert_eq(
        (lookup.retained_bytes, lookup.execution_bytes),
        (retained, execution),
      )
      assert_eq(@resources.ledger_usage(lookup.ledger), charged)
      assert_true(@resources.reservation_open(lookup.reservation))
    }
  }
}
