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
    fn(_) {
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
    fn(_) {
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
  let adopted : Ref[Array[@publication.CapturedEffectDependencyBody]?] = Ref(
    None,
  )
  let result = with_keyed_dependency_collection(
    lookup,
    1,
    8,
    fn(phase) {
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
      complete_unmeasured_keyed_dependencies(lookup, phase, [body])
    },
    bodies => {
      adopted.val = Some(bodies)
      Ok(())
    },
    () => Ok(adopted.val),
  )
  assert_true(result is Err(Identity(@publication.Contract(Encoding))))
  assert_true(
    !lookup.growing && @resources.reservation_open(lookup.reservation),
  )
  assert_eq(
    @publication.captured_effect_dependency_body_json(adopted.val.unwrap()[0]),
    wire,
  )
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
    fn(_) -> Result[KeyedProtocolBuilt[Unit], ClientKeyedRequestIssue] {
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
    fn(_) {
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

///|
test "managed scan construction retires its grow port before adoption and settles actual original extents" {
  let (lookup, cleanup) = keyed_wire_usage_fixture()
  defer assert_true(cleanup())
  let basis = (lookup.retained_bytes, lookup.execution_bytes)
  let escaped : Ref[
    ((@execution.ExecutionCapacity) -> Result[Unit, ClientKeyedRequestIssue])?,
  ] = Ref(None)
  let peak = Ref(0L)
  let build_fenced = Ref(false)
  let nested_refused = Ref(false)
  let adoption_fenced = Ref(false)
  let adoption_port_retired = Ref(false)
  let first = @execution.execution_capacity(8192L, 8192L).unwrap()
  let later = @execution.execution_capacity(16384L, 32768L).unwrap()
  let keep = @execution.execution_capacity(64L, 96L).unwrap()
  let settled = with_keyed_body_construction(
    lookup,
    first,
    0L,
    grow => {
      build_fenced.val = lookup.growing
      escaped.val = Some(grow)
      grow(later).unwrap()
      peak.val = lookup.retained_bytes
      nested_refused.val = with_keyed_body_construction(
          lookup,
          first,
          0L,
          _ => Ok(()),
          _ => Ok(()),
          _ => Some(keep),
        )
        is Err(Assembly("unavailable_body_construction"))
      Ok("original")
    },
    value => {
      adoption_fenced.val = lookup.growing
      adoption_port_retired.val = escaped.val.unwrap()(later)
        is Err(Assembly("unavailable_body_construction"))
      lookup.identity_bodies = Some((value, "schema"))
      Ok(())
    },
    _ => Some(keep),
  ).unwrap()
  assert_eq(settled.value, "original")
  assert_true(
    build_fenced.val &&
    nested_refused.val &&
    adoption_fenced.val &&
    adoption_port_retired.val,
  )
  // Independent fixed frame inventory:16 headers,12 references,30 words.
  let controls = 16L * 16L + 12L * 8L + 30L * 8L
  assert_eq(lookup.retained_bytes, basis.0 + controls + 64L)
  assert_eq(lookup.execution_bytes, basis.1 + controls + 96L)
  assert_true(lookup.retained_bytes < peak.val)
  assert_false(lookup.growing)
  let after = (lookup.retained_bytes, lookup.execution_bytes)
  assert_true(
    escaped.val.unwrap()(later)
    is Err(Assembly("unavailable_body_construction")),
  )
  assert_eq((lookup.retained_bytes, lookup.execution_bytes), after)
}

///|
test "managed scan construction preserves original peak on typed build or partial adoption failure" {
  for fail_build in [true, false] {
    let (lookup, cleanup) = keyed_wire_usage_fixture()
    let peak = Ref((0L, 0L))
    let escaped : Ref[
      ((@execution.ExecutionCapacity) -> Result[Unit, ClientKeyedRequestIssue])?,
    ] = Ref(None)
    let extent = @execution.execution_capacity(8192L, 16384L).unwrap()
    let retained_body = @execution.execution_capacity(128L, 128L).unwrap()
    let result = with_keyed_body_construction(
      lookup,
      extent,
      0L,
      grow => {
        escaped.val = Some(grow)
        peak.val = (lookup.retained_bytes, lookup.execution_bytes)
        if fail_build {
          Err(Assembly("original_scan_failure"))
        } else {
          Ok("body")
        }
      },
      body => {
        lookup.identity_bodies = Some((body, "schema"))
        Err(Assembly("original_adoption_failure"))
      },
      _ => Some(retained_body),
    )
    assert_true(
      if fail_build {
        result is Err(Assembly("original_scan_failure"))
      } else {
        result is Err(Assembly("original_adoption_failure"))
      },
    )
    assert_eq((lookup.retained_bytes, lookup.execution_bytes), peak.val)
    assert_true(@resources.reservation_open(lookup.reservation))
    assert_false(lookup.growing)
    assert_true(
      escaped.val.unwrap()(extent)
      is Err(Assembly("unavailable_body_construction")),
    )
    assert_eq(lookup.identity_bodies is Some(_), !fail_build)
    assert_true(cleanup())
  }
}

///|
test "managed scan construction retains adopted body on extent or cancellation refusal" {
  for cancel in [false, true] {
    let (lookup, cleanup) = keyed_wire_usage_fixture()
    let peak = Ref((0L, 0L))
    let extent = @execution.execution_capacity(8192L, 16384L).unwrap()
    let result = with_keyed_body_construction(
      lookup,
      extent,
      0L,
      _ => {
        peak.val = (lookup.retained_bytes, lookup.execution_bytes)
        Ok("body")
      },
      body => {
        lookup.identity_bodies = Some((body, "schema"))
        if cancel {
          stop_client_keyed_lookup_input(lookup)
        }
        Ok(())
      },
      _ => if cancel { Some(extent) } else { None },
    )
    assert_true(result is Err(_))
    assert_eq(lookup.identity_bodies.unwrap().0, "body")
    assert_eq((lookup.retained_bytes, lookup.execution_bytes), peak.val)
    assert_false(lookup.growing)
    assert_true(@resources.reservation_open(lookup.reservation))
    assert_true(cleanup())
  }
}

///|
test "managed scan construction funds its fixed frame and first scan before build at exact and one short" {
  for (retained_short, execution_short) in [(0L, 0L), (1L, 0L), (0L, 1L)] {
    let (lookup, cleanup) = keyed_wire_usage_fixture()
    let usage = @resources.ledger_usage(lookup.ledger)
    let limits = @resources.ledger_limits(lookup.ledger)
    let available_r = limits.retained_bytes -
      usage.held_bytes -
      usage.reserved_retention_bytes
    let available_e = limits.execution_bytes - usage.reserved_execution_bytes
    let needed = 8192L + 16L * 16L + 12L * 8L + 30L * 8L
    let blocker = @resources.reserve_capacity(
      lookup.ledger,
      available_r - needed + retained_short,
      available_e - needed + execution_short,
    ).unwrap()
    let built = Ref(false)
    let extent = @execution.execution_capacity(8192L, 8192L).unwrap()
    let result = with_keyed_body_construction(
      lookup,
      extent,
      0L,
      _ => {
        built.val = true
        Ok(())
      },
      _ => Ok(()),
      _ => Some(extent),
    )
    assert_eq(built.val, retained_short == 0L && execution_short == 0L)
    assert_true(
      if retained_short == 0L && execution_short == 0L {
        result is Ok(_)
      } else if retained_short != 0L {
        result is Err(Physical(@resources.RetentionLimit))
      } else {
        result is Err(Physical(@resources.ExecutionLimit))
      },
    )
    @resources.settle_capacity(lookup.ledger, blocker).unwrap()
    assert_true(cleanup())
  }
}

///|
test "managed scan construction refuses later growth without losing the first owned peak" {
  let (lookup, cleanup) = keyed_wire_usage_fixture()
  let usage = @resources.ledger_usage(lookup.ledger)
  let limits = @resources.ledger_limits(lookup.ledger)
  let available = limits.retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes
  let first_bytes = 8192L + 16L * 16L + 12L * 8L + 30L * 8L
  let blocker = @resources.reserve_capacity(
    lookup.ledger,
    available - first_bytes,
    0L,
  ).unwrap()
  let peak = Ref((0L, 0L))
  let adopted = Ref(false)
  let first = @execution.execution_capacity(8192L, 8192L).unwrap()
  let larger = @execution.execution_capacity(16384L, 16384L).unwrap()
  let result = with_keyed_body_construction(
    lookup,
    first,
    0L,
    grow => {
      peak.val = (lookup.retained_bytes, lookup.execution_bytes)
      grow(larger)
    },
    _ => {
      adopted.val = true
      Ok(())
    },
    _ => Some(first),
  )
  assert_true(result is Err(Physical(@resources.RetentionLimit)))
  assert_false(adopted.val)
  assert_false(lookup.growing)
  assert_eq((lookup.retained_bytes, lookup.execution_bytes), peak.val)
  assert_true(@resources.reservation_open(lookup.reservation))
  @resources.settle_capacity(lookup.ledger, blocker).unwrap()
  assert_true(cleanup())
}

///|
test "managed page scan returns actual original body after severing its scanner frame" {
  let (lookup, cleanup) = keyed_wire_usage_fixture()
  defer assert_true(cleanup())
  let original = lookup.left.composed.unwrap()
  // Finish this fixture's SAME empty response input. Request planning/transport
  // are deliberately outside this scan-component case.
  lookup.completed = Some(
    @execution.finish_admitted_input(lookup.input.unwrap()).unwrap(),
  )
  let read = keyed_lookup_supplied_read(lookup).unwrap()
  let capture = @execution.supplied_source_input_capture_capacity(
    lookup.completed.unwrap(),
  ).unwrap()
  keyed_lookup_body_grow(
    lookup,
    lookup.retained_bytes,
    lookup.execution_bytes,
    1024L,
    Some(capture),
  ).unwrap()
  let output = @execution.capture_generated_supplied_source_input(
    original.sequence,
    read,
    lookup.max_work,
    lookup.max_bytes,
  ).unwrap()
  // Only the existing scan component is selected here. No physical page,
  // transport receipt, RowRun capture or Native metadata grant is fabricated.
  let partial : ClientKeyedNativePageState = {
    read: Some(read),
    capture: None,
    output: Some(output),
    scan: None,
    receipt: None,
    result: None,
  }
  let first = @execution.completed_relation_identity_scan_start_construction_capacity(
    output,
    retain_body=true,
  ).unwrap()
  let wire : @execution.RowWireLimits = {
    max_bytes: 1000000,
    max_nodes: 100000,
    max_columns: 10,
    max_order_work: 100000,
    max_depth: 20,
  }
  let peak = Ref(0L)
  let settled = with_keyed_body_construction(
    lookup,
    first,
    1024L,
    grow => {
      let result = scan_client_keyed_native_page(
        lookup,
        partial,
        output,
        read,
        0,
        {
          max_nodes: 100000,
          max_text_bytes: 1000000,
          max_depth: 20,
          max_work: 1000000,
        },
        wire,
        wire,
        {
          max_fields: 10,
          max_bytes: 1000000,
          max_nodes: 100000,
          max_depth: 20,
        },
        1000000,
        None,
        grow,
      )
      peak.val = lookup.retained_bytes
      result
    },
    body => {
      lookup.identity_bodies = Some((body, "original-schema"))
      Ok(())
    },
    body => {
      match partial.receipt {
        Some(receipt) => keyed_identity_retained_capacity(receipt, body)
        None => None
      }
    },
  ).unwrap()
  assert_true(partial.scan is None)
  let receipt = partial.receipt.unwrap()
  assert_true(
    @execution.completed_relation_export_matches_output(receipt, output),
  )
  assert_eq(
    @execution.completed_relation_export_measurement(receipt).row_count,
    0,
  )
  assert_eq(lookup.identity_bodies.unwrap().0, settled.value)
  assert_true(lookup.retained_bytes < peak.val)
  @execution.cancel_completed_relation_export_receipt(receipt)
  partial.receipt = None
}
