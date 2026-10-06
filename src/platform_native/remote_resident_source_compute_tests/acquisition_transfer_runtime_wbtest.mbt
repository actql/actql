// Exact producer output → independent Direct Transfer holding → consumer borrow.
// Both executions use actual Native Runtime owners from the same original Run.
// Signed components are test fixtures; this is not public Cloud acceptance.

///|
fn acquisition_runtime_transfer_consumer(
  materials : @host.ClientRunMaterials,
  configuration : @resident.ResidentSourceComputeConfiguration,
  compilation : @host.ClientTaskCompilation,
  caller : @host.ClientRequestIdentity,
  selected : @host.ClientValuesSiteSelection,
  producer_runtime : @runtime.NativeRemoteRuntime,
  producer_dispatch : @remote.DispatchRequest,
  producer : @host.ClientRetainedInputProducer,
  material_id : String,
  site : @site.ExecutionSite,
  sqlite : @sqlite.Library,
  root_path : String,
  name : String,
  cancel_receiver? : Bool = false,
  deny_after_admission? : Bool = false,
) -> Unit raise {
  let reader = producer_runtime
    .open_output_manifest_reader(producer_dispatch, material_id, 128)
    .unwrap()
  let physical = reader.physical_manifest().unwrap()
  assert_eq(
    physical.codec_contract_cid,
    @execution.ordered_rows_canonical_contract_cid(),
  )
  assert_eq(physical.row_count, 3)
  let request = @transfer.prepare_request(
    retained_compute_cid("c"),
    "actual-runtime-transfer",
    @transfer.DirectStream,
    selected.site_key,
    selected.site_generation,
    selected.site_key,
    selected.site_generation,
    material_id,
    physical,
    physical.referenced_bytes,
    4102444800000L,
    selected.evidence_issuer_capability_cid,
    selected.grant_cid,
    retained_compute_cid("6"),
  ).unwrap()
  assert_true(reader.close().unwrap())
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
