///|
priv enum DependencyCollectionCase {
  Original
  OtherArray
  SameBodyCopy
  ReplaceBeforeAdopt
  ReplaceAfterAdopt
  ForeignLookup
  ForeignPhase
  SettlementRefused
  OneShort
  CleanupPending
}

///|
fn exercise_keyed_dependency_collection(
  case : DependencyCollectionCase,
) -> Unit raise {
  let (lookup, cleanup) = keyed_wire_usage_fixture()
  defer assert_true(cleanup())
  let (foreign, close_foreign) = if case is ForeignLookup {
    keyed_wire_usage_fixture()
  } else {
    (lookup, () => true)
  }
  defer assert_true(close_foreign())
  guard lookup.left.composed is Some(left) &&
    left.origin is SourceEffectOrigin(parent) else {
    fail("original checked Source and Request")
  }
  let owner = keyed_lookup_source_metadata_state(lookup, parent.request).unwrap()
  let authority = if case is ForeignLookup { foreign } else { lookup }
  let other_phase = if case is ForeignLookup || case is ForeignPhase {
    Some(grow_keyed_lookup_protocol_metadata(authority, 1, 16L).unwrap())
  } else {
    None
  }
  let basis = (lookup.retained_bytes, lookup.execution_bytes)
  let original = Ref(None)
  let replacement = Ref(None)
  let blocker = Ref(None)
  let peak = Ref((0L, 0L))
  let builds = Ref(0)
  let adoptions = Ref(0)
  let reads = Ref(0)
  let same_owner = Ref(true)
  let original_before_replacement = Ref(false)
  let depth = 8
  let nodes = if case is SettlementRefused { 1 } else { 32 }
  let result = with_keyed_dependency_collection(
    lookup,
    nodes,
    depth,
    phase => {
      builds.val += 1
      let issued_phase = other_phase.unwrap_or(phase)
      let cursor = begin_keyed_dependency_serial_cursor(authority, issued_phase).unwrap()
      let body = measured_test_body(authority, cursor, "{\"x\":\"é\"}", 2)
      let bodies = [body]
      cursor.record_body(authority, bodies, 32).unwrap()
      if case is SettlementRefused {
        // The valid same body can occur in the unmeasured suffix. The
        // final extent walk still uses its independent one-node limit.
        bodies.push(body)
      }
      original.val = Some(bodies)
      let completion = cursor.seal(authority, bodies).unwrap()
      if case is ReplaceBeforeAdopt {
        let occupied = bodies.copy()
        replacement.val = Some(occupied)
        owner.dependency_bodies = Some(occupied)
      }
      peak.val = (lookup.retained_bytes, lookup.execution_bytes)
      Ok(completion)
    },
    bodies => {
      adoptions.val += 1
      let installed = match case {
        OtherArray => []
        SameBodyCopy => bodies.copy()
        _ => bodies
      }
      owner.dependency_bodies = Some(installed)
      if case is OtherArray || case is SameBodyCopy {
        replacement.val = Some(installed)
      }
      if case is Original || case is OneShort {
        // The existing settlement walk's depth, fixed frames and measured
        // witness controls. Keep all other execution headroom in a real
        // Reservation so the second arm leaves exactly one byte less.
        let frames = 4L * (depth.to_int64() + 1L) + 4L + 37L
        let scratch = (12L + frames) * 16L +
          (24L + 4L * frames + 16L + 4L * frames) * 8L
        let usage = @resources.ledger_usage(lookup.ledger)
        let limits = @resources.ledger_limits(lookup.ledger)
        blocker.val = Some(
          @resources.reserve_capacity(
            lookup.ledger,
            limits.retained_bytes -
            usage.held_bytes -
            usage.reserved_retention_bytes -
            scratch,
            limits.execution_bytes -
            usage.reserved_execution_bytes -
            scratch +
            (if case is OneShort { 1L } else { 0L }),
          ).unwrap(),
        )
      }
      if case is CleanupPending {
        @resources.mark_cleanup_pending(lookup.ledger, lookup.reservation).unwrap()
      }
      Ok(())
    },
    () => {
      reads.val += 1
      let actual = lookup.native_sources.unwrap()
      same_owner.val = same_owner.val && physical_equal(owner, actual)
      if reads.val == 2 && case is ReplaceAfterAdopt {
        original_before_replacement.val = physical_equal(
          actual.dependency_bodies.unwrap(),
          original.val.unwrap(),
        )
        let substituted = original.val.unwrap().copy()
        replacement.val = Some(substituted)
        actual.dependency_bodies = Some(substituted)
      }
      Ok(actual.dependency_bodies)
    },
  )
  assert_eq(builds.val, 1)
  assert_true(same_owner.val)
  if case is ReplaceAfterAdopt {
    assert_true(original_before_replacement.val)
  }
  assert_true(
    !lookup.growing && @resources.reservation_open(lookup.reservation),
  )
  assert_eq(
    @resources.reservation_capacity_amounts(lookup.ledger, lookup.reservation).unwrap(),
    (lookup.retained_bytes, lookup.execution_bytes),
  )
  if blocker.val is Some(reservation) {
    @resources.settle_capacity(lookup.ledger, reservation).unwrap()
  }
  match case {
    Original => {
      result.unwrap()
      assert_eq((adoptions.val, reads.val), (1, 2))
      assert_true(
        physical_equal(owner.dependency_bodies.unwrap(), original.val.unwrap()),
      )
      // Original protocol control slots, one-slot Array and same measured
      // body. No new temporary completion or extent-walk storage survives.
      let keep = 80L * 128L + 3L * 16L + 4L * 8L + 3L * 8L + 696L
      assert_eq(
        (lookup.retained_bytes, lookup.execution_bytes),
        (basis.0 + keep, basis.1 + keep),
      )
    }
    ForeignLookup | ForeignPhase => {
      assert_true(result is Err(Assembly("foreign_dependency_cursor")))
      assert_eq((adoptions.val, reads.val), (0, 0))
      assert_true(owner.dependency_bodies is None)
    }
    ReplaceBeforeAdopt => {
      assert_true(result is Err(Assembly("occupied_dependency_array_slot")))
      assert_eq((adoptions.val, reads.val), (0, 1))
    }
    OtherArray | SameBodyCopy | ReplaceAfterAdopt => {
      assert_true(result is Err(Assembly("foreign_adopted_dependency_array")))
      assert_eq((adoptions.val, reads.val), (1, 2))
    }
    SettlementRefused => {
      // The completed body is valid. Add a genuine returned unmeasured
      // body below a one-node final extent allowance before this check.
      assert_true(result is Err(Identity(@publication.Contract(Encoding))))
      assert_eq((adoptions.val, reads.val), (1, 2))
    }
    OneShort => {
      assert_true(result is Err(Physical(@resources.ExecutionLimit)))
      assert_eq((adoptions.val, reads.val), (1, 2))
    }
    CleanupPending => {
      assert_true(result is Err(Assembly("retired_dependency_cursor")))
      assert_eq((adoptions.val, reads.val), (1, 2))
      assert_true(@resources.reservation_pending(lookup.reservation))
    }
  }
  if case is Original {
    assert_true(
      lookup.retained_bytes < peak.val.0 && lookup.execution_bytes < peak.val.1,
    )
  } else {
    assert_true(
      lookup.retained_bytes >= peak.val.0 &&
      lookup.execution_bytes >= peak.val.1,
    )
    if replacement.val is Some(array) {
      assert_true(physical_equal(owner.dependency_bodies.unwrap(), array))
    } else if adoptions.val == 1 {
      assert_true(
        physical_equal(owner.dependency_bodies.unwrap(), original.val.unwrap()),
      )
    }
  }
  if case is Original || case is OneShort {
    let short = if case is OneShort { 1 } else { 0 }
    println(
      "KEYED_DEPENDENCY_SETTLEMENT short=\{short} basis=\{basis.0}/\{basis.1} adopted=\{peak.val.0}/\{peak.val.1} final=\{lookup.retained_bytes}/\{lookup.execution_bytes}",
    )
  }
  assert_true(cleanup())
  assert_true(owner.dependency_bodies is None)
  assert_true(!@resources.reservation_open(lookup.reservation))
}

///|
test "keyed dependency collection settles the exact adopted original at exact capacity" {
  exercise_keyed_dependency_collection(Original)
}

///|
test "keyed dependency collection refuses a different adopted Array" {
  exercise_keyed_dependency_collection(OtherArray)
}

///|
test "keyed dependency collection refuses an adopted Array copy with the same body" {
  exercise_keyed_dependency_collection(SameBodyCopy)
}

///|
test "keyed dependency collection refuses a replacement immediately before adoption" {
  exercise_keyed_dependency_collection(ReplaceBeforeAdopt)
}

///|
test "keyed dependency collection refuses a replacement after adoption" {
  exercise_keyed_dependency_collection(ReplaceAfterAdopt)
}

///|
test "keyed dependency collection refuses a completion from a foreign Lookup" {
  exercise_keyed_dependency_collection(ForeignLookup)
}

///|
test "keyed dependency collection refuses another construction on the same Lookup" {
  exercise_keyed_dependency_collection(ForeignPhase)
}

///|
test "keyed dependency collection leaves an adopted original after failed settlement" {
  exercise_keyed_dependency_collection(SettlementRefused)
}

///|
test "keyed dependency collection leaves an adopted original one byte short" {
  exercise_keyed_dependency_collection(OneShort)
}

///|
test "keyed dependency collection preserves actual pending cleanup without settling" {
  exercise_keyed_dependency_collection(CleanupPending)
}
