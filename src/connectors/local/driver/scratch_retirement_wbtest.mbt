///|
test "managed scratch retirement keeps roots beyond one cleanup slice" {
  let cursor = local_managed_scratch_retirement()
  let bridges = Array::makei(70, index => Ref(Some(index)))
  let imports = Array::makei(3, index => Ref(Some(index + 100)))
  let reads : Array[Int?] = [Some(200), Some(201), Some(202), None, Some(204)]
  let cids : Array[String?] = [Some("first"), Some("second")]
  let issuers = [300, 301, 302, 303]
  assert_false(
    advance_local_managed_scratch_retirement(
      cursor, bridges, imports, reads, cids, issuers,
    ),
  )
  assert_true(cursor.phase == Bridges)
  assert_eq(cursor.index, 64)
  for index in 0..<70 {
    assert_eq(bridges[index].val, if index < 64 { None } else { Some(index) })
  }
  // These roots still belong to the same driver; its witness must stay false.
  assert_eq(imports.map(handle => handle.val), [Some(100), Some(101), Some(102)])
  assert_eq(reads, [Some(200), Some(201), Some(202), None, Some(204)])
  assert_eq(cids, [Some("first"), Some("second")])
  assert_eq(issuers, [300, 301, 302, 303])
  assert_true(
    advance_local_managed_scratch_retirement(
      cursor, bridges, imports, reads, cids, issuers,
    ),
  )
  assert_true(cursor.phase == Retired)
  assert_true(bridges.all(handle => handle.val is None))
  assert_true(imports.all(handle => handle.val is None))
  assert_eq(reads, [None, None, None, None, None])
  assert_eq(cids, [None, None])
  assert_true(issuers.is_empty())
  // A completed cursor does not perform cleanup again or manufacture work.
  assert_true(
    advance_local_managed_scratch_retirement(
      cursor, bridges, imports, reads, cids, issuers,
    ),
  )
}

///|
test "managed scratch retirement counts boundaries and issuer roots in its slice" {
  let cursor = local_managed_scratch_retirement()
  let bridges : Array[Ref[Int?]] = []
  let imports : Array[Ref[Int?]] = []
  let reads : Array[Int?] = []
  let cids : Array[String?] = []
  let issuers = Array::makei(130, index => index)
  // Four empty-collection boundaries leave sixty issuer pops in the first slice.
  assert_false(
    advance_local_managed_scratch_retirement(
      cursor, bridges, imports, reads, cids, issuers,
    ),
  )
  assert_true(cursor.phase == Issuers)
  assert_eq(issuers.length(), 70)
  assert_false(
    advance_local_managed_scratch_retirement(
      cursor, bridges, imports, reads, cids, issuers,
    ),
  )
  assert_eq(issuers, [0, 1, 2, 3, 4, 5])
  assert_true(
    advance_local_managed_scratch_retirement(
      cursor, bridges, imports, reads, cids, issuers,
    ),
  )
  assert_true(issuers.is_empty())
}

///|
test "managed scratch retirement closes an empty collection set" {
  let cursor = local_managed_scratch_retirement()
  let bridges : Array[Ref[Int?]] = []
  let imports : Array[Ref[Int?]] = []
  let reads : Array[Int?] = []
  let cids : Array[String?] = []
  let issuers : Array[Int] = []
  assert_true(
    advance_local_managed_scratch_retirement(
      cursor, bridges, imports, reads, cids, issuers,
    ),
  )
  assert_true(cursor.phase == Retired)
}

///|
test "managed scratch retirement requires the final phase boundary" {
  for bridge_count in [59, 60] {
    let cursor = local_managed_scratch_retirement()
    let bridges = Array::makei(bridge_count, index => Ref(Some(index)))
    let imports : Array[Ref[Int?]] = []
    let reads : Array[Int?] = []
    let cids : Array[String?] = []
    let issuers : Array[Int] = []
    // Each set needs its five phase boundaries even when later sets are empty.
    assert_eq(
      advance_local_managed_scratch_retirement(
        cursor, bridges, imports, reads, cids, issuers,
      ),
      bridge_count + 5 <= 64,
    )
    assert_true(bridges.all(handle => handle.val is None))
    assert_true(
      advance_local_managed_scratch_retirement(
        cursor, bridges, imports, reads, cids, issuers,
      ),
    )
    assert_true(cursor.phase == Retired)
  }
}

///|
test "managed scratch retirement waits for a reentrant callback to return" {
  let cursor = local_managed_scratch_retirement()
  let uses = Ref(0)
  let disposed = Ref(false)
  let bridges = [Ref(Some(7))]
  let imports : Array[Ref[Int?]] = []
  let reads : Array[Int?] = []
  let cids : Array[String?] = []
  let issuers : Array[Int] = []
  let release = fn() {
    if disposed.val && uses.val == 0 {
      advance_local_managed_scratch_retirement(
        cursor, bridges, imports, reads, cids, issuers,
      )
      |> ignore
    }
  }
  let during : Ref[(Int?, Bool, Int)] = Ref((None, false, 0))
  with_managed_scratch_use(uses, release, fn() {
    disposed.val = true
    release()
    during.val = (bridges[0].val, cursor.phase == Bridges, uses.val)
  })
  assert_eq(during.val, (Some(7), true, 1))
  assert_eq(uses.val, 0)
  assert_true(cursor.phase == Retired)
  assert_eq(bridges[0].val, None)
}

///|
test "managed input writes cannot repopulate settled or disposed scratch" {
  for live in [false, true] {
    for settled in [false, true] {
      for disposed in [false, true] {
        assert_eq(
          local_managed_input_writes_open(live, settled, disposed),
          live && !settled && !disposed,
        )
      }
    }
  }
}

///|
test "completed provider scratch keeps its same pending cleanup owner" {
  let stopped = Ref(false)
  let retained = Ref(false)
  let cleaned = Ref(false)
  let cleanup_error = Ref(false)
  let checks = Ref(0)
  let owner = @local.managed_provider_execution_with_retained_completion(
    _ => Ok(@local.managed_provider_stopped_poll(0L, 0L)),
    () => false,
    () => stopped.val,
    () => {
      if cleanup_error.val {
        Err(@connector.InvalidLimits)
      } else {
        Ok(cleaned.val)
      }
    },
    () => {
      checks.val += 1
      retained.val
    },
  )
  let provider : Ref[@local.ManagedProviderExecution?] = Ref(Some(owner))
  let detached = Ref(false)
  let work : Ref[Result[Int64, @local.ManagedProviderWorkIssue]] = Ref(Ok(0L))
  assert_false(
    release_local_managed_provider_scratch(provider, detached, true, work),
  )
  assert_eq(checks.val, 0)
  stopped.val = true
  assert_false(
    release_local_managed_provider_scratch(provider, detached, true, work),
  )
  retained.val = true
  assert_false(
    release_local_managed_provider_scratch(provider, detached, false, work),
  )
  cleanup_error.val = true
  assert_false(
    release_local_managed_provider_scratch(provider, detached, true, work),
  )
  assert_false(detached.val)
  cleanup_error.val = false
  assert_true(
    release_local_managed_provider_scratch(provider, detached, true, work),
  )
  assert_true(detached.val)
  assert_true(provider.val is Some(same) && physical_equal(same, owner))
  assert_false(@local.cleanup_managed_provider(owner).unwrap())
  assert_eq(work.val, Ok(0L))
  // A later cancellation does not turn this scratch fact into full cleanup.
  assert_false(
    release_local_managed_provider_scratch(provider, detached, false, work),
  )
  assert_true(provider.val is Some(_))
  cleaned.val = true
  assert_true(
    release_local_managed_provider_scratch(provider, detached, false, work),
  )
  assert_true(provider.val is None)
}
