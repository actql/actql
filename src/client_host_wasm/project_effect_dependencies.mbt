///|
// Keep the same Managed Run's standard dependency budget and closure
// validators. The Host only projects preimages and nominal Artifact roots.
fn prepare_original_mock_effect_dependencies(
  value : Instance,
  drive : StoredMockEffectTaskDrive,
  managed : @local_host.ClientInstalledManagedRun,
  targets : StoredMockEffectTargetDrive,
  original : MockEffectJournalObservationOriginal,
  artifacts : Array[StoredMockEffectArtifact],
  inputs : @strategy.CapturedEffectInputs,
  unit : @host.ClientEffectCombinedSourceUnit,
) -> Int {
  guard targets.workspace is None &&
    original.configuration.sdk is Some(sdk) &&
    original.configuration.host_current is Some(handle) &&
    value.host_currents.get(handle) is Some(current) else {
    return -32
  }
  let prepared = original.journal.materials.prepared
  let request = original.effect.request
  let plan = original.effect.plan
  let limits = @host.client_standard_effect_computation_limits().effects
  let bytes = limits.max_admission_text_bytes
  let nodes = limits.max_admission_nodes
  let depth = limits.max_admission_depth
  let (program, stage, sources) = @host.client_effect_combined_source_unit_catalog_subject(
    unit,
  )
  guard @checked.checked_local_dependency_static_count(program, stage)
    is Some(statics) else {
    return -31
  }
  guard @execution.preparation_representation_cost({
      record_headers: 40L + 6L * sources.to_int64(),
      reference_slots: 160L + 12L * sources.to_int64(),
      scalar_words: 50L + 4L * sources.to_int64(),
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(fixed) &&
    @resources.reserve_capacity(drive.ledger, 0L, fixed) is Ok(work) else {
    return -4
  }
  targets.workspace = Some(work)
  let mut temporary = fixed
  let reserved = Ref(fixed)
  let fund = peak => {
    if peak <= reserved.val {
      return true
    }
    if @resources.grow_capacity_reservation(drive.ledger, work, 0L, peak)
      is Err(_) {
      return false
    }
    reserved.val = peak
    true
  }
  let prepare = (body_bytes, body_nodes, body_depth) => {
    guard @local_host.installed_effect_canonical_body_capacity(
        body_bytes, body_nodes, body_depth,
      )
      is Some(body) &&
      @execution.checked_preparation_add_product(
        temporary,
        @execution.execution_capacity_execution_bytes(body),
        1L,
      )
      is Some(peak) &&
      @execution.checked_preparation_add_product(
        temporary,
        @execution.execution_capacity_retained_bytes(body),
        1L,
      )
      is Some(held) else {
      return false
    }
    if !fund(peak) {
      return false
    }
    temporary = held
    true
  }
  // The profile uses the same generation-zero record from the installed
  // Store. Its existing closed reader and decoder enforce an 8 KiB envelope.
  let retention = match
    sdk_selected_original(value, current, "retention.json", 8192) {
    Ok(bytes) => bytes
    Err(code) => return code
  }
  if !prepare(retention.length(), Int::min(512, retention.length()), 8) {
    return -4
  }
  guard @host.client_local_run_policy_retention_bodies(sdk.profile, retention)
    is Ok(retained) else {
    return -31
  }
  let policies = match
    @host.prepared_client_effect_publication_policy_bodies(
      prepared,
      bytes,
      nodes,
      depth,
      retain_catalog=false,
      before_body=Some(prepare),
      before_measure=Some((keys, depth) => {
        guard @encode.measuring_writer_construction_extent(keys, depth)
          is Some(codec) &&
          @execution.preparation_representation_cost({
            record_headers: codec.record_headers,
            reference_slots: codec.reference_slots,
            scalar_words: codec.scalar_words,
            owned_utf16_units: 0L,
            owned_wire_bytes: 0L,
          })
          is Some(work) &&
          @execution.checked_preparation_add_product(temporary, work, 1L)
          is Some(peak) else {
          return false
        }
        fund(peak)
      }),
    ) {
    Ok(policies) => policies
    Err(BudgetExceeded) => return -4
    Err(_) => return -31
  }
  let entries = retained.length().to_int64() +
    policies.length().to_int64() +
    @host.client_effect_combined_source_unit_dependency_body_count(unit) +
    2L * sources.to_int64() +
    8L * artifacts.length().to_int64() +
    statics.to_int64()
  if entries > 2147483647L - targets.members.length().to_int64() {
    return -4
  }
  match
    @local_host.reserve_installed_effect_dependency_group(
      managed,
      prepared,
      request,
      plan,
      entries.to_int(),
      targets.members.length(),
    ) {
    Ok(_) => ()
    Err(issue) => return mock_effect_work_issue(issue)
  }
  let kinds : Array[String] = Array(capacity=entries.to_int())
  let identities : Array[String?] = Array(capacity=entries.to_int())
  let wires : Array[String] = Array(capacity=entries.to_int())
  let append = (kind, identity, wire) => {
    kinds.push(kind)
    identities.push(identity)
    wires.push(wire)
  }
  for body in retained {
    append(
      @publication.captured_effect_dependency_body_kind(body),
      Some(@publication.captured_effect_dependency_body_cid(body)),
      @publication.captured_effect_dependency_body_json(body),
    )
  }
  for (kind, identity, wire) in policies {
    append(kind, Some(identity), wire)
  }
  for index in 0..<sources {
    guard @host.client_effect_combined_source_unit_relation_dependencies(
        unit, index,
      )
      is Some(((relation, rows), (schema, fields))) else {
      return -32
    }
    append("relation_value", Some(relation), rows)
    append("relation_schema", Some(schema), fields)
  }
  for
    (kind, identity, wire) in @host.client_effect_combined_source_unit_dependency_bodies(
      unit,
    ) {
    append(kind, Some(identity), wire)
  }
  let originals = Array(capacity=artifacts.length())
  let roots = Array(capacity=targets.members.length())
  for target in targets.members {
    roots.push(target.artifact)
  }
  for item in artifacts {
    // A sibling Result belongs to the complete public Manifest, but only
    // an original selected by a checked Effect member belongs in its closure.
    if !targets.members.any(target => {
        physical_equal(target.capture, item.capture) &&
        physical_equal(target.artifact, item.artifact)
      }) {
      continue
    }
    let artifact = item.artifact
    guard item.capture.original() is Some((exported, _, receipt)) &&
      @host.client_effect_dependency_result_definition(
        prepared, inputs, artifact, exported, receipt,
      )
      is Ok(definition) else {
      return -32
    }
    let relation = @execution.completed_relation_export_identity(receipt)
    let schema = @execution.completed_relation_export_schema_identity(receipt)
    let invocation = @host.client_effect_local_artifact_invocation(artifact)
    let retention = @host.client_effect_local_result_retention(artifact)
    originals.push(artifact)
    append(
      "relation_value",
      Some(@execution.logical_relation_cid(relation)),
      item.logical_body,
    )
    append(
      "relation_schema",
      Some(@execution.relation_schema_cid(schema)),
      @execution.relation_schema_wire(schema),
    )
    append(
      "local_result_definition",
      Some(@host.client_effect_local_result_definition_cid(definition)),
      @host.client_effect_local_result_definition_json(definition),
    )
    append(
      "local_computation",
      Some(@host.client_effect_local_invocation_cid(invocation)),
      @host.client_effect_local_invocation_json(invocation),
    )
    append(
      "result_artifact",
      Some(@host.client_effect_local_result_artifact_cid(artifact)),
      @host.client_effect_local_result_artifact_json(artifact),
    )
    append(
      "derivation_evidence",
      None,
      @host.client_effect_local_result_derivation_json(artifact),
    )
    append(
      "ordering_evidence",
      None,
      @host.client_effect_local_result_ordering_json(artifact),
    )
    append(
      "result_retention_policy",
      Some(@publication.publication_contract_identity(retention)),
      @publication.publication_contract_json(retention),
    )
  }
  let checked = match
    @local_host.prepare_installed_effect_dependency_bodies(
      managed, prepared, request, plan, inputs, stage, bytes, nodes, depth,
    ) {
    Ok(checked) => checked
    Err(issue) => return mock_effect_work_issue(issue)
  }
  for (kind, body) in checked {
    append(
      kind,
      Some(@checked.checked_local_dependency_body_cid(body)),
      @checked.checked_local_dependency_body_json(body),
    )
  }
  // The retained policy and retention bodies keep their original backing.
  // Their encoders and scanners have returned before the inventory enters.
  // Keep those bodies on the same reservation, with only their retained
  // allowance alongside the independently funded dependency constructor.
  if @resources.shrink_capacity_reservation(drive.ledger, work, 0L, temporary)
    is Err(_) {
    return -9
  }
  let inventory = match
    @local_host.prepare_installed_effect_dependency_inventory_retained(
      managed,
      prepared,
      request,
      plan,
      kinds,
      identities,
      wires,
      roots,
      bytes,
      nodes,
      depth,
      original_artifacts=originals,
    ) {
    Ok(inventory) => inventory
    Err(issue) => return mock_effect_work_issue(issue)
  }
  targets.dependencies = Some(inventory)
  0
}
