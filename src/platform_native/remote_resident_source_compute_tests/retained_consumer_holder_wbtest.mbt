///|
/// Actual producer/receiver Owners from acquisition_runtime_case. This selects
/// the holder connection before any physical borrow is pinned by the older
/// direct executor diagnostic. HTTP acceptance is a separate boundary.
fn retained_consumer_holder_case(
  handoff : @resident.ResidentRetainedTransfer,
  producer_journal : @dispatch_journal.Journal,
  materials : @host.ClientRunMaterials,
  admission : @resident.ResidentRunAdmission,
  configuration : @resident.ResidentSourceComputeConfiguration,
  input : @host.ClientRetainedTaskInput,
  dispatch : @remote.DispatchRequest,
  another_attempt : @remote.DispatchRequest,
  site : @site.ExecutionSite,
  sqlite : @sqlite.Library,
  root_path : String,
  name : String,
  destination_journal : @journal.Journal,
  destination_bytes : Int64,
  current_query : @remote.RemotePollRetainedCurrent,
  cancel_before_start? : Bool = false,
  output_unavailable? : Bool = false,
) -> Unit raise {
  let environment = @host.admit_client_check_environment(
    resident_effect_source_environment,
    "sha256:feb4443bd80a5e95c14e195113219eeb2e24bdd12e424d1ba00c1295f5c53554",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  guard materials.compilation is @host.Tasks(compilation) else {
    fail("expected checked tasks")
  }
  let wire = @host.issue_client_task_run_materials(
    materials.prepared,
    compilation,
    materials.admission,
    materials.run_definition,
    environment,
    resident_effect_source_environment,
    resident_compute_document,
    None,
  ).unwrap()
  let binding = @host.client_retained_task_input_binding(input)
  let envelope = @remote.remote_poll_dispatch_materials_json(
    dispatch, binding, wire,
  ).unwrap()
  let poll = @remote.admit_remote_poll_dispatch_json(envelope).unwrap()
  // A valid physical receipt cannot bless a foreign checked consumer port.
  let foreign_binding = @remote.prepare_remote_input_binding(
    @remote.remote_input_binding_body(binding).replace(
      old="\"consumer_input_port\":\"x\"",
      new="\"consumer_input_port\":\"other\"",
    ),
    262144,
  ).unwrap()
  assert_false(
    @remote.remote_input_binding_cid(foreign_binding) ==
    @remote.remote_input_binding_cid(binding),
  )
  // The existing envelope issuer refuses mismatched request/input identity
  // before a retained consumer can be prepared or any physical borrow starts.
  assert_true(
    @remote.remote_poll_dispatch_materials_json(dispatch, foreign_binding, wire)
    is Err(_),
  )
  let before = @site.site_status(site)
  let owner = @resident.prepare_resident_retained_consumer(
    handoff,
    producer_journal,
    admission,
    poll,
    "2026-10-05T00:00:00.000Z",
    {
      max_binding_bytes: 262144,
      max_chunks: 100,
      max_manifest_bytes: 4096,
      max_referenced_bytes: 1048576L,
    },
  ).unwrap()
  let duplicate = @resident.prepare_resident_retained_consumer(
    handoff,
    producer_journal,
    admission,
    poll,
    "2026-10-05T00:00:00.000Z",
    {
      max_binding_bytes: 262144,
      max_chunks: 100,
      max_manifest_bytes: 4096,
      max_referenced_bytes: 1048576L,
    },
  ).unwrap()
  let different = @remote.admit_remote_poll_dispatch_json(
    @remote.remote_poll_dispatch_materials_json(another_attempt, binding, wire).unwrap(),
  ).unwrap()
  assert_true(
    @resident.prepare_resident_retained_consumer(
      handoff,
      producer_journal,
      admission,
      different,
      "2026-10-05T00:00:00.000Z",
      {
        max_binding_bytes: 262144,
        max_chunks: 100,
        max_manifest_bytes: 4096,
        max_referenced_bytes: 1048576L,
      },
    )
    is Err(_),
  )
  assert_eq(@site.site_status(site), before)
  assert_eq(
    destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
    destination_bytes,
  )
  let configuration = {
    ..configuration,
    source: {
      ..configuration.source,
      retained_output_root: Some(
        if output_unavailable {
          root_path + "/missing-output-root"
        } else {
          root_path
        },
      ),
    },
  }
  let (bundles, active, journal) = retained_runtime_owners(
    sqlite, site, root_path, name,
  )
  // The same existing Site Owner saves the exact envelope before execution.
  journal.retain_dispatch_envelope(dispatch, envelope).unwrap()
  journal.accept(dispatch).unwrap() |> ignore
  let scope = @remote.dispatch_request_execution_scope(dispatch)
  let execution : @resident.ResidentExecution = {
    site,
    active_runtime: active,
    bundles,
    operation_capability_cid: scope[6],
    issuer_capability_cid: scope[7],
    budgets: [
      @remote.prepare_remote_dispatch_budget(1048576L, 1048576L).unwrap(),
    ],
    registry_body: configuration.registry_body,
    values_body: configuration.values_body,
    fixed_ms: 1L,
    per_row_ms: 0L,
    per_wire_byte_ms: 0L,
    per_pair_ms: 0L,
    source: Some(configuration.source),
    limits: {
      finalization_quantum: 256,
      max_finalization_rounds: 100,
      row_decode: retained_compute_input_limits().wire,
      bridge_max_entries: 100,
      bridge_max_name_bytes: 10000,
      output: {
        output_export: resident_compute_limits(),
        max_manifest_bytes: 4096,
        max_retained_bytes: 1048576L,
      },
    },
  }
  let entries = Ref(0)
  let run = () => {
    owner.execute(
      journal,
      execution,
      admission,
      configuration,
      retained_compute_input_limits(),
      "original-producer-holder",
      () => "2026-10-05T00:00:00.000Z",
      Some(key => {
        if key != @remote.remote_dispatch_attempt_key(dispatch) {
          return false
        }
        entries.val += 1
        true
      }),
    )
  }
  if cancel_before_start {
    let cancelled = journal.request_cancellation(dispatch).unwrap()
    let revision = @remote.dispatch_record_revision(cancelled)
    assert_false(@remote.remote_runtime_record_startable(cancelled))
    assert_true(run() is Err(_))
    assert_eq(entries.val, 0)
    assert_eq(@site.site_status(site), before)
    assert_eq(
      destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
      destination_bytes,
    )
    assert_true(owner.close())
    assert_true(owner.close())
    assert_eq(
      @remote.dispatch_record_revision(journal.require(dispatch).unwrap()),
      revision,
    )
    assert_true(journal.close())
    assert_true(bundles.close().unwrap())
    return
  }
  if output_unavailable {
    assert_true(run() is Err(_))
    assert_eq(entries.val, 1)
    // Missing physical output is not permission to enter Compute again.
    assert_true(run() is Err(_))
    assert_eq(entries.val, 1)
    assert_eq(
      destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
      destination_bytes,
    )
    assert_true(owner.close())
    assert_true(owner.close())
    assert_eq(
      destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
      destination_bytes,
    )
    assert_true(journal.close())
    assert_true(bundles.close().unwrap())
    return
  }
  let executed = run().unwrap()
  assert_true(executed.result_definition_cid is Some(_))
  assert_eq(entries.val, 1)
  assert_eq(
    duplicate
    .execute(
      journal,
      execution,
      admission,
      configuration,
      retained_compute_input_limits(),
      "original-producer-holder",
      () => "2026-10-05T00:00:00.000Z",
      Some(_ => {
        entries.val += 1
        true
      }),
    )
    .unwrap().completion.evidence_cid,
    executed.completion.evidence_cid,
  )
  assert_eq(
    run().unwrap().completion.evidence_cid,
    executed.completion.evidence_cid,
  )
  assert_eq(entries.val, 1)
  // Completion must name the original file custody before it is available for
  // Output. A process-local completion alone cannot survive holder loss.
  let custody = @dispatch_journal.recovered_site_dispatch_file_custody(
    journal.observation(dispatch).unwrap(),
  ).unwrap()
  assert_true(
    @dispatch_journal.native_output_file_custody_matches_request(
      custody, dispatch,
    ),
  )
  let occurrence = @dispatch_journal.native_output_file_custody_occurrence(
    custody,
  )
  let generation = @dispatch_journal.native_output_file_custody_generation(
    custody,
  )
  let file_root = @filesystem.open_root(root_path).unwrap()
  assert_true(file_root.verify_generation("output-" + occurrence, generation))
  let read_back = @dispatch_journal.open_journal(
    sqlite,
    root_path + "/" + name + ".runtime/execution.sqlite3",
    1048576L,
    @remote.create_site_dispatch_journal(site, "actql-remote-site/0.1").unwrap(),
  ).unwrap()
  let durable_custody = @dispatch_journal.recovered_site_dispatch_file_custody(
    read_back.observation(dispatch).unwrap(),
  ).unwrap()
  assert_eq(
    @dispatch_journal.native_output_file_custody_occurrence(durable_custody),
    occurrence,
  )
  assert_eq(
    @dispatch_journal.native_output_file_custody_generation(durable_custody),
    generation,
  )
  assert_eq(
    @dispatch_journal.native_output_file_custody_content_cid(durable_custody),
    @dispatch_journal.native_output_file_custody_content_cid(custody),
  )
  assert_true(read_back.close())
  let subject = @dispatch_journal.recovered_site_dispatch_subject(
    journal.observation(dispatch).unwrap(),
  ).unwrap()
  let fields = @remote.remote_managed_output_subject_projection(subject)
  let facts = executed.runtime
    .inspect_output_facts(dispatch, fields[1])
    .unwrap()
  assert_eq(facts.row_count, 1)
  assert_eq(
    facts.result_schema_cid,
    "sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513",
  )
  // A live Result reader prevents Runtime cleanup. The same consumer and both
  // independent holdings retain their responsibility until the reader ends.
  let reader = executed.runtime
    .open_output_reader(dispatch, fields[1], 128)
    .unwrap()
  assert_false(owner.close())
  assert_true(file_root.verify_generation("output-" + occurrence, generation))
  assert_eq(
    destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
    destination_bytes,
  )
  assert_true(handoff.reclaim() is Err(_))
  assert_true(
    handoff.current_reply(current_query) is Err(@resident.CleanupPending),
  )
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
  assert_true(owner.close())
  assert_true(owner.close())
  let file_root = @filesystem.open_root(root_path).unwrap()
  assert_false(file_root.verify_generation("output-" + occurrence, generation))
  assert_true(run() is Err(_))
  assert_eq(entries.val, 1)
  let (_, _, cleanup, _, _) = @remote.dispatch_record_state(
    journal.require(dispatch).unwrap(),
  )
  assert_true(cleanup is @remote.CleanupReleased)
  // Returning the borrow does not reclaim the independent receiver.
  assert_eq(
    destination_journal.destination_capacity_usage().unwrap().reserved_bytes,
    destination_bytes,
  )
  assert_true(journal.close())
  assert_true(bundles.close().unwrap())
}
