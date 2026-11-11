///|
// Authored local input and member, admitted by the existing environment reader.
// No Host/provider/state or completed semantic-check acceptance is asserted.
fn registration_snapshot_environment() -> @checked.CheckEnvironment {
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix =
    #|"host_policy_profile":{},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[{"output_carrier":"relation","schema":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"source_ref":"source:local/a/rows","version":"actql-local-input-schema/0.1"}],"source_views":[],"version":"actql-check-environment/0.1"}
  let cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  @publication_host.admit_client_check_environment(
    prefix + "\"evidence_bundle_cid\":\"" + cid + "\"," + suffix,
    cid,
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
fn registration_local_snapshot_fixture(
  current? : () -> Bool = () => true,
) -> (
  ClientRequestPreparation[Array[Int]],
  ClientProgramCheckPreparation[Array[Int], Unit],
  Array[Int],
) raise {
  let text =
    #|{"version":"actql/0.1","id":"member-entry","stages":[{"id":"a","inputs":{"rows":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false}}}},"from":"rows","steps":[],"results":{"out":{"from":"rows","fields":["id"]}}}],"results":{"out":{"from":{"stage":"a","result":"out"}}}}
  let (parent, owner, source, input) = registration_parent_fixture(
    current~,
    text~,
    environment=Some(registration_snapshot_environment()),
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
test "same parent backs original Local member capture before either one-short metadata limit" {
  assert_eq(program_source_local_snapshot_metadata_peak_bytes, 416L)
  assert_eq(program_source_local_snapshot_metadata_retained_bytes, 248L)
  for retention in [true, false] {
    let (parent, owner, input) = registration_local_snapshot_fixture()
    let original = owner.source_registration.unwrap()
    let read = @checked.parsed_source_registration_read(original)
    assert_true(
      @context.source_registration_local_phase(read)
      is Some(LocalEnvironmentSnapshot),
    )
    assert_true(
      @context.source_registration_local_snapshot_limits(read) is None,
    )
    let before = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    let cap = @resources.ledger_limits(parent.ledger)
    let short = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        cap.retained_bytes - before.0 - 416L + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        cap.execution_bytes - before.1 - 416L + 1L
      },
    ).unwrap()
    let refused = inspect_program_check_source_local_snapshot(owner)
    assert_true(
      if retention {
        refused is Err(Capacity(Resource(RetentionLimit)))
      } else {
        refused is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_true(
      @context.source_registration_local_snapshot_construction_geometry(read)
      is None,
    )
    assert_true(
      @context.source_registration_local_snapshot_limits(read) is None,
    )
    @resources.settle_capacity(parent.ledger, short).unwrap()
    inspect_program_check_source_local_snapshot(owner).unwrap()
    let geometry = @context.source_registration_local_snapshot_construction_geometry(
      read,
    ).unwrap()
    let limits = @context.source_registration_local_snapshot_limits(read).unwrap()
    assert_true(geometry.0 > 0 && geometry.1 > 0)
    assert_true(limits.max_bytes > 0 && limits.max_nodes > 0)
    assert_true(
      @context.source_registration_local_snapshot_emission(read) is None,
    )
    assert_true(
      inspect_program_check_source_local_snapshot(owner) is Err(WrongPhase),
    )
    reconcile_program_check_source_local_snapshot_inspection(owner).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input),
      Ok((before.0 + 248L, before.1 + 248L)),
    )
    assert_true(
      physical_equal(
        limits,
        @context.source_registration_local_snapshot_limits(read).unwrap(),
      ),
    )
    assert_true(
      physical_equal(
        take_program_check_source_registration(owner).unwrap(),
        original,
      ),
    )
    clear_program_check_preparation(owner).unwrap()
    assert_true(
      abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
    )
    @context.clear_source_registration(read)
    @resources.abort_preparation_capacity_after_cleanup(parent.capacity, input).unwrap()
    |> ignore
    preparation_initial_cleanup(parent.initial).unwrap()
  }
}

///|
test "Local member capture checks current once and refuses reentry before allocating selected metadata" {
  let stop = Ref(false)
  let calls = Ref(0)
  let reentry = Ref(0)
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (parent, owner, _) = registration_local_snapshot_fixture(current=() => {
    calls.val += 1
    if action.val is Some(run) {
      run()
    }
    !stop.val
  })
  let read = @checked.parsed_source_registration_read(
    owner.source_registration.unwrap(),
  )
  action.val = Some(() => {
    if clear_program_check_preparation(owner) is Err(WrongPhase) {
      reentry.val += 1
    }
    if inspect_program_check_source_local_snapshot(owner) is Err(WrongPhase) {
      reentry.val += 2
    }
    if take_program_check_source_registration(owner) is Err(WrongPhase) {
      reentry.val += 4
    }
  })
  stop.val = true
  let before = calls.val
  assert_true(
    inspect_program_check_source_local_snapshot(owner)
    is Err(Capacity(Resource(ClosedReservation))),
  )
  action.val = None
  assert_eq(calls.val - before, 1)
  assert_eq(reentry.val, 7)
  assert_true(@context.source_registration_local_snapshot_limits(read) is None)
  assert_true(
    @context.source_registration_local_snapshot_construction_geometry(read)
    is None,
  )
  assert_true(
    @context.source_registration_local_snapshot_emission(read) is None,
  )
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}
