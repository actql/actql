///|
test "cold Unit validation preserves every temporary peak without escaping retention" {
  let (_, prepared, compiled, definition) = journal_test_run(
    "cold-temporary-request", "cold-temporary-run",
  )
  let original = capture_native_run_plan_original(
      prepared, compiled, definition,
    ).unwrap().original
  let working : Array[(Int64, Int64, Int64)] = []
  native_cold_plan_view_working(original, (r, e, raw) => {
    working.push((r, e, raw))
    Ok(())
  }).unwrap()
  let forwarded : Array[(Int64, Int64, Int64)] = []
  native_cold_plan_view(original, (r, e, raw) => {
    forwarded.push((r, e, raw))
    Ok(())
  }).unwrap()
  assert_eq(forwarded.length(), working.length() + 1)
  assert_eq(
    forwarded[0],
    (
      0L, native_cold_validation_control_bytes, native_cold_validation_control_raw,
    ),
  )
  let mut live = 0L
  for index in 0..<working.length() {
    let (r, e, raw) = working[index]
    let actual = forwarded[index + 1]
    assert_eq(actual.0, 0L)
    assert_eq(
      actual.1,
      native_cold_validation_control_bytes + live + Int64::max(r, e),
    )
    assert_eq(actual.2, Int64::max(raw, native_cold_validation_control_raw))
    live += r
  }
  assert_true(live > 0L)
  // Every original failure remains first and stops before the next protected
  // constructor. The new adapter's own prelude is included in that sequence.
  for refused in 1..<=forwarded.length() {
    let mut calls = 0
    assert_true(
      native_cold_plan_view(original, (_, _, _) => {
        calls += 1
        if calls == refused {
          Err(Encoding)
        } else {
          Ok(())
        }
      })
      is Err(Encoding),
    )
    assert_eq(calls, refused)
  }
}

///|
test "cold plan admission keeps canonical identity and requires every construction stage" {
  let (_, prepared, compiled, definition) = journal_test_run(
    "cold-plan-request", "cold-plan-run",
  )
  let captured = capture_native_run_plan_original(
    prepared, compiled, definition,
  ).unwrap()
  let original = captured.original
  let wire = native_run_plan_original_wire(original).unwrap()
  let mut calls = 0
  let accepted = read_native_run_plan_original(
    wire,
    definition,
    Some(captured.program_cid),
    before_construction=Some((r, e, raw) => {
      calls += 1
      assert_true(r >= 0L && e >= r && raw > 0L) catch {
        _ => return Err(Encoding)
      }
      Ok(())
    }),
  ).unwrap()
  assert_eq(accepted.view, original.view)
  assert_eq(
    @publication.publication_contract_json(accepted.plan),
    @publication.publication_contract_json(original.plan),
  )
  assert_true(calls > 6)
  for refused in 1..<=calls {
    let mut stage = 0
    assert_true(
      read_native_run_plan_original(
        wire,
        definition,
        Some(captured.program_cid),
        before_construction=Some((_, _, _) => {
          stage += 1
          if stage == refused {
            Err(CapacityExceeded)
          } else {
            Ok(())
          }
        }),
      )
      is Err(_),
    )
    assert_eq(stage, refused)
  }
}

///|
test "cold plan refuses noncanonical bytes and foreign compiled identity" {
  let (_, prepared, compiled, definition) = journal_test_run(
    "cold-reject-request", "cold-reject-run",
  )
  let captured = capture_native_run_plan_original(
    prepared, compiled, definition,
  ).unwrap()
  let plan_wire = @publication.publication_contract_json(captured.original.plan)
  assert_true(
    native_cold_compiled_plan(plan_wire + " ", (_, _, _) => Ok(()))
    is Err(CustodyLost),
  )
  assert_true(
    native_cold_compiled_plan(
      plan_wire.replace(
        old=@publication.publication_contract_identity(captured.original.plan),
        new="sha256:" + "f".repeat(64),
      ),
      (_, _, _) => Ok(()),
    )
    is Err(CustodyLost),
  )
  let altered : NativeClientRunPlanOriginal = {
    plan: captured.original.plan,
    view: captured.original.view + " ",
  }
  assert_true(
    native_cold_plan_view(altered, (_, _, _) => Ok(())) is Err(CustodyLost),
  )
  assert_true(
    validate_native_run_plan_original(
      captured.original,
      definition,
      Some("sha256:" + "0".repeat(64)),
      before_construction=Some((_, _, _) => Ok(())),
    )
    is Err(ForeignRun),
  )
}

///|
test "cold binding preserves valid empty logical map without inventing key codecs" {
  let (_, prepared, compiled, definition) = journal_test_run(
    "cold-empty-request", "cold-empty-run",
  )
  let captured = capture_native_run_plan_original(
    prepared, compiled, definition,
  ).unwrap()
  let plan = captured.original.plan
  let body = "{\"version\":\"actql-logical-map/0.1\",\"compiled_plan_cid\":\"" +
    @publication.publication_contract_identity(plan) +
    "\",\"program_definition_cid\":\"" +
    captured.program_cid +
    "\",\"steps\":[]}"
  let map = @publication.seal_run_evidence_value(
    "logical_map", body, 65536, 8192, 64,
  ).unwrap()
  assert_true(
    @publication.check_interactive_logical_map_binding(
      map, plan, 65536, 8192, 64,
    )
    is Ok(_),
  )
  let mut calls = 0
  assert_true(
    native_cold_plan_binding_working(map, plan, (65536, 8192, 64), (_, _, _) => {
      calls += 1
      Ok(())
    })
    is Ok(_),
  )
  assert_eq(calls, 2)
}

///|
test "cold plan rejects a valid resealed foreign logical map through binding" {
  let (_, prepared, compiled, definition) = journal_test_run(
    "cold-foreign-request", "cold-foreign-run",
  )
  let captured = capture_native_run_plan_original(
    prepared, compiled, definition,
  ).unwrap()
  let foreign_program = "sha256:" + "f".repeat(64)
  assert_true(foreign_program != captured.program_cid)
  let map = @publication.seal_run_evidence_value(
    "logical_map",
    "{\"version\":\"actql-logical-map/0.1\",\"compiled_plan_cid\":\"" +
    @publication.publication_contract_identity(captured.original.plan) +
    "\",\"program_definition_cid\":\"" +
    foreign_program +
    "\",\"steps\":[]}",
    65536,
    8192,
    64,
  ).unwrap()
  let json = @json.parse(captured.original.view)
  guard json is Object(fields) else { fail("expected plan_view object") }
  fields["logical_map"] = @json.parse(@publication.run_evidence_value_json(map))
  let view = @canonical.stringify_value(
    @canonical.from_json(json, 8192, 64, 65536, data_keys=true),
    65536,
    8192,
    64,
  )
  assert_true(
    @publication.parse_interactive_run_control_shape(
      "plan_view", view, 65536, 8192, 64,
    )
    is Ok(_),
  )
  let changed : NativeClientRunPlanOriginal = {
    plan: captured.original.plan,
    view,
  }
  assert_true(
    native_cold_plan_view(changed, (_, _, _) => Ok(())) is Err(ForeignRun),
  )
}
