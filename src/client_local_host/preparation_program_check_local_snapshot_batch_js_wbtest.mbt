///|
// Original authored source/Member inputs on the existing Request fixture. The
// SHA ordering is a linkage fixture, not an independent identity-law oracle.
fn batch_snapshot_body(stage : String, name : String) -> String {
  "{\"output_carrier\":\"relation\",\"schema\":{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"},\"source_ref\":\"source:local/" +
  stage +
  "/" +
  name +
  "\",\"version\":\"actql-local-input-schema/0.1\"}"
}

///|
fn batch_snapshot_parent(
  count : Int,
  mixed? : Bool = false,
  bad_second? : Bool = false,
  current? : () -> Bool = () => true,
) -> (
  ClientRequestPreparation[Array[Int]],
  ClientProgramCheckPreparation[Array[Int], Unit],
  Array[Int],
) raise {
  let declarations : Array[String] = []
  let bodies : Array[String] = []
  for i in 0..<Int::max(count, 1) {
    declarations.push("\"b" + i.to_string() + "\":\"relation\"")
  }
  for i in 0..<count {
    bodies.push(
      batch_snapshot_body(
        if i % 2 == 0 {
          "s"
        } else {
          "t"
        },
        "b" + i.to_string(),
      ),
    )
  }
  if mixed {
    bodies.push(
      (
        #|{"carrier_schema_contract_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333","data_classification":"internal","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","source_data_policy_cid":"sha256:4444444444444444444444444444444444444444444444444444444444444444","source_ref":"connector://duckdb/local/orders#snapshot","source_view_contract_cid":"sha256:2222222222222222222222222222222222222222222222222222222222222222"}
      ),
    )
  }
  if bad_second {
    assert_eq(count, 1)
    let first = @sha.hex(@utf8.encode(bodies[0]))
    let mut found = false
    for i in 0..<100 {
      let invalid = batch_snapshot_body("missing" + i.to_string(), "b0")
      if @sha.hex(@utf8.encode(invalid)).compare(first) > 0 {
        bodies.push(invalid)
        found = true
        break
      }
    }
    assert_true(found)
  }
  bodies.sort_by((a, b) => {
    @sha.hex(@utf8.encode(a)).compare(@sha.hex(@utf8.encode(b)))
  })
  let stages : Array[String] = []
  for stage in ["s", "t"] {
    stages.push(
      "{\"id\":\"" +
      stage +
      "\",\"inputs\":{" +
      declarations.join(",") +
      "},\"steps\":[],\"results\":{\"out\":{}}}",
    )
  }
  let text = "{\"version\":\"actql/0.1\",\"id\":\"batch-body\",\"stages\":[" +
    stages.join(",") +
    "],\"results\":{\"out\":{\"from\":{\"stage\":\"t\",\"result\":\"out\"}}}}"
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[" +
    bodies.join(",") +
    "],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  let environment = @publication_host.admit_client_check_environment(
    prefix + "\"evidence_bundle_cid\":\"" + cid + "\"," + suffix,
    cid,
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let (parent, owner, source, input) = registration_parent_fixture(
    current~,
    text~,
    environment=Some(environment),
  )
  prepare_program_check_source_registration(owner, source).unwrap()
  inspect_program_check_source_collection(owner).unwrap()
  prepare_program_check_source_collection(owner).unwrap() |> ignore
  inspect_program_check_source_resolution(owner).unwrap()
  prepare_program_check_source_resolution(owner).unwrap() |> ignore
  prepare_program_check_source_pipeline(owner).unwrap() |> ignore
  prepare_program_check_source_local_entry(owner).unwrap() |> ignore
  inspect_program_check_source_local_index(owner).unwrap()
  prepare_program_check_source_local_index(owner).unwrap() |> ignore
  prepare_program_check_source_local_groups(owner).unwrap() |> ignore
  reconcile_program_check_source_local_groups(owner).unwrap()
  (parent, owner, input)
}

///|
test "same Request parent consumes zero one two many and mixed Snapshot bodies with one work phase" {
  for
    (count, mixed) in [
      (0, false),
      (1, false),
      (2, false),
      (12, false),
      (1, true),
    ] {
    let (parent, owner, input) = batch_snapshot_parent(count, mixed~)
    let read = @checked.parsed_source_registration_read(
      owner.source_registration.unwrap(),
    )
    assert_eq(
      prepare_program_check_source_local_snapshots(owner).unwrap(),
      RegistrationLocal,
    )
    assert_true(
      @context.source_registration_local_phase(read)
      is Some(LocalEnvironmentDeclaration),
    )
    assert_true(owner.work is None)
    if count == 0 {
      assert_true(owner.phase == SourceLocalSnapshotBatchComplete)
      assert_true(
        @context.source_registration_local_snapshot_emission(read) is None,
      )
    } else {
      assert_true(owner.phase == SourceLocalSnapshotBatchPrepared)
      assert_true(
        @context.source_registration_local_snapshot_emission(read) is Some(_),
      )
      assert_true(
        @resources.begin_preparation_phase_work64(
          parent.capacity,
          input,
          @resources.SourceLocalSnapshotBody,
          1L,
        )
        is Err(AlreadyClaimed),
      )
      reconcile_program_check_source_local_snapshots(owner).unwrap()
    }
    assert_true(
      prepare_program_check_source_local_snapshots(owner) is Err(WrongPhase),
    )
    clear_program_check_preparation(owner).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(
      @resources.ledger_usage(parent.ledger).reserved_retention_bytes,
      0L,
    )
  }
}

///|
test "same Request batch retains the original quantity across a one-short body grow without repeating inspection" {
  for retention in [true, false] {
    let (parent, owner, input) = batch_snapshot_parent(2)
    let read = @checked.parsed_source_registration_read(
      owner.source_registration.unwrap(),
    )
    // Run the SAME production metadata helper under its original latch, then
    // create this separate byte reservation outside the current callback.
    inspect_program_check_snapshot_batch_metadata(owner).unwrap() |> ignore
    quote_program_check_snapshot_batch_body(owner, read).unwrap()
    let (peak, _) = owner.source_body_quote.unwrap()
    let usage = @resources.ledger_usage(parent.ledger)
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes -
        usage.held_bytes -
        usage.reserved_retention_bytes -
        peak +
        1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - usage.reserved_execution_bytes - peak + 1L
      },
    ).unwrap()
    let result = prepare_program_check_source_local_snapshots(owner)
    match result {
      Err(Capacity(Resource(issue))) =>
        assert_eq(
          issue,
          if retention {
            @resources.RetentionLimit
          } else {
            @resources.ExecutionLimit
          },
        )
      Ok(_) =>
        fail("body unexpectedly succeeded instead of the one-short refusal")
      Err(_) => fail("unexpected non-resource refusal in the one-short fixture")
    }
    assert_true(owner.phase == SourceLocalSnapshotBatchRetained)
    assert_true(owner.work is None)
    assert_true(
      @context.source_registration_local_snapshot_emission(read) is None,
    )
    let original = @context.observe_source_registration_local_snapshot_batch_construction(
      read,
    )
    assert_true(original is Some(_))
    assert_true(
      physical_equal(
        original,
        @context.observe_source_registration_local_snapshot_batch_construction(
          read,
        ),
      ),
    )
    assert_true(
      @resources.begin_preparation_phase_work64(
        parent.capacity,
        input,
        @resources.SourceLocalSnapshotBodyInspection,
        1L,
      )
      is Err(AlreadyClaimed),
    )
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    assert_eq(
      prepare_program_check_source_local_snapshots(owner).unwrap(),
      RegistrationLocal,
    )
    clear_program_check_preparation(owner).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
  }
}

///|
test "same Request batch preserves second member typed failure completed first body and spent work" {
  let (parent, owner, input) = batch_snapshot_parent(1, bad_second=true)
  let read = @checked.parsed_source_registration_read(
    owner.source_registration.unwrap(),
  )
  assert_eq(
    prepare_program_check_source_local_snapshots(owner).unwrap(),
    RegistrationFailed,
  )
  assert_true(owner.phase == SourceLocalSnapshotBatchFailed)
  assert_true(
    @context.source_registration_local_failure_phase(read)
    is Some(LocalEnvironmentSnapshot),
  )
  assert_true(
    @context.source_registration_local_snapshot_emission(read)
    is Some((1, Some(_))),
  )
  assert_true(
    @context.source_registration_local_snapshot_work(read) is Some(spent) &&
    spent > 0,
  )
  assert_true(
    @context.take_source_registration_result(read)
    is Some(Err(LocalInputs(UnknownStage(1, _)))),
  )
  assert_true(@context.take_source_registration_result(read) is None)
  assert_true(
    @resources.begin_preparation_phase_work64(
      parent.capacity,
      input,
      @resources.SourceLocalSnapshotBody,
      1L,
    )
    is Err(AlreadyClaimed),
  )
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "batch body current boundary blocks reentry and stop before metadata or a Snapshot is constructed" {
  let action : Ref[(() -> Unit)?] = Ref(None)
  let stop = Ref(false)
  let calls = Ref(0)
  let (parent, owner, _) = batch_snapshot_parent(2, current=() => {
    calls.val += 1
    if action.val is Some(run) {
      run()
    }
    !stop.val
  })
  let read = @checked.parsed_source_registration_read(
    owner.source_registration.unwrap(),
  )
  let reentry = Ref(0)
  action.val = Some(() => {
    if clear_program_check_preparation(owner) is Err(WrongPhase) {
      reentry.val += 1
    }
    if prepare_program_check_source_local_snapshots(owner) is Err(WrongPhase) {
      reentry.val += 2
    }
    if take_program_check_source_registration(owner) is Err(WrongPhase) {
      reentry.val += 4
    }
  })
  stop.val = true
  let before = calls.val
  assert_true(
    prepare_program_check_source_local_snapshots(owner)
    is Err(Capacity(Resource(ClosedReservation))),
  )
  action.val = None
  assert_eq(calls.val - before, 1)
  assert_eq(reentry.val, 7)
  assert_true(
    @context.source_registration_local_snapshot_emission(read) is None,
  )
  assert_true(owner.work is None)
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}
