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
  for short in [0L, 1L] {
    let (lookup, cleanup) = keyed_wire_usage_fixture()
    reserve_keyed_dependency_serial_controls(lookup, 8).unwrap()
    let r = lookup.retained_bytes
    let e = lookup.execution_bytes
    let cursor = new_keyed_dependency_serial_cursor()
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
    assert_eq(cursor.available_execution, 0L)
    assert_true(
      grow_keyed_dependency_body(lookup, 2, 1, 1, Some(cursor))
      is Err(Assembly("live_dependency_cursor")),
    )
    let bodies = [first]
    cursor.record_body(bodies, 32, 8).unwrap()
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
    let second_retained = 3L * 256L + 2L * 7L * 8L + 4096L
    let requested_r = second_retained - (first_retained - first_keep)
    let requested_e = second_retained +
      2L * 2L * 256L -
      (first_retained + first_cursor - first_keep)
    let grown_e = Int64::max(requested_r, requested_e)
    let blocker = @resources.reserve_capacity(
      lookup.ledger,
      0L,
      limits.execution_bytes -
      charged.reserved_execution_bytes -
      grown_e +
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
      assert_eq(lookup.retained_bytes, r + first_retained + requested_r)
      assert_eq(
        lookup.execution_bytes,
        e + first_retained + first_cursor + grown_e,
      )
      assert_true(
        grow_keyed_dependency_body(lookup, 2, 1, 1, Some(cursor))
        is Err(Assembly("live_dependency_cursor")),
      )
      bodies.push(body)
      cursor.record_body(bodies, 32, 8).unwrap()
      assert_eq(cursor.measured.unwrap().end, 2)
    } else {
      assert_true(second is Err(ConstructionRefused))
      assert_true(primary.val is Some(Physical(@resources.ExecutionLimit)))
      assert_eq(lookup.retained_bytes, r + first_retained)
      assert_eq(lookup.execution_bytes, e + first_retained + first_cursor)
      assert_eq(cursor.pending_retained, -1L)
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
    reserve_keyed_dependency_serial_controls(lookup, 8).unwrap()
    let cursor = new_keyed_dependency_serial_cursor()
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
    cursor.record_body(bodies, 32, 8).unwrap()
    let adopted = if foreign { [body] } else { bodies }
    let peak_r = lookup.retained_bytes
    let peak_e = lookup.execution_bytes
    let done = finish_keyed_lookup_protocol_metadata(
      lookup,
      phase,
      32,
      8,
      [],
      dependencies=Measured(adopted, cursor.measured.unwrap()),
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
