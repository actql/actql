///|
// Independently authored canonical preimage, including the selected Node
// one-hour availability and its existing deletion/metadata windows.
fn original_retention_test_body(policy : String) -> String {
  "{\"available_until\":\"2026-11-18T01:00:00.000Z\",\"clock_contract_cid\":\"sha256:" +
  "3".repeat(64) +
  "\",\"delete_by\":\"2026-11-18T02:00:00.000Z\",\"effective_data_policy_cid\":\"" +
  policy +
  "\",\"extension_ceiling_at\":\"2026-11-25T00:00:00.000Z\",\"metadata_delete_by\":\"2026-11-25T00:00:00.000Z\",\"metadata_retention_policy_cid\":\"sha256:" +
  "2".repeat(64) +
  "\",\"retention_contract_cid\":\"sha256:" +
  "1".repeat(64) +
  "\",\"version\":\"actql-result-retention-policy/0.1\"}"
}

///|
fn original_retention_test_contract(
  policy : String,
) -> @publication.PublicationContract {
  @publication.seal_publication_contract(
    "result_retention_policy",
    original_retention_test_body(policy),
    10000,
    1000,
    32,
  ).unwrap()
}

///|
fn check_original_retention_test_result(
  value : @publication.PublicationContract,
  policy : String,
) -> Unit raise {
  let body = original_retention_test_body(policy)
  let cid = "sha256:" + @sha.hex(@utf8.encode(body))
  let wire = body.replace(
    old=",\"extension_ceiling_at\"",
    new=",\"effective_retention_policy_cid\":\"" +
      cid +
      "\",\"extension_ceiling_at\"",
  )
  assert_eq(@publication.publication_contract_identity(value), cid)
  assert_eq(@publication.publication_contract_json(value), wire)
}

///|
test "original retention rebind preserves the full independent wire and equal-policy original" {
  let original = effect_publication_values_original()
  bind_effect_publication_values(original).unwrap() |> ignore
  let policy = "sha256:" + "5".repeat(64)
  let selected = original_retention_test_contract(policy)
  let before = @resources.ledger_usage(original.parent.ledger)
  let same = rebind_installed_effect_result_retention(
    original.run,
    original.prepared,
    original.request,
    original.plan,
    selected,
    policy,
    10000,
    1000,
    32,
  ).unwrap()
  assert_true(physical_equal(same, selected))
  assert_eq(
    @resources.ledger_usage(original.parent.ledger).reserved_retention_bytes,
    before.reserved_retention_bytes +
    16L * (6L + 2L) +
    8L * (5L + 27L) +
    8L * (14L + 2L),
  )
  let next_policy = "sha256:" + "6".repeat(64)
  let changed = rebind_installed_effect_result_retention(
    original.run,
    original.prepared,
    original.request,
    original.plan,
    selected,
    next_policy,
    10000,
    1000,
    32,
  ).unwrap()
  check_original_retention_test_result(changed, next_policy)
  check_original_retention_test_result(selected, policy)
  assert_true(@publication.result_retention_bounds_equal(changed, selected))
  assert_true(
    @resources.ledger_usage(original.parent.ledger).reserved_retention_bytes >
    before.reserved_retention_bytes,
  )
  let held = @resources.ledger_usage(original.parent.ledger)
  assert_true(
    rebind_installed_effect_result_retention(
      original.run,
      original.prepared,
      original.request,
      { ..original.plan, },
      selected,
      next_policy,
      10000,
      1000,
      32,
    )
    is Err(Run(ForeignOriginal)),
  )
  assert_true(
    rebind_installed_effect_result_retention(
      original.run,
      original.prepared,
      original.request,
      original.plan,
      original.definition,
      next_policy,
      10000,
      1000,
      32,
    )
    is Err(Retention(@publication.InvalidObject)),
  )
  assert_true(
    rebind_installed_effect_result_retention(
      original.run,
      original.prepared,
      original.request,
      original.plan,
      selected,
      "unknown",
      10000,
      1000,
      32,
    )
    is Err(Retention(@publication.InvalidObject)),
  )
  assert_true(
    rebind_installed_effect_result_retention(
      original.run,
      original.prepared,
      original.request,
      original.plan,
      selected,
      policy,
      0,
      1000,
      32,
    )
    is Err(Retention(@publication.InvalidLimits)),
  )
  // The two admitted invalid-envelope/policy attempts retain their actual
  // control prefixes. Foreign Plan and invalid numeric limits add no prefix.
  assert_eq(
    @resources.ledger_usage(original.parent.ledger).reserved_retention_bytes,
    held.reserved_retention_bytes +
    2L * (16L * (6L + 2L) + 8L * (5L + 27L) + 8L * (14L + 2L)),
  )
  close_effect_publication_values(original)
}

///|
test "retention exact and one-short admission preserves the original Plan and already-funded execution peak" {
  for retained in [true, false] {
    let original = effect_publication_values_original()
    bind_effect_publication_values(original).unwrap() |> ignore
    let selected = original_retention_test_contract("sha256:" + "5".repeat(64))
    let policy = "sha256:" + "6".repeat(64)
    let holder = effect_unit_publication_body(
      original.run,
      original.plan,
      original.request,
    ).unwrap()
    let before = @resources.preparation_body_borrow_reserved_extents(holder).unwrap()
    let geometry = @publication.result_retention_policy_construction_geometry(
        selected, policy, 10000, 1000, 32,
      )
      .unwrap()
      .unwrap()
    let capacity = effect_unit_publication_capacity(
      [("result_retention_policy", geometry)],
      @publication.publication_contract_identity(selected),
    ).unwrap()
    let control = installed_effect_retention_control_capacity().unwrap()
    let control_r = 16L * (6L + 2L) + 8L * (5L + 27L) + 8L * (14L + 2L)
    assert_eq(@execution.execution_capacity_retained_bytes(control), control_r)
    let middle = (
      before.0 + control_r,
      Int64::max(
        before.1,
        before.0 + @execution.execution_capacity_execution_bytes(control),
      ),
    )
    let next_r = middle.0 +
      @execution.execution_capacity_retained_bytes(capacity)
    let next_e = Int64::max(
      middle.1,
      middle.0 + @execution.execution_capacity_execution_bytes(capacity),
    )
    let usage = @resources.ledger_usage(original.parent.ledger)
    let limits = @resources.ledger_limits(original.parent.ledger)
    if !retained && next_e == before.1 {
      // This original Plan's prior execution peak already dominates the writer.
      // Fill all remaining execution: no invented extra debit or false
      // one-short execution refusal is allowed for an unchanged peak.
      let pressure = @resources.reserve_capacity(
        original.parent.ledger,
        0L,
        limits.execution_bytes - usage.reserved_execution_bytes,
      ).unwrap()
      let issued = rebind_installed_effect_result_retention(
        original.run,
        original.prepared,
        original.request,
        original.plan,
        selected,
        policy,
        10000,
        1000,
        32,
      ).unwrap()
      check_original_retention_test_result(issued, policy)
      assert_eq(
        @resources.preparation_body_borrow_reserved_extents(holder),
        Ok((next_r, before.1)),
      )
      @resources.settle_capacity(original.parent.ledger, pressure).unwrap()
      close_effect_publication_values(original)
      continue
    }
    let short = match
      @resources.reserve_capacity(
        original.parent.ledger,
        if retained {
          limits.retained_bytes -
          usage.held_bytes -
          usage.reserved_retention_bytes -
          (next_r - before.0) +
          1L
        } else {
          0L
        },
        if retained {
          0L
        } else {
          limits.execution_bytes -
          usage.reserved_execution_bytes -
          (next_e - before.1) +
          1L
        },
      ) {
      Ok(value) => value
      Err(_) =>
        fail(
          "pressure setup: held=" +
          before.0.to_string() +
          "," +
          before.1.to_string() +
          "; next=" +
          next_r.to_string() +
          "," +
          next_e.to_string() +
          "; parent=" +
          usage.reserved_retention_bytes.to_string() +
          "," +
          usage.reserved_execution_bytes.to_string() +
          "; limits=" +
          limits.retained_bytes.to_string() +
          "," +
          limits.execution_bytes.to_string(),
        )
    }
    let refused = rebind_installed_effect_result_retention(
      original.run,
      original.prepared,
      original.request,
      original.plan,
      selected,
      policy,
      10000,
      1000,
      32,
    )
    assert_true(
      if retained {
        refused is Err(Run(Preparation(Resource(RetentionLimit))))
      } else {
        refused is Err(Run(Preparation(Resource(ExecutionLimit))))
      },
    )
    assert_eq(
      @resources.preparation_body_borrow_reserved_extents(holder),
      Ok(middle),
    )
    assert_true(
      physical_equal(
        effect_unit_publication_body(
          original.run,
          original.plan,
          original.request,
        ).unwrap(),
        holder,
      ),
    )
    @resources.settle_capacity(original.parent.ledger, short).unwrap()
    let usage = @resources.ledger_usage(original.parent.ledger)
    // Retry counts one actual control operation on the SAME charged prefix.
    let exact_r = middle.0 +
      control_r +
      @execution.execution_capacity_retained_bytes(capacity)
    let exact_e = Int64::max(
      Int64::max(
        middle.1,
        middle.0 + @execution.execution_capacity_execution_bytes(control),
      ),
      middle.0 +
      control_r +
      @execution.execution_capacity_execution_bytes(capacity),
    )
    let exact = @resources.reserve_capacity(
      original.parent.ledger,
      if retained {
        limits.retained_bytes -
        usage.reserved_retention_bytes -
        (exact_r - middle.0)
      } else {
        0L
      },
      if retained {
        0L
      } else {
        limits.execution_bytes -
        usage.reserved_execution_bytes -
        (exact_e - middle.1)
      },
    ).unwrap()
    let issued = rebind_installed_effect_result_retention(
      original.run,
      original.prepared,
      original.request,
      original.plan,
      selected,
      policy,
      10000,
      1000,
      32,
    ).unwrap()
    check_original_retention_test_result(issued, policy)
    assert_eq(
      @resources.preparation_body_borrow_reserved_extents(holder),
      Ok((exact_r, exact_e)),
    )
    @resources.settle_capacity(original.parent.ledger, exact).unwrap()
    close_effect_publication_values(original)
  }
}

///|
test "retention constructor fences current reentry and leaves failed original cleanup intact" {
  let action : Ref[() -> Unit] = Ref(() => ())
  let alive = Ref(true)
  let original = effect_publication_values_original(current=() => {
    (action.val)()
    alive.val
  })
  bind_effect_publication_values(original).unwrap() |> ignore
  let selected = original_retention_test_contract("sha256:" + "5".repeat(64))
  let policy = "sha256:" + "6".repeat(64)
  let blocked = Ref(false)
  action.val = () => {
    blocked.val = rebind_installed_effect_result_retention(
        original.run,
        original.prepared,
        original.request,
        original.plan,
        selected,
        policy,
        10000,
        1000,
        32,
      )
      is Err(Run(AlreadyBound))
  }
  rebind_installed_effect_result_retention(
    original.run,
    original.prepared,
    original.request,
    original.plan,
    selected,
    policy,
    10000,
    1000,
    32,
  ).unwrap()
  |> ignore
  assert_true(blocked.val)
  assert_false(original.run.effect_operation_opening)
  action.val = () => ()
  alive.val = false
  let before = @resources.ledger_usage(original.parent.ledger)
  assert_true(
    rebind_installed_effect_result_retention(
      original.run,
      original.prepared,
      original.request,
      original.plan,
      selected,
      policy,
      10000,
      1000,
      32,
    )
    is Err(Run(_)),
  )
  assert_eq(@resources.ledger_usage(original.parent.ledger), before)
  assert_false(original.run.effect_operation_opening)
  close_effect_publication_values(original)
  assert_true(
    rebind_installed_effect_result_retention(
      original.run,
      original.prepared,
      original.request,
      original.plan,
      selected,
      policy,
      10000,
      1000,
      32,
    )
    is Err(Run(_)),
  )
}

///|
test "retention measuring control is funded before either geometry or equal-policy result" {
  let original = effect_publication_values_original()
  bind_effect_publication_values(original).unwrap() |> ignore
  let policy = "sha256:" + "5".repeat(64)
  let selected = original_retention_test_contract(policy)
  let holder = effect_unit_publication_body(
    original.run,
    original.plan,
    original.request,
  ).unwrap()
  let before = @resources.preparation_body_borrow_reserved_extents(holder).unwrap()
  let usage = @resources.ledger_usage(original.parent.ledger)
  let limits = @resources.ledger_limits(original.parent.ledger)
  let amount = 16L * (6L + 2L) + 8L * (5L + 27L) + 8L * (14L + 2L)
  let short = @resources.reserve_capacity(
    original.parent.ledger,
    limits.retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes -
    amount +
    1L,
    0L,
  ).unwrap()
  assert_true(
    rebind_installed_effect_result_retention(
      original.run,
      original.prepared,
      original.request,
      original.plan,
      selected,
      policy,
      10000,
      1000,
      32,
    )
    is Err(Run(Preparation(Resource(RetentionLimit)))),
  )
  assert_eq(
    @resources.preparation_body_borrow_reserved_extents(holder),
    Ok(before),
  )
  assert_false(original.run.effect_operation_opening)
  @resources.settle_capacity(original.parent.ledger, short).unwrap()
  let exact = @resources.reserve_capacity(
    original.parent.ledger,
    limits.retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes -
    amount,
    0L,
  ).unwrap()
  let same = rebind_installed_effect_result_retention(
    original.run,
    original.prepared,
    original.request,
    original.plan,
    selected,
    policy,
    10000,
    1000,
    32,
  ).unwrap()
  assert_true(physical_equal(same, selected))
  assert_eq(
    @resources.preparation_body_borrow_reserved_extents(holder).unwrap().0,
    before.0 + amount,
  )
  @resources.settle_capacity(original.parent.ledger, exact).unwrap()
  close_effect_publication_values(original)
}
