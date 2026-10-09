// Actual Native consumer export and SQLite/filesystem custody. Publication
// attempt/material/codec and provider target are explicit protocol fixtures.
// Reopening this Store retains the live execution Ledger owner; it does not
// establish Host restart, approval, encrypted Preview persistence or Cloud use.

///|
fn retained_effect_source_store(
  consumer : @resident.ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  artifact : @host.ClientEffectLocalResultArtifact,
  source : @publication.CapturedEffectSourceArtifact,
  local_result : Int,
  stop_custodies : Array[(@resident.ResidentEffectSourceCustody, @store.Store)],
) -> Unit raise {
  let root_path = @env.get_env_var("ACTQL_TEST_NATIVE_RETAINED_TASK_ROOT").unwrap()
  let root = @filesystem.open_root(root_path).unwrap()
  let child = "effect-source-custody-" + @env.now().to_string()
  root.create_directory(child).unwrap() |> ignore
  let path = root_path + "/" + child
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let authority = @publication.captured_effect_source_store_authority_cid(
    source,
  )
  let open = () => {
    @store.open_store(library, path, authority, 536870912L, 8L, 262144L).unwrap()
  }
  let definition = @host.issue_captured_client_effect_local_result_definition(
    materials.prepared,
    inputs,
    0,
    65536,
    4096,
    64,
  ).unwrap()
  let ordering = @publication.admit_publication_contract(
    "ordering_evidence",
    @host.client_effect_local_result_ordering_json(artifact),
    65536,
    4096,
    64,
  ).unwrap()
  let (logical, schema, rows, _) = @publication.captured_effect_source_payload_facts(
    source,
    materials.run_definition,
  ).unwrap()
  let request = (token : String, schema : String, max_bytes : Int64) => {
    @payload.prepare_publication_payload_request(
      authority,
      "sha256:" + @sha.hex(@utf8.encode(token + "-fixture-attempt")),
      "sha256:" + @sha.hex(@utf8.encode(token + "-fixture-material")),
      @host.client_effect_local_result_definition_cid(definition),
      logical,
      schema,
      @publication.publication_contract_identity(ordering),
      retained_compute_cid("f"),
      max_bytes,
      rows,
    ).unwrap()
  }
  println("retained-effect-custody: native facts admitted")
  let mut store = open()
  let closed = Ref(false)
  let allocations = Ref(0)
  store.observe_allocation(step => {
    if step == "allocated" {
      allocations.val += 1
    }
  })
  let baseline = consumer.usage().reserved_retention_bytes
  let rejected = consumer.retain_effect_source_custody(
    store,
    materials,
    inputs,
    0,
    artifact,
    source,
    request("foreign", retained_compute_cid("b"), 64L),
  )
  assert_true(rejected is Err({ issue: Binding(_), custody: None, }))
  assert_eq(allocations.val, 0)
  assert_eq(consumer.usage().reserved_retention_bytes, baseline)
  assert_true(
    consumer.retain_effect_source_custody(
      store,
      materials,
      inputs,
      0,
      artifact,
      source,
      request("too-large", schema, 536870913L),
    )
    is Err({ issue: Capacity(_), custody: None, }),
  )
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)

  // A lost intent persistence reply produces no writer. The same live prepared
  // owner keeps its original reservation and reconciles the committed record.
  store.observe_allocation(step => {
    if step == "effect-custody-intent-saved" {
      closed.val = store.close().unwrap()
    }
  })
  let first_request = request("normal", schema, 64L)
  let failed = consumer.retain_effect_source_custody(
    store, materials, inputs, 0, artifact, source, first_request,
  )
  guard failed is Err({ issue: Store(Closed), custody: Some(custody), }) else {
    fail("lost custody reply dropped its owner or admitted a writer")
  }
  assert_eq(consumer.usage().reserved_retention_bytes, baseline + 64L)
  assert_true(closed.val)
  closed.val = false
  store = open()
  custody.restore_store(store).unwrap()
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_eq(consumer.usage().reserved_retention_bytes, baseline + 64L)
  let duplicate = consumer
    .retain_effect_source_custody(
      store, materials, inputs, 0, artifact, source, first_request,
    )
    .unwrap()
  assert_true(physical_equal(duplicate, custody))
  assert_eq(consumer.usage().reserved_retention_bytes, baseline + 64L)
  println("retained-effect-custody: original intent reconciled")
  let writer = custody.begin_payload().unwrap()
  let exported = consumer
    .prepare_effect_result_export(
      inputs,
      local_result,
      resident_compute_limits(),
    )
    .unwrap()
  let preparation = @strategy.captured_effect_local_result_export_preparation(
    exported,
  )
  while !@execution.advance_completed_result_relation_export(preparation, 16).unwrap().0 {
    continue
  }
  let stream = @execution.finish_completed_result_relation_export_preparation(
    preparation,
  ).unwrap()
  let observed = StringBuilder()
  while @execution.next_completed_output_export(stream).unwrap() is Some(chunk) {
    observed.write_string(chunk)
    writer.append(@utf8.encode(chunk)).unwrap()
  }
  let (receipt, tail) = @execution.finish_completed_relation_export(stream).unwrap()
  observed.write_string(tail)
  writer.append(@utf8.encode(tail)).unwrap()
  assert_eq(observed.to_string(), "[{\"id\":3}]")
  assert_true(
    @strategy.captured_effect_local_result_export_matches_receipt(
      inputs, exported, receipt,
    ),
  )
  writer.seal().unwrap() |> ignore
  custody.confirm_payload().unwrap() |> ignore
  println("retained-effect-custody: exact payload sealed")
  @execution.cancel_completed_relation_export_receipt(receipt)
  @execution.cancel_completed_output_export(stream)
  assert_true(custody.begin_payload() is Err(Store(ExistingPayload)))
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 64L)
  assert_true(store.close().unwrap())
  store = open()
  custody.restore_store(store).unwrap()
  let reader = custody.open_reader().unwrap()
  assert_true(custody.retry_cleanup() is Err(Store(ReaderBusy)))
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 64L)
  assert_eq(consumer.usage().reserved_retention_bytes, baseline + 64L)
  let restored = StringBuilder()
  while true {
    let chunk = reader.next(3).unwrap()
    restored.write_string(@utf8.decode_lossy(chunk.bytes))
    if chunk.eof {
      break
    }
  }
  reader.finish().unwrap()
  assert_eq(restored.to_string(), "[{\"id\":3}]")
  // The physical Owner has reclaimed its payload, but a lost terminal metadata
  // write still keeps the execution reservation and exact cleanup responsibility.
  store.observe_allocation(step => {
    if step == "effect-custody-before-terminal" {
      closed.val = store.close().unwrap()
    }
  })
  assert_true(custody.retry_cleanup() is Err(Store(Closed)))
  assert_eq(consumer.usage().reserved_retention_bytes, baseline + 64L)
  assert_true(closed.val)
  closed.val = false
  store = open()
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  custody.restore_store(store).unwrap()
  assert_true(custody.retry_cleanup().unwrap())
  assert_false(custody.retry_cleanup().unwrap())
  assert_eq(consumer.usage().reserved_retention_bytes, baseline)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)

  // Intent persistence fails before a commit: retain the same prepared owner,
  // then reconcile its original intent and release it without payload allocation.
  store.observe_allocation(step => {
    if step == "effect-custody-before-intent" {
      closed.val = store.close().unwrap()
    }
  })
  let failed = consumer.retain_effect_source_custody(
    store,
    materials,
    inputs,
    0,
    artifact,
    source,
    request("no-write", schema, 64L),
  )
  guard failed is Err({ issue: Store(Closed), custody: Some(uncommitted), }) else {
    fail("uncommitted custody lost its prepared cleanup owner")
  }
  assert_true(closed.val)
  closed.val = false
  store = open()
  uncommitted.restore_store(store).unwrap()
  assert_true(uncommitted.retry_cleanup().unwrap())
  assert_false(uncommitted.retry_cleanup().unwrap())
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_eq(consumer.usage().reserved_retention_bytes, baseline)

  // A partial writer remains the same cleanup obligation; no replacement writer
  // or source/consumer execution is admitted to conceal its incomplete outcome.
  let partial = consumer
    .retain_effect_source_custody(
      store,
      materials,
      inputs,
      0,
      artifact,
      source,
      request("partial", schema, 64L),
    )
    .unwrap()
  let writer = partial.begin_payload().unwrap()
  writer.append(b"[").unwrap()
  assert_true(partial.retry_cleanup() is Err(Store(CleanupPending)))
  assert_true(partial.begin_payload() is Err(Store(RecoveryRequired)))
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 64L)
  assert_eq(consumer.usage().reserved_retention_bytes, baseline + 64L)
  writer.cancel().unwrap()
  assert_true(partial.retry_cleanup().unwrap())
  assert_false(partial.retry_cleanup().unwrap())
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_eq(consumer.usage().reserved_retention_bytes, baseline)
  // Leave an original custody live until the caller stops this same consumer.
  // Its retained input is still borrowed while physical cleanup remains pending.
  let stop_custody = consumer.retain_effect_source_custody(
    store, materials, inputs, 0, artifact, source,
    request("stop-before-payload", schema, 64L),
  ).unwrap()
  stop_custodies.push((stop_custody, store))
  println(
    "retained-effect-custody: exact Native bytes restored; pending cleanup retried once",
  )
}
