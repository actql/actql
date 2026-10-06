// Exact producer output → independent Direct Transfer holding → consumer borrow.
// Both executions use actual Native Runtime owners from the same original Run.
// Signed components are test fixtures; this is not public Cloud acceptance.

///|
fn acquisition_runtime_transfer_consumer(
  materials : @host.ClientRunMaterials,
  admission : @resident.ResidentRunAdmission,
  configuration : @resident.ResidentSourceComputeConfiguration,
  compilation : @host.ClientTaskCompilation,
  caller : @host.ClientRequestIdentity,
  selected : @host.ClientValuesSiteSelection,
  producer_runtime : @runtime.NativeRemoteRuntime,
  producer_journal : @dispatch_journal.Journal,
  producer_dispatch : @remote.DispatchRequest,
  producer : @host.ClientRetainedInputProducer,
  material_id : String,
  site : @site.ExecutionSite,
  sqlite : @sqlite.Library,
  root_path : String,
  name : String,
  cancel_receiver? : Bool = false,
  deny_after_admission? : Bool = false,
  consumer_start_expiry? : Bool = false,
  cancel_producer_before_handoff? : Bool = false,
) -> Unit raise {
  let facts = producer_runtime
    .inspect_output_facts(producer_dispatch, material_id)
    .unwrap()
  let physical = facts.physical_manifest
  assert_eq(
    physical.codec_contract_cid,
    @execution.ordered_rows_canonical_contract_cid(),
  )
  assert_eq(physical.row_count, 3)
  let intent = @host.prepare_client_retained_input_intent(producer, {
    transfer_attempt: "actual-runtime-transfer",
    transfer_max_bytes: physical.referenced_bytes,
    transfer_expires_unix_ms: 4102444800000L,
    source_grant_cid: retained_compute_cid("7"),
    destination_grant_cid: retained_compute_cid("8"),
    route_capability_cid: retained_compute_cid("6"),
  }).unwrap()
  let envelope = @remote.remote_poll_retained_input_plan_json(intent).unwrap()
  let operation = @remote.admit_remote_poll_operation_json(envelope).unwrap()
  guard operation is @remote.RetainedPlan(poll) else {
    fail("expected internal plan")
  }
  assert_false(@remote.remote_poll_operation_is_output_plan(operation))
  assert_false(@remote.remote_poll_operation_is_output(operation))
  let intent = @remote.remote_poll_retained_input_intent(poll)
  let context = @resident.prepare_resident_retained_producer_context(
    producer_journal, admission, intent, "2026-10-05T00:00:00.000Z",
  ).unwrap()
  let local_delegation : @resident_protocol.ResidentRetainedInputDelegation = {
    dispatch: {
      coordinator_authority: retained_compute_cid("c"),
      site_key: selected.site_key,
      runtime_bundle_cid: selected.runtime_bundle_cid,
      connector_registration: selected.connector_registration,
      connector_revision: selected.connector_revision,
      strategy_revision: selected.strategy_revision,
      grant_cid: selected.grant_cid,
      evidence_issuer_capability_cid: selected.evidence_issuer_capability_cid,
      budget_cids: [selected.budget_cid],
    },
    source_grant_cid: retained_compute_cid("7"),
    destination_grant_cid: retained_compute_cid("8"),
    route_capability_cid: retained_compute_cid("6"),
  }
  let planner_current = @host.install_client_retained_input_current(
    () => site,
    () => retained_compute_cid("c"),
    () => 1791158400000L,
    (_, request) => {
      @resident.resident_retained_producer_authorized(
        context,
        local_delegation,
        request,
        @site.site_generation(site),
        "2026-10-05T00:00:00.000Z",
      )
    },
  )
  let before_plan = @site.site_status(site)
  let projection = @remote.remote_retained_input_intent_projection(intent)
  let foreign = @remote.prepare_remote_retained_input_intent(
    producer_dispatch,
    {
      ..projection,
      consumer_task_key: projection.consumer_task_key + "-foreign",
    },
  ).unwrap()
  assert_true(
    @resident.plan_resident_retained_input_transfer(
      producer_runtime, producer, foreign, planner_current, site,
    )
    is Err(@resident.Input(@host.InvalidBinding)),
  )
  let denied = @host.install_client_retained_input_current(
    () => site,
    () => retained_compute_cid("c"),
    () => 1791158400000L,
    (_, _) => false,
  )
  assert_true(
    @resident.plan_resident_retained_input_transfer(
      producer_runtime, producer, intent, denied, site,
    )
    is Err(@resident.Input(@host.AuthorizationUnavailable)),
  )
  let stale = @host.install_client_retained_input_owner_current(
    (_, _, _) => false,
    () => retained_compute_cid("c"),
    () => 1791158400000L,
    (_, _) => true,
  )
  assert_true(
    @resident.plan_resident_retained_input_transfer(
      producer_runtime, producer, intent, stale, site,
    )
    is Err(@resident.Input(@host.StaleSiteGeneration)),
  )
  let expired = @host.install_client_retained_input_current(
    () => site,
    () => retained_compute_cid("c"),
    () => 4102444800000L,
    (_, _) => true,
  )
  assert_true(
    @resident.plan_resident_retained_input_transfer(
      producer_runtime, producer, intent, expired, site,
    )
    is Err(@resident.Input(@host.TransferExpired)),
  )
  let plan = @resident.plan_resident_retained_input_transfer(
    producer_runtime,
    @resident.resident_retained_producer(context),
    intent,
    planner_current,
    site,
  ).unwrap()
  let restored_plan = @remote.admit_remote_retained_input_plan_json(
    @remote.remote_retained_input_plan_json(plan),
    @remote.remote_retained_input_plan_identity(plan),
    intent,
    8,
    4096,
    536870912L,
  ).unwrap()
  let request = @remote.remote_retained_input_plan_transfer(restored_plan)
  assert_true(
    @remote.admit_remote_retained_input_plan_json(
      @remote.remote_retained_input_plan_json(plan).replace(
        old="actual-runtime-transfer",
        new="different-transfer",
      ),
      @remote.remote_retained_input_plan_identity(plan),
      intent,
      8,
      4096,
      536870912L,
    )
    is Err(@remote.InvalidDispatch),
  )
  assert_true(
    @remote.admit_remote_retained_input_plan_json(
      @remote.remote_retained_input_plan_json(plan),
      @remote.remote_retained_input_plan_identity(plan),
      foreign,
      8,
      4096,
      536870912L,
    )
    is Err(@remote.InvalidDispatch),
  )
  assert_true(
    @remote.admit_remote_retained_input_plan_json(
      @remote.remote_retained_input_plan_json(plan),
      @remote.remote_retained_input_plan_identity(plan),
      intent,
      8,
      4096,
      0L,
    )
    is Err(@remote.InvalidDispatch),
  )
  assert_eq(@site.site_status(site)[6], before_plan[6])
  assert_false(
    @resident.resident_retained_producer_authorized(
      context,
      { ..local_delegation, source_grant_cid: retained_compute_cid("0"), },
      request,
      @site.site_generation(site),
      "2026-10-05T00:00:00.000Z",
    ),
  )
  assert_false(
    @resident.resident_retained_producer_authorized(
      context,
      local_delegation,
      request,
      @site.site_generation(site),
      "2100-01-01T00:00:00.000Z",
    ),
  )
  let root = @filesystem.open_root(root_path).unwrap()
  let path = root_path + "/" + name + ".actual-transfer.sqlite"
  let destination_journal = @journal.open_journal(
    sqlite, path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  let authorized = Ref(true)
  let common_current = @host.install_client_retained_input_current(
    () => site,
    () => retained_compute_cid("c"),
    () => 1791158400000L,
    (_, _) => {
      authorized.val &&
      @resident.resident_retained_producer_authorized(
        context,
        local_delegation,
        request,
        @site.site_generation(site),
        "2026-10-05T00:00:00.000Z",
      ) &&
      (
        !deny_after_admission ||
        destination_journal.require(request)
        is Err(@journal.Physical(@sqlite.NotFound))
      )
    },
  )
  let transfer = @resident.prepare_resident_retained_transfer(
    producer_runtime, producer_dispatch, producer, request, common_current, site,
    destination_journal, root, 128, 536870912L, 8L,
  ).unwrap()
  let before = @site.site_status(site)
  if cancel_producer_before_handoff {
    producer_journal.request_cancellation(producer_dispatch).unwrap() |> ignore
    assert_true(
      producer_journal.cancellation_requested(producer_dispatch).unwrap(),
    )
    assert_true(
      transfer.advance() is Err(@resident.Input(@host.AuthorizationUnavailable)),
    )
    assert_eq(@site.site_status(site)[6], before[6])
    assert_eq(
      destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
      0L,
    )
    // The cancellation request withholds movement. It does not rewrite the
    // completed producer as unexecuted or release its original holding.
    assert_true(@host.client_retained_input_producer_available(producer))
    assert_true(transfer.reclaim().unwrap())
    assert_false(transfer.reclaim().unwrap())
    assert_true(destination_journal.close())
    return
  }
  authorized.val = false
  assert_true(
    transfer.advance() is Err(@resident.Input(@host.AuthorizationUnavailable)),
  )
  assert_eq(@site.site_status(site)[6], before[6])
  assert_eq(
    destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
    0L,
  )
  authorized.val = true
  if deny_after_admission {
    assert_true(
      transfer.advance() is Err(@resident.Input(@host.AuthorizationUnavailable)),
    )
    assert_eq(@site.site_status(site)[6], before[6] + physical.referenced_bytes)
    assert_eq(
      destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
      physical.referenced_bytes,
    )
    assert_true(
      destination_journal
      .inspect_destination_allocation_if_present(
        request, "direct-destination", 0,
      )
      .unwrap()
      is None,
    )
    assert_true(transfer.reclaim().unwrap())
    assert_false(transfer.reclaim().unwrap())
    assert_true(
      @transfer.direct_transfer_cleanup_confirmed(
        destination_journal.require(request).unwrap(),
      ),
    )
    assert_eq(@site.site_status(site)[6], before[6])
    assert_eq(
      destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
      0L,
    )
    assert_true(@host.client_retained_input_producer_available(producer))
    assert_true(destination_journal.close())
    return
  }
  assert_false(transfer.advance().unwrap())
  assert_eq(@site.site_status(site)[6], before[6] + physical.referenced_bytes)
  authorized.val = false
  if cancel_receiver {
    assert_true(transfer.reclaim().unwrap())
    assert_false(transfer.reclaim().unwrap())
    assert_true(
      @transfer.direct_transfer_cleanup_confirmed(
        destination_journal.require(request).unwrap(),
      ),
    )
    assert_eq(
      destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
      0L,
    )
    assert_eq(@site.site_status(site)[6], before[6])
    assert_true(@host.client_retained_input_producer_available(producer))
    assert_true(destination_journal.close())
    return
  }
  assert_true(
    transfer.advance() is Err(@resident.Input(@host.AuthorizationUnavailable)),
  )
  assert_eq(@site.site_status(site)[6], before[6] + physical.referenced_bytes)
  assert_eq(
    destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
    physical.referenced_bytes,
  )
  assert_true(
    destination_journal
    .inspect_destination_allocation_if_present(request, "direct-destination", 1)
    .unwrap()
    is None,
  )
  authorized.val = true
  let mut rounds = 1
  while !transfer.advance().unwrap() {
    rounds += 1
    assert_true(rounds <= 4)
  }
  assert_eq(rounds, 3)
  assert_eq(@site.site_status(site)[6], before[6] + physical.referenced_bytes)
  let revision = @transfer.record_revision(
    destination_journal.require(request).unwrap(),
  )
  assert_true(transfer.advance().unwrap())
  assert_eq(
    @transfer.record_revision(destination_journal.require(request).unwrap()),
    revision,
  )
  let bytes = physical.referenced_bytes
  assert_eq(
    destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
    bytes,
  )
  assert_true(@host.client_retained_input_producer_available(producer))
  assert_true(destination_journal.close())
  // Receiver reconstruction after commit preserves the original sender. It
  // neither recompiles the Program nor fetches Source input again.
  let destination_journal = @journal.open_journal(
    sqlite, path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  transfer.reopen_completed_destination(destination_journal).unwrap()
  let committed = @transfer_client.commit_durable_direct_destination(
    destination_journal, root, request,
  ).unwrap()
  let receipt = destination_journal
    .inspect_destination_receipt(request)
    .unwrap()
    .unwrap()
  let current = @output.install_native_remote_retained_input_current(
    () => site,
    () => retained_compute_cid("c"),
    () => 1791158400000L,
    (_, _) => true,
  )
  let input = @output.prepare_native_remote_retained_task_input(
    producer, committed, receipt, "direct-destination", current, 262144,
  ).unwrap()
  let common_input = @host.prepare_client_retained_task_input(
    producer, committed, receipt, "direct-destination", common_current, 262144,
  ).unwrap()
  let dispatch = @host.prepare_client_retained_task_dispatch(
    materials.prepared,
    compilation,
    materials.admission,
    materials.run_definition,
    caller,
    1,
    1,
    "actual-consumer",
    selected,
    common_input,
    common_current,
  ).unwrap()
  let material = @transfer_client.pin_durable_direct_destination_material(
    destination_journal,
    root,
    request,
    @remote.dispatch_request_identity(dispatch),
    @transfer.destination_receipt_cid(receipt),
  ).unwrap()
  @transfer_client.validate_destination_material_use(material).unwrap()
  assert_true(destination_journal.close())
  let destination_journal = @journal.open_journal(
    sqlite, path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  transfer.reopen_completed_destination(destination_journal).unwrap()
  let material = @transfer_client.pin_durable_direct_destination_material(
    destination_journal,
    root,
    request,
    @remote.dispatch_request_identity(dispatch),
    @transfer.destination_receipt_cid(receipt),
  ).unwrap()
  @transfer_client.validate_destination_material_use(material).unwrap()
  assert_eq(
    destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
    bytes,
  )
  let saved = @output.native_remote_retained_task_input_binding(input)
  let restored = @remote.prepare_remote_input_binding(
    @remote.remote_input_binding_body(saved),
    262144,
  ).unwrap()
  let input = @output.admit_native_remote_retained_task_input(
    restored, producer, committed, receipt, "direct-destination", current, 262144,
  ).unwrap()
  @output.validate_native_remote_retained_task_input_borrow(
    input, material, current,
  ).unwrap()
  let cleanup = @transfer_client.pin_durable_direct_destination_material(
    destination_journal,
    root,
    request,
    "actual-runtime-receiver-cleanup",
    @transfer.destination_receipt_cid(receipt),
  ).unwrap()
  let codec = @output.register_native_remote_standard_row_codec(
    physical.schema_contract_cid,
    physical.view_contract_cid,
    physical.codec_contract_cid,
  ).unwrap()
  // The producer's live Source owner remains responsible, but a new acquisition
  // cannot open this pathname. Compute must use the independent receiver.
  resident_compute_reclaim(root, name)
  let producer_usage = @site.site_status(site)
  retained_compute_through_runtime(
    materials,
    configuration,
    input,
    material,
    dispatch,
    @host.prepare_client_retained_task_dispatch(
      materials.prepared,
      compilation,
      materials.admission,
      materials.run_definition,
      caller,
      1,
      2,
      "foreign-actual-consumer",
      selected,
      common_input,
      common_current,
    ).unwrap(),
    codec,
    current,
    site,
    root_path,
    name + ".consumer",
    sqlite,
    destination_journal,
    cleanup,
    bytes,
    retained_site_usage=producer_usage,
    through_resident=true,
    expire_at_start=consumer_start_expiry,
    restore_input=(rebuilt, saved) => {
      guard rebuilt.compilation is @host.Tasks(compilation) else {
        return Err(@output.InvalidBinding)
      }
      let edge = match
        @host.prepare_client_retained_input_edge(
          rebuilt.prepared,
          compilation,
          rebuilt.admission,
          rebuilt.run_definition,
          1,
          0,
        ) {
        Ok(value) => value
        Err(_) => return Err(@output.InvalidBinding)
      }
      let observation = match producer_journal.observation(producer_dispatch) {
        Ok(value) => value
        Err(_) => return Err(@output.ProducerUnavailable)
      }
      guard @dispatch_journal.recovered_site_dispatch_evidence(observation)
        is Some(evidence) &&
        @dispatch_journal.recovered_site_dispatch_subject(observation)
        is Some(subject) else {
        return Err(@output.ProducerUnavailable)
      }
      let record = match producer_journal.require(producer_dispatch) {
        Ok(value) => value
        Err(_) => return Err(@output.ProducerUnavailable)
      }
      let producer = match
        @host.prepare_client_retained_input_producer(
          edge, record, evidence, subject,
        ) {
        Ok(value) => value
        Err(_) => return Err(@output.ProducerUnavailable)
      }
      let committed = match destination_journal.require(request) {
        Ok(value) => value
        Err(_) => return Err(@output.ForeignTransfer)
      }
      let receipt = match
        destination_journal.inspect_destination_receipt(request) {
        Ok(Some(value)) => value
        _ => return Err(@output.ForeignTransfer)
      }
      @output.admit_native_remote_retained_task_input(
        saved, producer, committed, receipt, "direct-destination", current, 262144,
      )
    },
  )
  assert_true(@host.client_retained_input_producer_available(producer))
  authorized.val = false
  assert_true(transfer.reclaim().unwrap())
  assert_false(transfer.reclaim().unwrap())
  assert_eq(@site.site_status(site)[6], before[6])
  assert_eq(
    destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
    0L,
  )
  assert_true(destination_journal.close())
}
