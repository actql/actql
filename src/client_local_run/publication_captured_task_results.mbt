///|
struct LocalCapturedTaskResultPublication[Store, E] {
  preflight : LocalCapturedTaskPublicationPreflight[Store, E]
  index : Int
  output : @host.PublicationOutputExport
  material : LocalResultPublicationMaterial
}

///|
struct LocalCapturedTaskPublicationManifest[Store, E] {
  preflight : LocalCapturedTaskPublicationPreflight[Store, E]
  results : Array[LocalCapturedTaskResultPublication[Store, E]]
  manifest : @publication.PublicationContract
}

///|
fn[E] captured_task_result_issue(
  issue : LocalResultPublicationIssue,
) -> LocalCapturedTaskPublicationPreflightIssue[E] {
  Intent(ResultPublication(issue))
}

///|
fn[Store, E] check_local_captured_result_output(
  preflight : LocalCapturedTaskPublicationPreflight[Store, E],
  index : Int,
  output : @host.PublicationOutputExport,
) -> Result[
  @publication.PublicationContract,
  LocalCapturedTaskPublicationPreflightIssue[E],
] {
  if !output.matches_captured_run(preflight.dag) {
    return Err(captured_task_result_issue(ForeignCompute))
  }
  guard local_captured_task_publication_preflight_result(preflight, index)
    is Some((expected, retention)) else {
    return Err(Intent(MissingResult))
  }
  let definition = match output.definition() {
    Ok(definition) => definition
    Err(issue) => return Err(captured_task_result_issue(Output(issue)))
  }
  if @publication.publication_contract_identity(definition) !=
    @publication.publication_contract_identity(expected) ||
    @publication.publication_contract_json(definition) !=
    @publication.publication_contract_json(expected) {
    return Err(Intent(PreflightMismatch))
  }
  Ok(retention)
}

///|
/// Seal the already completed export with the exact held File preflight.
/// Only the preflight can choose the result ordinal, data policy or retention.
pub fn[Store, E] issue_local_captured_task_result_publication(
  preflight : LocalCapturedTaskPublicationPreflight[Store, E],
  index : Int,
  output : @host.PublicationOutputExport,
  limits : LocalPublicationIntentLimits,
  current : () -> Result[Unit, LocalCapturedTaskPublicationPreflightIssue[E]],
  fund : (Int64, Int64) -> Bool,
) -> Result[
  LocalCapturedTaskResultPublication[Store, E],
  LocalCapturedTaskPublicationPreflightIssue[E],
] {
  current()
  .bind(_ => check_local_captured_result_output(preflight, index, output))
  .bind(retention => {
    let original = preflight.observed.step.publication.step.candidate.task_materials.plan
    let computation = @publication.publication_contract_identity(
      @host.client_compiled_run_plan(original.compiled),
    )
    let inputs = [preflight.source_relation_cid]
    let scope = @publication.publication_contract_identity(original.definition)
    let authority = @host.client_request_authority_scope_cid(original.request)
    let geometry = match
      output.captured_managed_metadata_geometry(
        preflight.dag,
        preflight.invocation,
        retention,
        (computation, inputs, scope, preflight.data_policy_cid, authority),
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(captured_task_result_issue(Output(issue)))
    }
    guard @local.installed_effect_public_result_capacity(geometry, scope)
      is Some(capacity) &&
      fund(
        @execution.execution_capacity_retained_bytes(capacity),
        @execution.execution_capacity_execution_bytes(capacity),
      ) else {
      return Err(Intent(InventoryLimit))
    }
    match current() {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    issue_local_result_material(
      output,
      preflight.invocation,
      retention,
      computation,
      inputs,
      scope,
      preflight.data_policy_cid,
      authority,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
      (definition, artifact, derivation, ordering, retention) => {
        definition,
        artifact,
        derivation,
        ordering,
        retention,
      },
    )
    .map_err(issue => captured_task_result_issue(issue))
    .bind(material => {
      current().map(_ => { preflight, index, output, material, })
    })
  })
}

///|
/// Look back at the same already sealed Result, with no second issuance.
pub fn[Store, E] reuse_local_captured_task_result_publication(
  value : LocalCapturedTaskResultPublication[Store, E],
  preflight : LocalCapturedTaskPublicationPreflight[Store, E],
  index : Int,
  output : @host.PublicationOutputExport,
  current : () -> Result[Unit, LocalCapturedTaskPublicationPreflightIssue[E]],
) -> Result[
  LocalCapturedTaskResultPublication[Store, E],
  LocalCapturedTaskPublicationPreflightIssue[E],
] {
  if !physical_equal(value.preflight, preflight) ||
    value.index != index ||
    !physical_equal(value.output, output) {
    return Err(captured_task_result_issue(ForeignPublication))
  }
  current()
  .bind(_ => check_local_captured_result_output(preflight, index, output))
  .map(_ => value)
}

///|
pub fn[Store, E] start_local_captured_task_result_snapshot(
  result : LocalCapturedTaskResultPublication[Store, E],
  limits : LocalPublicationIntentLimits,
  current : () -> Result[Unit, LocalCapturedTaskPublicationPreflightIssue[E]],
  fund : (Int64, Int64) -> Result[
    Unit,
    LocalCapturedTaskPublicationPreflightIssue[E],
  ],
) -> Result[
  @host.PublicationOutputSnapshotPreparation,
  LocalCapturedTaskPublicationPreflightIssue[E],
] {
  current()
  .bind(_ => {
    check_local_captured_result_output(
      result.preflight,
      result.index,
      result.output,
    )
  })
  .bind(_ => {
    let dag = result.preflight.dag
    guard @strategy.graph_result_occurrence(
        @strategy.captured_dag_graph(dag),
        result.index,
      )
      is Some(occurrence) else {
      return Err(Intent(MissingResult))
    }
    let (bytes, nodes, _, depth) = match
      result.output.snapshot_original_extent(dag, occurrence) {
      Ok(extent) => extent
      Err(issue) => return Err(captured_task_result_issue(Output(issue)))
    }
    guard bytes > 0 &&
      bytes <= limits.max_wire_bytes &&
      nodes > 0 &&
      nodes <= limits.max_nodes &&
      depth >= 0 &&
      depth <= limits.max_depth &&
      @local.original_recursive_result_snapshot_capacity(
        occurrence, bytes, nodes, depth,
      )
      is Some((retained, temporary)) else {
      return Err(Intent(InventoryLimit))
    }
    fund(retained, temporary)
    .bind(_ => current())
    .bind(_ => {
      result.output
      .start_captured_snapshot(bytes, nodes, depth)
      .map_err(issue => captured_task_result_issue(Output(issue)))
    })
  })
}

///|
fn captured_task_publication_inventory_funding(
  slots : Int64,
  fund : (Int64, Int64) -> Bool,
) -> Bool {
  guard @execution.execution_capacity_inventory_add(
      8192L,
      CursorRootSlots,
      slots,
      4,
    )
    is Some(workspace) else {
    return false
  }
  fund(0L, workspace)
}

///|
fn captured_task_publication_material_funding(
  bytes : Int,
  nodes : Int,
  depth : Int,
  fund : (Int64, Int64) -> Bool,
) -> Bool {
  // The issuer measures before the final self CID and outer key are added.
  guard bytes >= 0 &&
    bytes <= 2147483551 &&
    nodes >= 0 &&
    depth >= 0 &&
    @execution.checked_preparation_add_product(16L, nodes.to_int64(), 1L)
    is Some(slots) &&
    @host.client_protocol_metadata_construction_bytes(
      bytes + 96,
      slots,
      copies=1,
    )
    is Some((retained, _)) &&
    @host.client_protocol_metadata_construction_bytes(
      bytes + 96,
      slots + depth.to_int64(),
      copies=2,
    )
    is Some((execution, _)) else {
    return false
  }
  fund(retained, execution)
}

///|
/// Keep every original authored Result in the order of the sealed inventory.
pub fn[Store, E] issue_local_captured_task_publication_manifest(
  preflight : LocalCapturedTaskPublicationPreflight[Store, E],
  results : Array[LocalCapturedTaskResultPublication[Store, E]],
  limits : LocalPublicationIntentLimits,
  current : () -> Result[Unit, LocalCapturedTaskPublicationPreflightIssue[E]],
  fund : (Int64, Int64) -> Bool,
) -> Result[
  LocalCapturedTaskPublicationManifest[Store, E],
  LocalCapturedTaskPublicationPreflightIssue[E],
] {
  match current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if results.length() !=
    local_captured_task_publication_preflight_count(preflight) ||
    results.length() > limits.max_results {
    return Err(Intent(PreflightMismatch))
  }
  for index, result in results {
    if !physical_equal(result.preflight, preflight) ||
      result.index != index ||
      !result.output.matches_captured_run(preflight.dag) {
      return Err(captured_task_result_issue(ForeignPublication))
    }
  }
  let original = preflight.observed.step.publication.step.candidate.task_materials.plan
  let refused = Ref(false)
  let manifest = @publication.issue_result_manifest(
    original.definition,
    preflight.invocation,
    results.map(result => result.material.definition),
    results.map(result => result.material.artifact),
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
    funding=Some(
      (
        count => {
          let allowed = captured_task_publication_inventory_funding(
            count.to_int64(),
            fund,
          )
          refused.val = !allowed
          allowed
        },
        (bytes, nodes, depth) => {
          let allowed = captured_task_publication_material_funding(
            bytes, nodes, depth, fund,
          )
          refused.val = !allowed
          allowed
        },
      ),
    ),
  )
  if refused.val {
    return Err(Intent(InventoryLimit))
  }
  manifest
  .map_err(issue => captured_task_result_issue(Manifest(issue)))
  .bind(manifest => {
    current().map(_ => { preflight, results: results.copy(), manifest, })
  })
}

///|
pub fn[Store, E] local_captured_task_publication_manifest_contract(
  value : LocalCapturedTaskPublicationManifest[Store, E],
) -> @publication.PublicationContract {
  value.manifest
}

///|
/// Issue the Effect-free Receipt and begin the bounded original capture.
/// The issuer checks original invocation/observation and Source evidence.
/// No Store index, payload binding or write acknowledgement is produced here.
pub fn[Store, E] start_local_captured_task_publication_capture(
  value : LocalCapturedTaskPublicationManifest[Store, E],
  observation : @publication.RunEvidenceValue,
  source_evidence : @publication.RunEvidenceValue,
  snapshots : Array[@publication.CapturedResultSnapshot],
  limits : LocalPublicationIntentLimits,
  max_workspace_slots : Int,
  current : () -> Result[Unit, LocalCapturedTaskPublicationPreflightIssue[E]],
  fund : (Int64, Int64) -> Bool,
) -> Result[
  (
    @publication.CapturedRunIssuancePreparation,
    @publication.PublicationContract,
  ),
  LocalCapturedTaskPublicationPreflightIssue[E],
] {
  match current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if snapshots.length() != value.results.length() {
    return Err(Intent(PreflightMismatch))
  }
  let preflight = value.preflight
  for result in value.results {
    if !result.output.matches_captured_run(preflight.dag) {
      return Err(captured_task_result_issue(ForeignCompute))
    }
  }
  let original = preflight.observed.step.publication.step.candidate.task_materials.plan
  let prepared = @host.client_captured_task_run_materials_prepared(original)
  // The existing normalization writer has its own fixed 1 KiB / 32 node
  // contract envelope. Keep it live beside the later Receipt constructors.
  guard @host.client_protocol_metadata_construction_bytes(1024, 32L, copies=2)
    is Some((normalization_peak, _)) &&
    fund(normalization_peak, normalization_peak) else {
    return Err(Intent(InventoryLimit))
  }
  let normalization = match
    @host.issue_prepared_client_local_normalization(prepared).bind(original => {
      @host.prepared_client_local_normalization_evidence(prepared, original)
    }) {
    Ok(journal) => journal
    Err(issue) => {
      let typed = LocalRunNormalizationIssue::Normalization(issue)
      return Err(
        captured_task_result_issue(
          LocalResultPublicationIssue::Normalization(typed),
        ),
      )
    }
  }
  let authoring = match
    @local.issue_funded_capture_authoring_context(
      prepared,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
      fund,
    ) {
    Some(Ok(value)) => value
    Some(Err(issue)) => return Err(captured_task_result_issue(Authoring(issue)))
    None => return Err(Intent(InventoryLimit))
  }
  match current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let definitions = value.results.map(result => result.material.definition)
  let artifacts = value.results.map(result => result.material.artifact)
  let funding_refused = Ref(false)
  let issued = @publication.issue_effect_free_run_receipt(
    @host.client_compiled_run_admission(original.compiled),
    original.definition,
    preflight.invocation,
    observation,
    definitions,
    artifacts,
    value.manifest,
    normalization,
    [],
    [],
    [source_evidence],
    [],
    [],
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
    funding=Some(
      (
        slots => {
          let allowed = captured_task_publication_inventory_funding(slots, fund)
          funding_refused.val = !allowed
          allowed
        },
        (bytes, nodes, depth) => {
          let allowed = captured_task_publication_material_funding(
            bytes, nodes, depth, fund,
          )
          funding_refused.val = !allowed
          allowed
        },
      ),
    ),
  )
  if funding_refused.val {
    return Err(Intent(InventoryLimit))
  }
  let receipt = match issued {
    Ok(value) => value
    Err(issue) => return Err(captured_task_result_issue(Receipt(issue)))
  }
  match current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard captured_task_publication_inventory_funding(
      3L * snapshots.length().to_int64(),
      fund,
    ) &&
    @publication.prepare_original_effect_free_capture_plan(
      original.definition,
      preflight.invocation,
      definitions,
      artifacts,
      value.manifest,
      receipt,
      snapshots,
      authoring,
      [],
      limits=Some(
        (
          limits.max_wire_bytes,
          limits.max_nodes,
          limits.max_depth,
          max_workspace_slots,
        ),
      ),
    )
    is Some(plan) else {
    return Err(Intent(InventoryLimit))
  }
  defer @publication.cancel_capture_construction_plan(plan)
  guard @local.installed_effect_capture_constructor_capacity(
      plan,
      0,
      0,
      0,
      0,
      0,
      0,
      [],
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
      _ => true,
    )
    is Some(capacity) &&
    fund(
      @execution.execution_capacity_retained_bytes(capacity),
      @execution.execution_capacity_execution_bytes(capacity),
    ) else {
    return Err(Intent(InventoryLimit))
  }
  current().bind(_ => {
    match @publication.start_planned_captured_run(plan) {
      Some(capture) => Ok((capture, receipt))
      None => Err(Intent(PreflightMismatch))
    }
  })
}

///|
fn[Store, E] captured_task_payload_target(
  preflight : LocalCapturedTaskPublicationPreflight[Store, E],
) -> (String, String) {
  (
    preflight.observed.step.publication.step.store_authority_cid,
    @publication.publication_contract_identity(preflight.contracts.attempt),
  )
}

///|
pub fn[Store, E] prepare_local_captured_task_payload_request(
  preflight : LocalCapturedTaskPublicationPreflight[Store, E],
  ordinal : Int,
  original : LocalCapturedTaskResultPublication[Store, E],
  store : String,
  generation : String,
  max_bytes : Int64,
  current : () -> Result[Unit, LocalCapturedTaskPublicationPreflightIssue[E]],
) -> Result[
  @payload.PublicationPayloadRequest,
  LocalCapturedTaskPublicationPreflightIssue[E],
] {
  reuse_local_captured_task_result_publication(
    original,
    preflight,
    ordinal,
    original.output,
    current,
  ).bind(_ => {
    let (target, attempt) = captured_task_payload_target(preflight)
    if store != target {
      return Err(Payload(@host.RequestMismatch))
    }
    original.output
    .prepare_payload_request(attempt, target, generation, max_bytes)
    .map_err(issue => Payload(issue))
  })
}

///|
pub fn[Store, E] prepare_local_captured_task_payload_replay(
  preflight : LocalCapturedTaskPublicationPreflight[Store, E],
  ordinal : Int,
  original : LocalCapturedTaskResultPublication[Store, E],
  request : @payload.PublicationPayloadRequest,
  current : () -> Result[Unit, LocalCapturedTaskPublicationPreflightIssue[E]],
) -> Result[
  @host.PublicationOutputReplay,
  LocalCapturedTaskPublicationPreflightIssue[E],
] {
  reuse_local_captured_task_result_publication(
    original,
    preflight,
    ordinal,
    original.output,
    current,
  ).bind(_ => {
    let (target, attempt) = captured_task_payload_target(preflight)
    if @payload.publication_payload_request_store_authority(request) != target ||
      @payload.publication_payload_request_attempt(request) != attempt {
      return Err(Payload(@host.RequestMismatch))
    }
    original.output
    .replay_payload_request(request)
    .map_err(issue => Payload(issue))
  })
}

///|
pub fn[Store, E] issue_local_captured_task_sealed_result_binding(
  preflight : LocalCapturedTaskPublicationPreflight[Store, E],
  ordinal : Int,
  original : LocalCapturedTaskResultPublication[Store, E],
  record : @payload.PublicationPayloadRecord,
  limits : LocalPublicationIntentLimits,
  current : () -> Result[Unit, LocalCapturedTaskPublicationPreflightIssue[E]],
) -> Result[
  @publication.PublicationContract,
  LocalCapturedTaskPublicationPreflightIssue[E],
] {
  reuse_local_captured_task_result_publication(
    original,
    preflight,
    ordinal,
    original.output,
    current,
  ).bind(_ => {
    let request = @payload.publication_payload_record_request(record)
    let (target, attempt) = captured_task_payload_target(preflight)
    if @payload.publication_payload_request_store_authority(request) != target ||
      @payload.publication_payload_request_attempt(request) != attempt {
      return Err(Payload(@host.RequestMismatch))
    }
    let run = preflight.observed.step.publication.step.candidate.task_materials.plan
    original.output
    .issue_sealed_durable_binding(
      run.definition,
      preflight.invocation,
      original.material.retention,
      record,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    .map_err(issue => Payload(issue))
  })
}

///|
fn captured_task_index_inventory_bytes(
  units : @publication.EffectPreviewIdentityConstructionInventory,
) -> Int64? {
  @execution.preparation_representation_cost({
    record_headers: units.record_headers,
    reference_slots: units.reference_slots,
    scalar_words: units.scalar_words,
    owned_utf16_units: units.owned_utf16_units,
    owned_wire_bytes: units.owned_wire_bytes,
  })
}

///|
/// Reuse the checked File artifact/receipt/capture chain and the same sealed
/// binding inventory. This constructs the existing bounded candidate only.
pub fn[Store, E] prepare_local_captured_task_commit_candidate(
  manifest : LocalCapturedTaskPublicationManifest[Store, E],
  capture : @publication.CapturedRunIssuancePreparation,
  receipt : @publication.PublicationContract,
  captured_run : @publication.PublicationContract,
  bindings : Array[@publication.PublicationContract],
  committed_at : String,
  limits : LocalPublicationIntentLimits,
  max_workspace : Int,
  current : () -> Result[Unit, LocalCapturedTaskPublicationPreflightIssue[E]],
  fund : (Int64, Int64) -> Bool,
) -> Result[
  (@publication.PublicationContract, @publication.PublicationCommitPreparation),
  LocalCapturedTaskPublicationPreflightIssue[E],
] {
  match current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let preflight = manifest.preflight
  let count = local_captured_task_publication_preflight_count(preflight)
  if count != bindings.length() ||
    count != manifest.results.length() ||
    count > limits.max_results {
    return Err(Intent(PreflightMismatch))
  }
  for ordinal, result in manifest.results {
    if result.index != ordinal ||
      !physical_equal(result.preflight, preflight) ||
      !result.output.matches_captured_run(preflight.dag) {
      return Err(captured_task_result_issue(ForeignPublication))
    }
  }
  let run = preflight.observed.step.publication.step.candidate.task_materials.plan
  let (request, attempt) = local_captured_task_publication_preflight_contracts(
    preflight,
  )
  // The caller has funded the measuring cursor and the reference vectors.
  // Only the newly issued Index owns a new protocol representation.
  let geometry = match
    @publication.public_index_entry_construction_geometry(
      run.definition,
      preflight.invocation,
      manifest.manifest,
      receipt,
      captured_run,
      bindings,
      request,
      attempt,
      committed_at,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Intent(CommitCandidate(issue)))
  }
  guard @publication.publication_wire_construction_inventory(geometry)
    is Some((retained, codec)) &&
    captured_task_index_inventory_bytes(retained) is Some(retained_bytes) &&
    captured_task_index_inventory_bytes(codec) is Some(codec_bytes) &&
    @encode.text_writer_live_key_inventory(geometry.bytes, 12, geometry.depth)
    is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers,
      reference_slots: writer.reference_slots,
      scalar_words: writer.scalar_words,
      owned_utf16_units: writer.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(writer_bytes) &&
    @execution.checked_preparation_add_product(retained_bytes, codec_bytes, 1L)
    is Some(construction) &&
    @execution.checked_preparation_add_product(construction, writer_bytes, 1L)
    is Some(execution_bytes) &&
    fund(retained_bytes, execution_bytes) else {
    return Err(Intent(InventoryLimit))
  }
  match current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let index = match
    @publication.issue_public_index_entry(
      run.definition,
      preflight.invocation,
      manifest.manifest,
      receipt,
      captured_run,
      bindings,
      request,
      attempt,
      committed_at,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Err(issue) => return Err(Intent(CommitCandidate(issue)))
    Ok(value) => value
  }
  current().map(_ => {
    (
      index,
      @publication.start_effect_free_publication_commit_check_retained(
        capture,
        run.definition,
        preflight.invocation,
        manifest.results.map(result => result.material.definition),
        manifest.results.map(result => result.material.artifact),
        manifest.results.map(result => result.material.derivation),
        manifest.results.map(result => result.material.ordering),
        // Each named Result refers to this original policy. Commit evidence
        // contains its admitted identity once.
        [preflight.retention],
        bindings,
        manifest.manifest,
        receipt,
        captured_run,
        request,
        attempt,
        index,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
        max_workspace,
      ),
    )
  })
}

///|
pub fn[Store, E] local_captured_task_result_schema_field(
  preflight : LocalCapturedTaskPublicationPreflight[Store, E],
  ordinal : Int,
  original : LocalCapturedTaskResultPublication[Store, E],
  field : LocalResultSchemaField,
  current : () -> Result[Unit, LocalCapturedTaskPublicationPreflightIssue[E]],
) -> Result[String, LocalCapturedTaskPublicationPreflightIssue[E]] {
  reuse_local_captured_task_result_publication(
    original,
    preflight,
    ordinal,
    original.output,
    current,
  ).bind(_ => {
    let projected = match field {
      Identity => original.output.result_schema_cid()
      Wire => original.output.result_schema_wire()
    }
    projected.map_err(issue => captured_task_result_issue(Output(issue)))
  })
}
