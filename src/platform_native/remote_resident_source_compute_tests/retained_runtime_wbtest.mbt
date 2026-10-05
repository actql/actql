///|
fn retained_runtime_required_env(name : String) -> String {
  match @env.get_env_var(name) {
    Some(value) if value != "" => value
    _ => abort("retained Runtime diagnostic requires " + name)
  }
}

///|
/// This signed component is the existing Native test fixture. It establishes
/// real bundle/journal/Runtime admission, not a distributed resident binary or
/// public Cloud acceptance. The producer completion remains the explicit
/// protocol fixture in retained_compute_wbtest.mbt.
fn retained_compute_through_runtime(
  materials : @host.ClientRunMaterials,
  configuration : @resident.ResidentSourceComputeConfiguration,
  input : @output.NativeRemoteRetainedTaskInput,
  material : @transfer_client.NativeRemoteDestinationMaterialUse,
  dispatch : @remote.DispatchRequest,
  another_attempt : @remote.DispatchRequest,
  codec : @output.NativeRemoteStandardRowCodec,
  current : @output.NativeRemoteRetainedInputCurrent,
  site : @site.ExecutionSite,
  root_path : String,
  name : String,
  sqlite : @sqlite.Library,
  destination_journal : @journal.Journal,
  cleanup_owner : @transfer_client.NativeRemoteDestinationMaterialUse,
  destination_bytes : Int64,
  retained_site_usage? : Array[Int64] = Array::make(9, 0L),
) -> Unit raise {
  let (bundles, active, journal) = retained_runtime_owners(
    sqlite, site, root_path, name,
  )
  let limits : @output.NativeRemoteStandardTaskLimits = {
    output_export: resident_compute_limits(),
    max_manifest_bytes: 4096,
    max_retained_bytes: 1048576L,
  }
  let executor = @resident.install_resident_retained_compute_executor(
    materials,
    configuration,
    input,
    material,
    dispatch,
    codec,
    retained_compute_input_limits(),
    current,
    limits,
  ).unwrap()
  assert_true(@transfer_client.destination_material_use_available(material))
  assert_eq(
    destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
    destination_bytes,
  )
  let scope = @remote.dispatch_request_execution_scope(dispatch)
  let runtime = @output.open_native_remote_standard_site_runtime(
    site,
    active,
    scope[6],
    scope[7],
    [executor],
    journal,
    bundles,
    [@remote.prepare_remote_dispatch_budget(1048576L, 1048576L).unwrap()],
  ).unwrap()
  runtime.guard_executor_start(() => true).unwrap()
  runtime.claim_starts_as("retained-consumer-holder").unwrap()
  let entries = Ref(0)
  runtime
  .observe_executor_entry(identity => {
    if identity != @remote.remote_dispatch_attempt_key(dispatch) {
      return true
    }
    entries.val += 1
    true
  })
  .unwrap()
  let binding = @output.native_remote_retained_task_input_binding(input)
  assert_true(
    runtime.start(another_attempt, binding)
    is Err(@runtime.Physical("foreign-input-binding")),
  )
  assert_eq(entries.val, 0)
  // Runtime owns the rejected occurrence's stop/cleanup acknowledgement too.
  // Its cleanup must not return the original consumer's independently pinned
  // input borrow or hide that borrow behind an empty resource count.
  assert_true(runtime.cleanup_pending())
  assert_true(runtime.cleanup(another_attempt).unwrap())
  assert_false(runtime.cleanup(another_attempt).unwrap())
  assert_false(runtime.cleanup_pending())
  assert_true(@transfer_client.destination_material_use_available(material))
  assert_eq(
    destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
    destination_bytes,
  )
  let completion = match runtime.start(dispatch, binding) {
    Ok(value) => value
    Err(@runtime.Physical(code)) => abort("Consumer Runtime refused: " + code)
    Err(_) => abort("Consumer Runtime refused outside physical Owner")
  }
  assert_eq(entries.val, 1)
  assert_true(runtime.retains_dispatch_resources())
  assert_eq(
    runtime.start(dispatch, binding).unwrap().evidence_cid,
    completion.evidence_cid,
  )
  assert_eq(entries.val, 1)
  let observed = journal.observation(dispatch).unwrap()
  let evidence = @dispatch_journal.recovered_site_dispatch_evidence(observed).unwrap()
  let subject = @dispatch_journal.recovered_site_dispatch_subject(observed).unwrap()
  assert_eq(
    @remote.remote_execution_evidence_cid(evidence),
    completion.evidence_cid,
  )
  assert_eq(
    @remote.remote_managed_output_subject_cid(subject),
    completion.subject_cid,
  )
  let fields = @remote.remote_managed_output_subject_projection(subject)
  let facts = runtime.inspect_output_facts(dispatch, fields[1]).unwrap()
  assert_eq(facts.row_count, 1)
  // Independently pinned complete field-map schema, not the row-object port
  // contract and not a CID copied from the emitted Native output.
  assert_eq(
    facts.result_schema_cid,
    "sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513",
  )
  // A successful Compute and an idempotent start do not return its input.
  assert_true(@transfer_client.destination_material_use_available(material))
  assert_true(
    @transfer_client.reclaim_durable_destination_material(cleanup_owner)
    is Err(Durable(@journal.MaterialInUse)),
  )
  let reader = runtime.open_output_reader(dispatch, fields[1], 128).unwrap()
  assert_false(runtime.release(dispatch).unwrap())
  let bytes : Array[Byte] = []
  while true {
    let chunk = reader.next().unwrap()
    for byte in chunk.bytes {
      bytes.push(byte)
    }
    if chunk.eof {
      break
    }
  }
  assert_eq(@utf8.decode(Bytes::from_array(bytes)), "[{\"id\":3}]")
  assert_true(reader.finish().unwrap())
  assert_false(reader.finish().unwrap())
  assert_true(@transfer_client.destination_material_use_available(material))
  assert_eq(
    destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
    destination_bytes,
  )
  assert_true(runtime.release(dispatch).unwrap())
  assert_false(runtime.release(dispatch).unwrap())
  assert_eq(entries.val, 1)
  assert_false(runtime.retains_dispatch_resources())
  assert_false(runtime.cleanup_pending())
  let record = journal.require(dispatch).unwrap()
  let (state, _, cleanup, _, _) = @remote.dispatch_record_state(record)
  assert_true(state is @remote.NativeSettled)
  assert_true(cleanup is @remote.CleanupReleased)
  let revision = @remote.dispatch_record_revision(record)
  assert_true(
    runtime.start(dispatch, binding) is Err(@runtime.DispatchAlreadyStarted),
  )
  assert_eq(entries.val, 1)
  assert_eq(
    @remote.dispatch_record_revision(journal.require(dispatch).unwrap()),
    revision,
  )
  assert_false(@transfer_client.destination_material_use_available(material))
  // Formal task cleanup returned the borrow, not the independent receiver.
  assert_eq(
    destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
    destination_bytes,
  )
  assert_true(
    @transfer_client.reclaim_durable_destination_material(cleanup_owner).unwrap(),
  )
  assert_false(
    @transfer_client.reclaim_durable_destination_material(cleanup_owner).unwrap(),
  )
  assert_eq(
    destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
    0L,
  )
  let usage = @site.site_status(site)
  for index in [2, 4, 6, 7, 8] {
    assert_eq(usage[index], retained_site_usage[index])
  }
  assert_true(runtime.close().unwrap())
  assert_true(journal.close())
  assert_true(bundles.close().unwrap())
}

///|
fn retained_runtime_owners(
  sqlite : @sqlite.Library,
  site : @site.ExecutionSite,
  root_path : String,
  name : String,
) -> (
  @bundle.NativeRuntimeBundleStore,
  @bundle.NativeActiveRuntimeBinding,
  @dispatch_journal.Journal,
) {
  let crypto = @signature.load_library(
    retained_runtime_required_env("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY"),
  ).unwrap()
  let target = retained_runtime_required_env(
    "ACTQL_TEST_NATIVE_REMOTE_RUNTIME_TARGET",
  )
  let bundle_cid = retained_runtime_required_env(
    "ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID",
  )
  let root = @filesystem.open_root(root_path).unwrap()
  let directory = name + ".runtime"
  root.create_directory(directory).unwrap() |> ignore
  let root = root.open_child(directory).unwrap()
  let component = b"native-runtime"
  let writer = root
    .create_writer("stage", component.length().to_int64())
    .unwrap()
  writer.append(component).unwrap()
  let generation = writer.seal("component").unwrap()
  let path = root_path + "/" + directory
  let bundles = @bundle.open_runtime_bundle_store(
    sqlite,
    crypto,
    path,
    [
      {
        issuer_authority: "bundle-authority-a",
        key_id: "key-a",
        public_key_pem: retained_runtime_required_env(
          "ACTQL_TEST_NATIVE_REMOTE_RUNTIME_PUBLIC_KEY",
        ),
      },
    ],
    target,
    component.length().to_int64(),
    4,
    8,
    1048576L,
  ).unwrap()
  bundles
  .adopt(
    "actql-remote-runtime-bundle-signature/0.1",
    "key-a",
    bundle_cid,
    retained_runtime_required_env(
      "ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_BODY",
    ),
    retained_runtime_required_env("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_SIGNATURE"),
    "component",
    generation,
  )
  .unwrap()
  |> ignore
  bundles.activate(bundle_cid).unwrap() |> ignore
  let active = bundles
    .acquire_active_component(
      "sha256:" + @sha.hex(component),
      target,
      "retained-consumer-process",
    )
    .unwrap()
  let control = @remote.create_site_dispatch_journal(
    site, "actql-remote-site/0.1",
  ).unwrap()
  let journal = @dispatch_journal.open_journal(
    sqlite,
    path + "/execution.sqlite3",
    1048576L,
    control,
  ).unwrap()
  (bundles, active, journal)
}
