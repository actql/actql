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
test "serial dependency admission reuses only completed cursor workspace at exact and one short" {
  for short in [0L, 1L] {
    let (lookup, cleanup) = keyed_wire_usage_fixture()
    reserve_keyed_dependency_serial_controls(lookup).unwrap()
    let r = lookup.retained_bytes
    let e = lookup.execution_bytes
    let cursor : KeyedDependencySerialCursor = { reusable: 0L, pending: -1L, }
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
    assert_eq(lookup.retained_bytes, r + first_retained)
    assert_eq(lookup.execution_bytes, e + first_retained + first_cursor)
    assert_eq(cursor.reusable, 0L)
    assert_true(
      grow_keyed_dependency_body(lookup, 2, 1, 1, Some(cursor))
      is Err(Assembly("live_dependency_cursor")),
    )
    cursor.retire()
    assert_eq(cursor.reusable, first_cursor)
    let charged = @resources.ledger_usage(lookup.ledger)
    let limits = @resources.ledger_limits(lookup.ledger)
    let second_retained = 3L * 256L + 2L * 7L * 8L + 4096L
    let blocker = @resources.reserve_capacity(
      lookup.ledger,
      0L,
      limits.execution_bytes -
      charged.reserved_execution_bytes -
      second_retained +
      short,
    ).unwrap()
    let second = admit_client_effect_dependency_capture_body(
      "request_values",
      Some(
        "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a",
      ),
      "{}",
      1024,
      32,
      8,
      prepare,
      () => true,
      wire_extent=Some((2, 1)),
    )
    if short == 0L {
      let (body, bytes) = second.unwrap()
      assert_eq(bytes, 2)
      assert_eq(@publication.captured_effect_dependency_body_json(body), "{}")
      assert_eq(lookup.retained_bytes, r + first_retained + second_retained)
      assert_eq(
        lookup.execution_bytes,
        e + first_retained + first_cursor + second_retained,
      )
      assert_eq(cursor.pending, 0L)
      cursor.retire()
    } else {
      assert_true(second is Err(ConstructionRefused))
      assert_true(primary.val is Some(Physical(@resources.ExecutionLimit)))
      assert_eq(lookup.retained_bytes, r + first_retained)
      assert_eq(lookup.execution_bytes, e + first_retained + first_cursor)
      assert_eq(cursor.pending, -1L)
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
