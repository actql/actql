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
  through_consumer_holder? : Bool = false,
  consumer_task? : Int = 1,
  chain_context? : RetainedNativeChainContext? = None,
  cancel_consumer_before_start? : Bool = false,
  consumer_output_unavailable? : Bool = false,
  cancel_receiver? : Bool = false,
  deny_after_admission? : Bool = false,
  consumer_start_expiry? : Bool = false,
  producer_cleanup_at_handoff? : Bool = false,
  cleanup_after_preparation? : Bool = false,
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
  let handoff_wire = @remote.remote_poll_retained_input_transfer_json(
    restored_plan,
  ).unwrap()
  let operation = @remote.admit_remote_poll_operation_json(handoff_wire).unwrap()
  guard operation is @remote.RetainedTransfer(handoff) else {
    fail("expected retained transfer handoff")
  }
  let restored_plan = @remote.remote_poll_retained_transfer_plan(handoff)
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
  let cleanup_now = Ref(
    producer_cleanup_at_handoff && !cleanup_after_preparation,
  )
  let cleanup_confirmed = Ref(false)
  let common_current = @host.install_client_retained_input_current(
    () => site,
    () => retained_compute_cid("c"),
    () => 1791158400000L,
    (_, _) => {
      // Observe delegation first, then inject an actual concurrent producer
      // release before returning that earlier authorization observation.
      let delegated = @resident.resident_retained_producer_authorized(
        context,
        local_delegation,
        request,
        @site.site_generation(site),
        "2026-10-05T00:00:00.000Z",
      )
      if cleanup_now.val {
        cleanup_now.val = false
        cleanup_confirmed.val = producer_runtime
          .release(producer_dispatch)
          .unwrap()
      }
      authorized.val &&
      delegated &&
      (
        !deny_after_admission ||
        destination_journal.require(request)
        is Err(@journal.Physical(@sqlite.NotFound))
      )
    },
  )
  // A foreign checked consumer must be refused before receiver admission,
  // even when its physical Transfer bytes would otherwise match the producer.
  let before_preparation = @site.site_status(site)
  assert_true(
    @resident.prepare_resident_retained_plan_transfer(
      producer_runtime, producer, foreign, restored_plan, common_current, site, destination_journal,
      root, 128, 536870912L, 8L,
    )
    is Err(@resident.Input(@host.InvalidBinding)),
  )
  assert_eq(@site.site_status(site)[6], before_preparation[6])
  let prepared_transfer = @resident.prepare_resident_retained_plan_transfer(
    producer_runtime, producer, intent, restored_plan, common_current, site, destination_journal,
    root, 128, 536870912L, 8L,
  )
  if producer_cleanup_at_handoff {
    if cleanup_after_preparation {
      let transfer = prepared_transfer.unwrap()
      let current_query = @remote.admit_remote_poll_retained_input_current_json(
        @remote.remote_poll_retained_input_current_json(
          restored_plan, "live-receiver-query",
        ).unwrap(),
      ).unwrap()
      assert_true(
        transfer.current_reply(current_query) is Err(@resident.CleanupPending),
      )
      cleanup_now.val = true
      assert_true(
        transfer.advance() is Err(@resident.Input(@host.ProducerUnavailable)),
      )
      assert_true(transfer.reclaim().unwrap())
      assert_false(transfer.reclaim().unwrap())
    } else {
      assert_true(
        prepared_transfer is Err(@resident.Input(@host.ProducerUnavailable)),
      )
    }
    assert_true(cleanup_confirmed.val)
    assert_false(@host.client_retained_input_producer_available(producer))
    assert_eq(
      destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
      0L,
    )
    assert_true(
      destination_journal.require(request)
      is Err(@journal.Physical(@sqlite.NotFound)),
    )
    assert_false(producer_runtime.release(producer_dispatch).unwrap())
    assert_true(destination_journal.close())
    return
  }
  let transfer = prepared_transfer.unwrap()
  let current_query = @remote.admit_remote_poll_retained_input_current_json(
    @remote.remote_poll_retained_input_current_json(
      restored_plan, "live-receiver-query",
    ).unwrap(),
  ).unwrap()
  assert_true(
    transfer.current_reply(current_query) is Err(@resident.CleanupPending),
  )
  assert_true(transfer.result() is Err(@resident.CleanupPending))
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
  let report = transfer.result().unwrap()
  let report_wire = @remote.remote_retained_input_result_json(report)
  let report_cid = @remote.remote_retained_input_result_identity(report)
  let admitted_report = @remote.admit_remote_retained_input_result_json(
    report_wire, report_cid, restored_plan,
  ).unwrap()
  assert_eq(
    @transfer.record_request_identity(
      @remote.remote_retained_input_result_record(admitted_report),
    ),
    @transfer.request_cid(request),
  )
  assert_eq(
    @transfer.record_revision(
      @remote.remote_retained_input_result_record(admitted_report),
    ),
    revision,
  )
  // At the report boundary, a retry uses immutable receiver evidence, never
  // bytes or acquisition. This case does not perform an HTTP exchange.
  // Historical reporting is still possible after revocation.
  authorized.val = false
  assert_eq(
    @remote.remote_retained_input_result_json(transfer.result().unwrap()),
    report_wire,
  )
  assert_true(
    transfer.current_reply(current_query)
    is Err(@resident.Input(@host.AuthorizationUnavailable)),
  )
  authorized.val = true
  let before_query = @site.site_status(site)
  let current_reply = transfer.current_reply(current_query).unwrap()
  let current_reply = @remote.admit_remote_retained_input_current_reply_json(
    @remote.remote_retained_input_current_reply_json(current_reply),
    @remote.remote_retained_input_current_reply_identity(current_reply),
    current_query,
    8,
    4096,
    1024L,
  ).unwrap()
  assert_eq(
    @remote.remote_retained_input_current_reply_transfer_record_json(
      current_reply,
    ),
    @transfer.remote_transfer_record_durable_json(
      destination_journal.require(request).unwrap(),
    ).unwrap(),
  )
  assert_eq(
    @transfer.record_revision(destination_journal.require(request).unwrap()),
    revision,
  )
  assert_eq(@site.site_status(site), before_query)
  let foreign_query = @remote.admit_remote_poll_retained_input_current_json(
    @remote.remote_poll_retained_input_current_json(
      @remote.prepare_remote_retained_input_plan(
        foreign,
        @host.client_retained_input_producer_subject(producer),
        @host.client_retained_input_producer_evidence(producer),
        request,
      ).unwrap(),
      "foreign-live-query",
    ).unwrap(),
  ).unwrap()
  assert_true(
    transfer.current_reply(foreign_query) is Err(@resident.ForeignProducer),
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
    consumer_task,
    1,
    "actual-consumer",
    selected,
    common_input,
    common_current,
  ).unwrap()
  if through_consumer_holder {
    retained_consumer_holder_case(
      transfer,
      producer_journal,
      materials,
      admission,
      configuration,
      common_input,
      dispatch,
      @host.prepare_client_retained_task_dispatch(
        materials.prepared,
        compilation,
        materials.admission,
        materials.run_definition,
        caller,
        consumer_task,
        2,
        "foreign-holder-consumer",
        selected,
        common_input,
        common_current,
      ).unwrap(),
      site,
      sqlite,
      root_path,
      name + ".consumer-holder",
      destination_journal,
      bytes,
      current_query,
      cancel_before_start=cancel_consumer_before_start ||
        (
          chain_context is Some(context) &&
          context.cancel_tail &&
          consumer_task == 2
        ),
      chain_task=if chain_context is Some(_) {
        Some(consumer_task)
      } else {
        None
      },
      chain_context~,
      output_unavailable=consumer_output_unavailable,
    )
    assert_true(@host.client_retained_input_producer_available(producer))
    if chain_context is Some(_) ||
      (!cancel_consumer_before_start && !consumer_output_unavailable) {
      // Durable file handoff or confirmed pre-start cancellation already
      // reclaimed this receiver through its existing Owner.
      assert_false(transfer.reclaim().unwrap())
    } else {
      assert_true(transfer.reclaim().unwrap())
      assert_false(transfer.reclaim().unwrap())
    }
    assert_true(
      transfer.current_reply(current_query) is Err(@resident.CleanupPending),
    )
    assert_eq(
      destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
      0L,
    )
    assert_eq(@site.site_status(site)[6], before[6])
    assert_true(destination_journal.close())
    return
  }
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
      consumer_task,
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
          consumer_task,
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
    @remote.remote_retained_input_result_identity(transfer.result().unwrap()),
    report_cid,
  )
  assert_eq(
    @remote.remote_retained_input_result_json(transfer.result().unwrap()),
    report_wire,
  )
  assert_eq(
    destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
    0L,
  )
  assert_true(destination_journal.close())
}
