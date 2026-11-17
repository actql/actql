///|
// The ordinary supplier must convert this foreign Host callback exception to
// its existing stopping status before the Resource phase cut can observe it.
#warnings("-deprecated")
extern "js" fn effect_material_throw_original_current() -> Unit =
  #|() => { throw new Error('OriginalEffectMaterialCurrentFailure'); }

///|
// Actual checked Request/Effect originals exercise the fixed material-codec
// resource scope. The supplied closed codec is a component port, not a Run,
// physical Source, publication ACK or ordinary-package acceptance.
test "Effect materials fund each actual projection before construction and reuse sequential scratch" {
  let (parent, input, prepared) = request_effect_compile_fixture()
  reserve_request_effect_plan(parent, input).unwrap()
  let capacity = parent.effect_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let calls = Ref(0)
  let checks = Ref(0)
  let peak = Ref((0L, 0L))
  let result = construct_request_effect_materials(parent, input, prepared, body => {
    if body("environment", 65537, 512, 8) {
      checks.val += 1
    }
    let first = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
    if first.0 > before.0 && first.1 > before.1 {
      checks.val += 1
    }
    if body("environment", 65537, 512, 8) {
      checks.val += 1
    }
    if @resources.preparation_capacity_working_extents(capacity, input).unwrap() ==
      first {
      checks.val += 1
    }
    if body("run_materials", 70000, 32, 2) {
      checks.val += 1
    }
    peak.val = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
    calls.val += 1
    Ok("complete-original")
  }).unwrap()
  assert_eq(result, "complete-original")
  assert_eq(calls.val, 1)
  assert_eq(checks.val, 5)
  let returned = @resources.preparation_capacity_working_extents(
    capacity, input,
  ).unwrap()
  assert_eq(returned.0, peak.val.0)
  assert_true(returned.1 < peak.val.1)
  assert_true(parent.phase == EffectPlanReserved)
  assert_eq(@resources.ledger_usage(parent.ledger).attempts, 0)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Effect materials keep the original byte-short refusal before allocating the body" {
  let (parent, input, prepared) = request_effect_compile_fixture()
  reserve_request_effect_plan(parent, input).unwrap()
  let capacity = parent.effect_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let (retained, _) = request_effect_material_body_layout(65537, 512, 8, false).unwrap()
  let limits = @resources.ledger_limits(parent.ledger)
  let usage = @resources.ledger_usage(parent.ledger)
  let blocker = @resources.reserve_capacity(
    parent.ledger,
    limits.retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes -
    request_effect_material_control_bytes -
    retained +
    1L,
    0L,
  ).unwrap()
  let built = Ref(false)
  let result : Result[String, ClientRequestProgramPlanIssue] = construct_request_effect_materials(
    parent,
    input,
    prepared,
    body => {
      if !body("environment", 65537, 512, 8) {
        return Err(
          @publication_host.Input(@publication_host.MaterialsMalformed),
        )
      }
      built.val = true
      Ok("unfunded")
    },
  )
  assert_true(result is Err(Preparation(Capacity(Resource(RetentionLimit)))))
  assert_false(built.val)
  let after = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  assert_eq(after.0, before.0 + request_effect_material_control_bytes)
  assert_eq(@resources.ledger_usage(parent.ledger).attempts, 0)
  @resources.settle_capacity(parent.ledger, blocker).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Effect material current refusal preserves its successful prefix and fences reentry" {
  let live = Ref(true)
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (parent, input, prepared) = request_effect_compile_fixture(current=() => {
    if action.val is Some(check) {
      check()
    }
    live.val
  })
  reserve_request_effect_plan(parent, input).unwrap()
  let capacity = parent.effect_capacity.unwrap()
  let prefix : Ref[(Int64, Int64)?] = Ref(None)
  let reentries = Ref(0)
  let accepted = Ref(false)
  let refused = Ref(false)
  action.val = Some(() => {
    let nested : Result[String, ClientRequestProgramPlanIssue] = construct_request_effect_materials(
      parent,
      input,
      prepared,
      _ => Ok("foreign-reentry"),
    )
    if nested is Err(Preparation(ForeignOriginal)) {
      reentries.val += 1
    }
  })
  let result : Result[String, ClientRequestProgramPlanIssue] = construct_request_effect_materials(
    parent,
    input,
    prepared,
    body => {
      accepted.val = body("environment", 65537, 512, 8)
      prefix.val = Some(
        @resources.preparation_capacity_working_extents(capacity, input).unwrap(),
      )
      live.val = false
      refused.val = !body("run_materials", 70000, 32, 2)
      Err(@publication_host.Input(@publication_host.MaterialsMalformed))
    },
  )
  assert_true(result is Err(Preparation(Capacity(_))))
  assert_true(reentries.val > 0)
  assert_true(accepted.val && refused.val)
  assert_eq(
    @resources.preparation_capacity_accounting(capacity).4,
    prefix.val.unwrap().0,
  )
  assert_eq(
    @resources.preparation_capacity_accounting(capacity).5,
    prefix.val.unwrap().1,
  )
  live.val = true
  action.val = None
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Effect material successful return cannot cut scratch after original current refusal or retire reentry" {
  for throws_current in [false, true] {
    let live = Ref(true)
    let action : Ref[(() -> Unit)?] = Ref(None)
    let (parent, input, prepared) = request_effect_compile_fixture(current=() => {
      if action.val is Some(check) {
        check()
      }
      live.val
    })
    reserve_request_effect_plan(parent, input).unwrap()
    let capacity = parent.effect_capacity.unwrap()
    let prefix = Ref((0L, 0L))
    let retire_refused = Ref(false)
    let request_refused = Ref(false)
    let result : Result[String, ClientRequestProgramPlanIssue] = construct_request_effect_materials(
      parent,
      input,
      prepared,
      body => {
        if !body("environment", 65537, 512, 8) {
          return Err(
            @publication_host.Input(@publication_host.MaterialsMalformed),
          )
        }
        prefix.val = @resources.preparation_capacity_working_extents(
          capacity, input,
        ).unwrap()
        // The next original current callback belongs to the success-only cut.
        action.val = Some(() => {
          retire_refused.val = @resources.retire_preparation_capacity(capacity)
            is Err(WorkActive)
          request_refused.val = abort_request_preparation_after_cleanup(parent)
            is Err(WrongPhase)
          if throws_current {
            effect_material_throw_original_current()
          } else {
            live.val = false
          }
        })
        Ok("returned-original")
      },
    )
    assert_true(result is Err(Preparation(Capacity(_))))
    assert_true(retire_refused.val && request_refused.val)
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      Ok(prefix.val),
    )
    assert_eq(
      @resources.preparation_capacity_accounting(capacity).4,
      prefix.val.0,
    )
    assert_eq(
      @resources.preparation_capacity_accounting(capacity).5,
      prefix.val.1,
    )
    assert_eq(@resources.ledger_usage(parent.ledger).attempts, 0)
    live.val = true
    action.val = None
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}
