///|
test "protocol construction rejects a foreign original lookup before reconciliation" {
  let (first, cleanup_first) = keyed_wire_usage_fixture()
  defer assert_true(cleanup_first())
  let (second, cleanup_second) = keyed_wire_usage_fixture()
  defer assert_true(cleanup_second())
  let phase = grow_keyed_lookup_protocol_metadata(first, 8192, 16L).unwrap()
  let before = (second.retained_bytes, second.execution_bytes)
  assert_true(
    finish_keyed_lookup_protocol_metadata(second, phase, 32, 8, [])
    is Err(Assembly("foreign_protocol_construction")),
  )
  assert_eq((second.retained_bytes, second.execution_bytes), before)
}

///|
test "protocol construction cannot reconcile its original phase twice" {
  let (lookup, cleanup) = keyed_wire_usage_fixture()
  defer assert_true(cleanup())
  let phase = grow_keyed_lookup_protocol_metadata(lookup, 8192, 16L).unwrap()
  finish_keyed_lookup_protocol_metadata(lookup, phase, 32, 8, []).unwrap()
  let before = (lookup.retained_bytes, lookup.execution_bytes)
  assert_true(
    finish_keyed_lookup_protocol_metadata(lookup, phase, 32, 8, [])
    is Err(Assembly("retired_protocol_construction")),
  )
  assert_eq((lookup.retained_bytes, lookup.execution_bytes), before)
}

///|
test "managed protocol construction fences reentry but allows original internal growth" {
  let (lookup, cleanup) = keyed_wire_usage_fixture()
  defer assert_true(cleanup())
  let basis = lookup.retained_bytes
  let peak = Ref(0L)
  let building = Ref(false)
  let reentry_refused = Ref(false)
  let grown = Ref(false)
  let adopting = Ref(false)
  let wire = "{\"text\":\"é😀\"}"
  with_keyed_protocol_construction(
    lookup,
    8192,
    16L,
    32,
    8,
    fn() {
      building.val = lookup.growing
      reentry_refused.val = grow_keyed_lookup_protocol_metadata(lookup, 1, 1L)
        is Err(Assembly("unavailable_protocol_construction"))
      keyed_lookup_body_grow(
        lookup,
        lookup.retained_bytes,
        lookup.execution_bytes,
        128L,
        None,
      ).unwrap()
      grown.val = lookup.growing
      peak.val = lookup.retained_bytes
      Ok(keyed_protocol_built((), texts=[wire]))
    },
    _ => {
      adopting.val = lookup.growing
      lookup.identity_bodies = Some((wire, "schema"))
      Ok(())
    },
  ).unwrap()
  |> ignore
  assert_true(building.val && reentry_refused.val && grown.val && adopting.val)
  assert_true(!lookup.growing)
  assert_true(lookup.retained_bytes > basis && lookup.retained_bytes < peak.val)
  assert_eq(lookup.identity_bodies.unwrap().0, wire)
}

///|
test "managed protocol partial adoption preserves its first error and live backing" {
  let (lookup, cleanup) = keyed_wire_usage_fixture()
  defer assert_true(cleanup())
  let peak = Ref(0L)
  let wire = "{\"text\":\"é😀\"}"
  let result = with_keyed_protocol_construction(
    lookup,
    8192,
    16L,
    32,
    8,
    fn() {
      peak.val = lookup.retained_bytes
      Ok(keyed_protocol_built((), texts=[wire]))
    },
    _ => {
      lookup.identity_bodies = Some((wire, "schema"))
      Err(Assembly("original_partial_adoption"))
    },
  )
  assert_true(result is Err(Assembly("original_partial_adoption")))
  assert_true(
    !lookup.growing && @resources.reservation_open(lookup.reservation),
  )
  assert_eq(lookup.identity_bodies.unwrap().0, wire)
  assert_eq(lookup.retained_bytes, peak.val)
}

///|
test "managed protocol extent refusal retains already adopted originals for cleanup" {
  let (lookup, cleanup) = keyed_wire_usage_fixture()
  defer assert_true(cleanup())
  let peak = Ref(0L)
  let wire = "{\"text\":\"é😀\"}"
  let result = with_keyed_protocol_construction(
    lookup,
    8192,
    16L,
    1,
    8,
    fn() {
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
      peak.val = lookup.retained_bytes
      Ok(keyed_protocol_built((), dependency_bodies=Some([body])))
    },
    _ => {
      lookup.identity_bodies = Some((wire, "schema"))
      Ok(())
    },
  )
  assert_true(result is Err(Identity(@publication.Contract(Encoding))))
  assert_true(
    !lookup.growing && @resources.reservation_open(lookup.reservation),
  )
  assert_eq(lookup.identity_bodies.unwrap().0, wire)
  assert_true(lookup.retained_bytes >= peak.val)
}

///|
test "managed protocol typed build failure retains original reservation until cleanup" {
  let (lookup, cleanup) = keyed_wire_usage_fixture()
  defer assert_true(cleanup())
  let before = lookup.retained_bytes
  let adopted = Ref(false)
  let result = with_keyed_protocol_construction(
    lookup,
    8192,
    16L,
    32,
    8,
    fn() -> Result[KeyedProtocolBuilt[Unit], ClientKeyedRequestIssue] {
      Err(Assembly("original_builder_failure"))
    },
    _ => {
      adopted.val = true
      Ok(())
    },
  )
  assert_true(result is Err(Assembly("original_builder_failure")))
  assert_false(adopted.val)
  assert_false(lookup.growing)
  assert_true(lookup.retained_bytes > before)
  assert_true(@resources.reservation_open(lookup.reservation))
}

///|
test "managed protocol cancellation after adoption keeps backing without a settled exit" {
  let (lookup, cleanup) = keyed_wire_usage_fixture()
  defer assert_true(cleanup())
  let wire = "{\"text\":\"é😀\"}"
  let peak = Ref(0L)
  let result = with_keyed_protocol_construction(
    lookup,
    8192,
    16L,
    32,
    8,
    fn() {
      peak.val = lookup.retained_bytes
      Ok(keyed_protocol_built((), texts=[wire]))
    },
    _ => {
      lookup.identity_bodies = Some((wire, "schema"))
      stop_client_keyed_lookup_input(lookup)
      Ok(())
    },
  )
  assert_true(result is Err(Assembly("unavailable_protocol_workspace_return")))
  assert_eq(lookup.identity_bodies.unwrap().0, wire)
  assert_eq(lookup.retained_bytes, peak.val)
  assert_false(lookup.growing)
  assert_true(@resources.reservation_open(lookup.reservation))
}
