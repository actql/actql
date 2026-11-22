///|
/// Register the fixed ordinary Local dispatch's dependency on the original
/// preparation before opening its configured Host. The holder covers that
/// Host's modules, operation closures and transitive completed-output anchors
/// until physical/output cleanup AND private alias severance have completed.
/// It is not a new byte grant, a stop acknowledgement, or a generic low-level
/// execution lifetime. A legacy Run without a preparation owner returns None.
pub fn borrow_installed_managed_dispatch_preparation(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram]?,
  ClientInstalledManagedRunIssue,
] {
  match check_installed_managed_run(value, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard value.preparation_retirement is Some(custody) else { return Ok(None) }
  guard custody is PurePreparation(original) else {
    return Err(ForeignOriginal)
  }
  guard original.holder is Some(holder) &&
    @resources.preparation_body_borrow_value(holder) is Some(body) &&
    physical_equal(body, prepared) &&
    !@resources.preparation_body_retirement_started(holder) else {
    return Err(Retired)
  }
  // Sibling acquisition rechecks the same original Resource currentness and
  // claims its live borrower slot before callbacks; no adapter-owned count.
  match @resources.borrow_preparation_body_sibling(holder) {
    Ok(borrowed) => Ok(Some(borrowed))
    Err(@resources.PreparationCapacityIssue::Resource(issue)) =>
      Err(Ledger(issue))
    Err(_) => Err(CleanupPending)
  }
}

///|
/// Accounting correspondence for an already stopped fixed ordinary Host. The
/// captured DAG must use this exact Run Ledger, not an equal numeric profile.
/// A true result still requires the caller's actual stop/output-close proof.
pub fn installed_managed_preparation_usage_isolated(
  value : ClientInstalledManagedRun,
  request : @publication_host.ClientRequestIdentity,
  captured : @strategy.CapturedDAG,
) -> Bool {
  guard value.original is Some(original) &&
    physical_equal(original, value) &&
    physical_equal(value.request, request) &&
    value.ledger is Some(ledger) &&
    physical_equal(ledger, @strategy.captured_dag_ledger(captured)) &&
    value.preparation_retirement is Some(retirement) else {
    return false
  }
  match retirement {
    PurePreparation(original) =>
      @resources.prepared_run_usage_isolated(original.admission, ledger)
    EffectPlanPreparation(original) =>
      @resources.prepared_run_usage_isolated(original.admission, ledger)
  }
}

///|
/// The selected Effect dispatch and its operations borrow the same plan body
/// before opening the Host. No equal Program/request or copied plan can select
/// this holder; retirement fences new siblings on the existing capacity owner.
pub fn borrow_installed_effect_dispatch_preparation(
  value : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  @resources.PreparationBodyBorrow[ClientInstalledEffectManagedPlan]?,
  ClientInstalledManagedRunIssue,
] {
  guard value.preparation is Some(PlannedEffectManaged(_, original)) &&
    physical_equal(original, plan) &&
    physical_equal(value.request, request) else {
    return Err(ForeignOriginal)
  }
  match require_installed_managed_run(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard value.preparation_retirement is Some(custody) else { return Ok(None) }
  guard custody is EffectPlanPreparation(original) &&
    original.holder is Some(holder) &&
    @resources.preparation_body_borrow_value(holder) is Some(body) &&
    physical_equal(body, plan) &&
    !@resources.preparation_body_retirement_started(holder) else {
    return Err(Retired)
  }
  match @resources.borrow_preparation_body_sibling(holder) {
    Ok(borrowed) => Ok(Some(borrowed))
    Err(@resources.PreparationCapacityIssue::Resource(issue)) =>
      Err(Ledger(issue))
    Err(_) => Err(CleanupPending)
  }
}

///|
/// Original preparation and semantic constructor failures retain their typed
/// causes. This private installation boundary adds no SDK error or authority.
pub(all) enum ClientEffectUnitPreparationIssue {
  Run(ClientInstalledManagedRunIssue)
  Evidence(@publication_host.ClientEffectAcquiredEvidenceIssue)
  Pin(@strategy.RunIssue)
  Export(@strategy.CapturedEffectLocalResultExportIssue)
  Artifact(@publication_host.ClientEffectLocalResultArtifactIssue)
  Manifest(@publication_host.ClientEffectLocalManifestIssue)
  Retention(@publication.PublicationContractIssue)
}

///|
fn effect_unit_publication_body(
  value : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  @resources.PreparationBodyBorrow[ClientInstalledEffectManagedPlan],
  ClientInstalledManagedRunIssue,
] {
  guard value.original is Some(original) &&
    physical_equal(original, value) &&
    value.ledger is Some(_) &&
    !value.effect_operation_closing &&
    physical_equal(value.request, request) &&
    physical_equal(plan.request, request) &&
    value.preparation is Some(PlannedEffectManaged(admission, actual)) &&
    physical_equal(actual, plan) &&
    value.preparation_retirement is Some(EffectPlanPreparation(retirement)) &&
    physical_equal(retirement.admission, admission) &&
    retirement.holder is Some(holder) &&
    !@resources.preparation_body_retirement_started(holder) &&
    @resources.preparation_body_borrow_value(holder) is Some(body) &&
    physical_equal(body, plan) else {
    return Err(ForeignOriginal)
  }
  Ok(holder)
}

///|
/// Publication DATA from the same admitted Effect Compute plan. This neither
/// widens the installed policy nor grants execution, input access or a claim.
/// The original metadata quote already owns the Result row/index envelope.
pub fn installed_effect_managed_publication_limits(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
  max_payload_bytes : Int,
) -> @publication_host.PublicationOutputExportLimits? {
  guard check_installed_effect_managed_run(value, prepared, request) is Ok(_) &&
    physical_equal(plan.prepared, prepared) &&
    effect_unit_publication_body(value, plan, request) is Ok(_) else {
    return None
  }
  client_node_publication_limits_original(max_payload_bytes, plan.capacity_plan)
}

///|
// The owned contract registry selects the identity field. Measuring that
// single field uses the same String encoder; no second protocol field table,
// manufactured contract, wire or identity is introduced by this calculation.
fn effect_unit_sealed_geometry(
  name : String,
  body : @encode.EncodingConstructionGeometry,
  identity : String,
) -> @encode.EncodingConstructionGeometry? {
  guard @publication.publication_contract_identity_field_for_name(name)
    is Some(field) else {
    return None
  }
  let maximum = 12L +
    6L * (field.length().to_int64() + identity.length().to_int64())
  if maximum > 2147483647L {
    return None
  }
  let writer = @encode.construction_measuring_writer(maximum.to_int(), 4, 2) catch {
    _ => return None
  }
  let header = try {
    @encode.begin_object(writer)
    @encode.key(writer, field)
    @encode.string_value(writer, identity)
    @encode.end_object(writer)
    @encode.finish_construction_measurement(writer)
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      return None
    }
  }
  let bytes = body.bytes.to_int64() +
    header.bytes.to_int64() -
    (if body.nodes == 1 { 2L } else { 1L })
  let text = body.text_units.to_int64() + header.text_units.to_int64()
  if bytes > 2147483647L ||
    text > 2147483647L ||
    body.nodes == 2147483647 ||
    body.fields == 2147483647 ||
    body.strings > 2147483645 ||
    body.largest_object == 2147483647 {
    return None
  }
  Some({
    ..body,
    bytes: bytes.to_int(),
    nodes: body.nodes + 1,
    fields: body.fields + 1,
    largest_object: body.largest_object + 1,
    strings: body.strings + header.strings,
    text_units: text.to_int(),
  })
}

///|
// Reuse the compiler's existing Unicode JSON/parser/canonical layout and
// codec constructor inventories. Bodies remain simultaneously retained;
// active constructor scratch is a maximum. Fixed wrappers use Common overhead.
fn effect_unit_publication_capacity(
  bodies : Array[(String, @encode.EncodingConstructionGeometry)],
  identity : String,
  complete_body? : Bool = false,
) -> @execution.ExecutionCapacity? {
  let mut held : @execution.PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let mut scratch = held
  for (name, geometry) in bodies {
    guard @encode.text_writer_construction_inventory(
        geometry.bytes,
        geometry.nodes,
        geometry.depth,
      )
      is Some(writer) &&
      @encode.hash_writer_construction_inventory(geometry.nodes, geometry.depth)
      is Some(hash) else {
      return None
    }
    let text : @execution.PreparationRepresentationUnits = {
      record_headers: writer.record_headers,
      reference_slots: writer.reference_slots,
      scalar_words: writer.scalar_words,
      owned_utf16_units: writer.owned_utf16_units,
      owned_wire_bytes: geometry.bytes.to_int64(),
    }
    let hashing : @execution.PreparationRepresentationUnits = {
      record_headers: hash.record_headers,
      reference_slots: hash.reference_slots,
      scalar_words: hash.scalar_words,
      owned_utf16_units: hash.owned_utf16_units,
      owned_wire_bytes: hash.owned_wire_bytes,
    }
    let mut retained : @execution.PreparationRepresentationUnits = {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: geometry.bytes.to_int64(),
      owned_wire_bytes: 0L,
    }
    let mut temporary = @execution.compose_preparation_representation([
      text, hashing,
    ]).unwrap()
    if name != "request_values" &&
      name != "local_computation" &&
      name != "local_result_definition" &&
      name != "local_manifest" &&
      name != "result_import_observation" {
      // Keyed invocation's two closed emitters measure the complete body,
      // including its canonical-width self CID. Reuse that larger geometry
      // for BOTH preimage and final parse/codec overlap. It is not a contract
      // registry lookup (observation_set is RunEvidence), nor a second CID.
      let sealed_body = if complete_body {
        Some(geometry)
      } else {
        effect_unit_sealed_geometry(name, geometry, identity)
      }
      guard sealed_body is Some(sealed_body) &&
        program_artifact_parse_layout(
          @encode.construction_geometry_usage(geometry),
          structure=Some(geometry),
        )
        is Some(body) &&
        program_artifact_parse_layout(
          @encode.construction_geometry_usage(sealed_body),
          structure=Some(sealed_body),
        )
        is Some(complete) &&
        @encode.text_writer_construction_inventory(
          sealed_body.bytes,
          sealed_body.nodes,
          sealed_body.depth,
        )
        is Some(final_writer) else {
        return None
      }
      let wire : @execution.PreparationRepresentationUnits = {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: sealed_body.bytes.to_int64(),
        owned_wire_bytes: 0L,
      }
      let final_text : @execution.PreparationRepresentationUnits = {
        record_headers: final_writer.record_headers,
        reference_slots: final_writer.reference_slots,
        scalar_words: final_writer.scalar_words,
        owned_utf16_units: final_writer.owned_utf16_units,
        owned_wire_bytes: sealed_body.bytes.to_int64(),
      }
      guard @execution.compose_preparation_representation([complete.value, wire])
        is Some(value) &&
        @execution.compose_preparation_representation([
          body.value,
          body.temporary,
          complete.temporary,
          temporary,
          final_text,
        ])
        is Some(active) else {
        return None
      }
      retained = value
      temporary = active
    }
    guard @execution.compose_preparation_representation([held, retained])
      is Some(next) else {
      return None
    }
    held = next
    scratch = compilation_scratch_max(scratch, temporary)
  }
  @execution.preparation_execution_capacity({
    retained: held,
    workspace: scratch,
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
/// Construct one original upstream Source Unit only after growing the SAME
/// adopted Plan body reservation. No second Ledger/read/Root or cleanup owner
/// is issued. The caller retains its existing dispatch borrow and child duty;
/// a refused/reentrant grow leaves the actual old debit with that same owner.
pub fn prepare_installed_effect_model_source_unit(
  value : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  sources : @publication_host.ClientEffectSourceUnitInputs,
  unit : Int,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectCombinedSourceUnit,
  ClientEffectUnitPreparationIssue,
] {
  let holder = match effect_unit_publication_body(value, plan, request) {
    Ok(value) => value
    Err(issue) => return Err(Run(issue))
  }
  guard plan.model is Some(model) &&
    @publication_host.client_effect_source_unit_inputs_match(
      sources,
      plan.prepared,
      model.definition,
    ) else {
    return Err(Run(ForeignOriginal))
  }
  let (base_r, base_e) = match
    @resources.preparation_body_borrow_reserved_extents(holder) {
    Ok(value) => value
    Err(issue) => return Err(Run(Preparation(issue)))
  }
  let bodies = match
    @publication_host.client_effect_source_unit_construction_geometry(
      sources, unit, retention, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  guard effect_unit_publication_capacity(
      bodies,
      @publication.publication_contract_identity(model.definition),
    )
    is Some(required) &&
    @execution.checked_preparation_add_product(
      base_r,
      @execution.execution_capacity_retained_bytes(required),
      1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(
      base_r,
      @execution.execution_capacity_execution_bytes(required),
      1L,
    )
    is Some(e) else {
    return Err(Run(InsufficientCapacity))
  }
  match
    @resources.reserve_preparation_publication_phase(
      holder,
      plan,
      r,
      Int64::max(base_e, e),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Run(Preparation(issue)))
  }
  guard effect_unit_publication_body(value, plan, request) is Ok(actual) &&
    physical_equal(actual, holder) else {
    return Err(Run(Retired))
  }
  let prepared = @publication_host.prepare_client_effect_source_unit(
    sources, unit, retention, max_bytes, max_nodes, max_depth,
  )
  guard effect_unit_publication_body(value, plan, request) is Ok(actual) &&
    physical_equal(actual, holder) else {
    return Err(Run(Retired))
  }
  prepared.map_err(issue => Evidence(issue))
}

///|
// Direct Source publication measures existing emitters. A pending unordered
// key can precede its value's node debit.
fn installed_effect_direct_publication_control(
  entries : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @execution.ExecutionCapacity? {
  guard max_nodes > 0 &&
    max_nodes < 2147483647 &&
    installed_effect_dependency_fixed_capacity(entries, 1, max_depth)
    is Some(census) &&
    @encode.measuring_writer_construction_extent(0, max_depth) is Some(base) &&
    @encode.measuring_writer_construction_extent(max_nodes + 1, max_depth)
    is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: base.record_headers,
      reference_slots: base.reference_slots,
      scalar_words: base.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(base_bytes) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers,
      reference_slots: writer.reference_slots,
      scalar_words: writer.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(writer_bytes) else {
    return None
  }
  // The dependency census includes its exact zero-key measuring writer.
  // Replace that item with this writer's complete frame and key workspace.
  // The geometry and census backing stay in the original retained extent.
  let retained = @execution.execution_capacity_retained_bytes(census)
  let execution = @execution.execution_capacity_execution_bytes(census)
  guard retained >= base_bytes &&
    execution >= base_bytes &&
    @execution.checked_preparation_add_product(
      execution - base_bytes,
      writer_bytes,
      1L,
    )
    is Some(peak) else {
    return None
  }
  @execution.execution_capacity(retained - base_bytes, peak)
}

///|
// The measuring frame is synchronous and returns only its immutable quote.
// Preserve the execution floor that was already live before opening it;
// failed measurement or a failed current check keeps the original debit.
fn[T] measure_installed_effect_direct_publication(
  owner : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  capacity : @execution.ExecutionCapacity,
  measure : () -> Result[T, ClientEffectUnitPreparationIssue],
) -> Result[T, ClientEffectUnitPreparationIssue] {
  let holder = match effect_unit_publication_body(owner, plan, request) {
    Err(issue) => return Err(Run(issue))
    Ok(value) => value
  }
  let (_, base_execution) = match
    @resources.preparation_body_borrow_reserved_extents(holder) {
    Err(issue) => return Err(Run(Preparation(issue)))
    Ok(value) => value
  }
  match
    reserve_effect_unit_publication_capacity(owner, plan, request, capacity) {
    Err(issue) => return Err(Run(issue))
    Ok(_) => ()
  }
  let measured = match measure() {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let (retained, execution) = match
    @resources.preparation_body_borrow_reserved_extents(holder) {
    Err(issue) => return Err(Run(Preparation(issue)))
    Ok(value) => value
  }
  let floor = Int64::max(base_execution, retained)
  if execution > floor {
    match
      @resources.reconcile_preparation_publication_execution(
        holder, plan, floor,
      ) {
      Err(issue) => return Err(Run(Preparation(issue)))
      Ok(_) => ()
    }
  }
  guard effect_unit_publication_body(owner, plan, request) is Ok(current) &&
    physical_equal(current, holder) else {
    return Err(Run(Retired))
  }
  Ok(measured)
}

///|
/// Construct one combined Unit from this Run's original Source observation.
/// The admitted Plan retains both the variable bodies and their failed prefix.
pub fn prepare_installed_effect_combined_source_unit(
  owner : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  publication : @publication_host.ClientEffectDirectSourcesPublication,
  unit : Int,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectCombinedSourceUnit,
  ClientEffectUnitPreparationIssue,
] {
  guard !owner.effect_operation_opening &&
    plan.direct_occurrences is Some(occurrences) &&
    owner.publication_definition is Some(definition) &&
    owner.publication_invocation is Some(invocation) &&
    physical_equal(
      invocation,
      @publication_host.client_effect_direct_sources_publication_invocation(
        publication,
      ),
    ) &&
    effect_unit_publication_body(owner, plan, request) is Ok(_) else {
    return Err(Run(ForeignOriginal))
  }
  owner.effect_operation_opening = true
  defer {
    owner.effect_operation_opening = false
  }
  // At most five measured bodies per Source (request, retention, scope,
  // ordering and relation), plus the union and local computation. Pay for
  // the measuring frames and both census arrays before creating a writer.
  // Direct occurrences cover both Whole and Query Sources. The compact
  // Query capture array has no slots for Whole Sources.
  let entries = @publication_host.client_direct_acquisition_occurrence_count(
      occurrences,
    ).to_int64() *
    5L +
    2L
  guard entries <= 2147483647L &&
    installed_effect_direct_publication_control(
      entries.to_int(),
      max_nodes,
      max_depth,
    )
    is Some(control) else {
    return Err(Run(InsufficientCapacity))
  }
  let required = match
    measure_installed_effect_direct_publication(owner, plan, request, control, () => {
      let bodies = match
        @publication_host.client_effect_combined_source_unit_construction_geometry(
          publication, unit, retention, max_bytes, max_nodes, max_depth,
        ) {
        Err(issue) => return Err(Evidence(issue))
        Ok(value) => value
      }
      match
        effect_unit_publication_capacity(
          bodies,
          @publication.publication_contract_identity(definition),
        ) {
        None => Err(Run(InsufficientCapacity))
        Some(value) => Ok(value)
      }
    }) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  match
    reserve_effect_unit_publication_capacity(owner, plan, request, required) {
    Err(issue) => return Err(Run(issue))
    Ok(_) => ()
  }
  let combined = @publication_host.prepare_client_effect_combined_source_unit(
    publication, unit, retention, max_bytes, max_nodes, max_depth,
  )
  guard effect_unit_publication_body(owner, plan, request) is Ok(_) &&
    owner.publication_invocation is Some(current) &&
    physical_equal(current, invocation) else {
    return Err(Run(Retired))
  }
  combined.map_err(issue => Evidence(issue))
}

///|
/// Bind the actual completed producer to the original combined Source Unit.
/// The same Plan funds the Definition and three artifact bodies before issue.
pub fn prepare_installed_effect_combined_source_result_artifact(
  owner : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  publication : @publication_host.ClientEffectDirectSourcesPublication,
  inputs : @strategy.CapturedEffectInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  combined : @publication_host.ClientEffectCombinedSourceUnit,
  receipt : @execution.CompletedRelationExportReceipt,
  admission : @publication.RunPublicationAdmission,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  imported? : (
    @publication_host.ClientEffectImportedEvidence,
    @publication.PublicationContract,
  )? = None,
) -> Result[
  @publication_host.ClientEffectLocalResultArtifact,
  ClientEffectUnitPreparationIssue,
] {
  guard !owner.effect_operation_opening &&
    plan.direct_occurrences is Some(occurrences) &&
    owner.publication_definition is Some(definition) &&
    owner.publication_invocation is Some(invocation) &&
    owner.source_free_captured is Some(captured) &&
    @strategy.captured_effect_inputs_match_captured_run(inputs, captured) &&
    physical_equal(
      invocation,
      @publication_host.client_effect_direct_sources_publication_invocation(
        publication,
      ),
    ) &&
    effect_unit_publication_body(owner, plan, request) is Ok(_) else {
    return Err(Run(ForeignOriginal))
  }
  let observation = @publication_host.client_effect_direct_sources_publication_observation(
    publication,
  )
  if imported is Some((evidence, retention)) &&
    !@publication_host.client_effect_imported_matches_direct_source_unit(
      evidence, combined, retention, invocation, observation,
    ) {
    return Err(Run(ForeignOriginal))
  }
  if !@strategy.captured_effect_local_result_export_matches_receipt(
      inputs, exported, receipt,
    ) {
    return Err(Artifact(ForeignExport))
  }
  owner.effect_operation_opening = true
  defer {
    owner.effect_operation_opening = false
  }
  // Four geometry bodies plus the actual Unit's borrowed relation CID vector.
  let (_, _, parts) = @publication_host.client_effect_combined_source_unit_catalog_subject(
    combined,
  )
  guard parts >= 1 &&
    parts <=
    @publication_host.client_direct_acquisition_occurrence_count(occurrences) else {
    return Err(Run(ForeignOriginal))
  }
  guard parts <= 2147483643 &&
    installed_effect_direct_publication_control(parts + 4, max_nodes, max_depth)
    is Some(control) else {
    return Err(Run(InsufficientCapacity))
  }
  let result = @strategy.captured_effect_local_result_export_result(exported)
  let name = @execution.managed_result_occurrence_name(
    @strategy.captured_any_result_borrow_occurrence(
      @strategy.captured_effect_local_result_borrow(result),
    ),
  )
  let required = match
    measure_installed_effect_direct_publication(owner, plan, request, control, () => {
      let shapes = match
        (match imported {
          None =>
            @publication_host.client_effect_source_unit_artifact_construction_geometry(
              combined, name, receipt, admission, max_bytes, max_nodes, max_depth,
            )
          Some((evidence, retention)) =>
            @publication_host.client_effect_imported_result_artifact_construction_geometry(
              plan.prepared,
              inputs,
              evidence,
              name,
              receipt,
              retention,
              admission,
              definition,
              invocation,
              observation,
              max_bytes,
              max_nodes,
              max_depth,
            )
        }) {
        Err(issue) => return Err(Artifact(issue))
        Ok(value) => value
      }
      match
        effect_unit_publication_capacity(
          shapes,
          @publication.publication_contract_identity(definition),
        ) {
        Some(value) => Ok(value)
        None => Err(Run(InsufficientCapacity))
      }
    }) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  match
    reserve_effect_unit_publication_capacity(owner, plan, request, required) {
    Err(issue) => return Err(Run(issue))
    Ok(_) => ()
  }
  let local_definition = match
    @publication_host.issue_client_effect_local_result_definition(
      plan.prepared,
      @strategy.captured_effect_local_result_stage(result),
      name,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Err(_) => return Err(Artifact(ForeignDefinition))
    Ok(value) => value
  }
  let artifact = match imported {
    None =>
      @publication_host.issue_combined_source_client_effect_local_result_artifact(
        plan.prepared,
        inputs,
        exported,
        combined,
        local_definition,
        receipt,
        admission,
        definition,
        invocation,
        observation,
        max_bytes,
        max_nodes,
        max_depth,
      )
    Some((evidence, retention)) =>
      @publication_host.issue_imported_client_effect_local_result_artifact(
        plan.prepared,
        inputs,
        exported,
        evidence,
        local_definition,
        receipt,
        retention,
        admission,
        definition,
        invocation,
        observation,
        max_bytes,
        max_nodes,
        max_depth,
      )
  }
  guard effect_unit_publication_body(owner, plan, request) is Ok(_) &&
    owner.publication_invocation is Some(current) &&
    physical_equal(current, invocation) else {
    return Err(Run(Retired))
  }
  artifact.map_err(issue => Artifact(issue))
}

///|
/// The checked Catalog retains the original bodies. Only their newly encoded
/// wires and the active writer are owned here, before that existing emitter
/// allocates either. Each resize extends this SAME adopted Plan reservation.
pub fn prepare_installed_effect_model_source_unit_catalog(
  value : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  sources : @publication_host.ClientEffectSourceUnitInputs,
  unit : @publication_host.ClientEffectCombinedSourceUnit,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Array[(String, String, String)], ClientEffectUnitPreparationIssue] {
  if value.effect_operation_opening || value.effect_operation_closing {
    return Err(Run(AlreadyBound))
  }
  value.effect_operation_opening = true
  defer {
    value.effect_operation_opening = false
  }
  let holder = match effect_unit_publication_body(value, plan, request) {
    Ok(value) => value
    Err(issue) => return Err(Run(issue))
  }
  guard plan.model is Some(model) &&
    @publication_host.client_effect_source_unit_inputs_match(
      sources,
      plan.prepared,
      model.definition,
    ) &&
    @publication_host.client_effect_combined_source_unit_matches_inputs(
      unit, sources,
    ) else {
    return Err(Run(ForeignOriginal))
  }
  let (program, unit_index, parts) = @publication_host.client_effect_combined_source_unit_catalog_subject(
    unit,
  )
  match
    reserve_effect_unit_catalog_controls(value, plan, request, holder, parts) {
    Err(issue) => return Err(Run(issue))
    Ok(_) => ()
  }
  let bodies = []
  let seen : Map[String, Bool] = Map([])
  let mut remaining = max_bytes
  for part in 0..<parts {
    let references = match
      @publication_host.client_effect_combined_source_unit_catalog_dependencies_at(
        unit, part,
      ) {
      Err(issue) => return Err(Evidence(issue))
      Ok(value) => value
    }
    for (role, cid) in references {
      let key = role + "\u0000" + cid
      if seen.contains(key) {
        continue
      }
      let (body, bytes) = match
        prepare_effect_model_catalog_body(
          value, plan, request, program, unit_index, role, cid, remaining, max_nodes,
          max_depth,
        ) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      remaining -= bytes
      bodies.push(
        (
          role,
          @checked.checked_local_dependency_body_cid(body),
          @checked.checked_local_dependency_body_json(body),
        ),
      )
      seen[key] = true
    }
  }
  guard effect_unit_publication_body(value, plan, request) is Ok(actual) &&
    physical_equal(actual, holder) else {
    return Err(Run(Retired))
  }
  Ok(bodies)
}

///|
fn reserve_effect_unit_publication_capacity(
  value : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  capacity : @execution.ExecutionCapacity,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  let holder = match effect_unit_publication_body(value, plan, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let (r, e) = match
    @resources.preparation_body_borrow_reserved_extents(holder) {
    Ok(value) => value
    Err(issue) => return Err(Preparation(issue))
  }
  guard @execution.checked_preparation_add_product(
      r,
      @execution.execution_capacity_retained_bytes(capacity),
      1L,
    )
    is Some(next_r) &&
    @execution.checked_preparation_add_product(
      r,
      @execution.execution_capacity_execution_bytes(capacity),
      1L,
    )
    is Some(next_e) else {
    return Err(InsufficientCapacity)
  }
  match
    @resources.reserve_preparation_publication_phase(
      holder,
      plan,
      next_r,
      Int64::max(e, next_e),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Preparation(issue))
  }
  guard effect_unit_publication_body(value, plan, request) is Ok(actual) &&
    physical_equal(actual, holder) else {
    return Err(Retired)
  }
  Ok(())
}

///|
/// Retain the existing original Unit pins before opening its Model consumer.
/// The checked Program supplies the finite variable descriptor-array bound;
/// fixed per-Result/control records remain in Common preparation overhead.
pub fn pin_installed_effect_model_unit_results(
  value : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  run : @strategy.CapturedEffectRunDAG,
  unit : Int,
) -> Result[
  @strategy.CapturedEffectLocalUnitInputs,
  ClientEffectUnitPreparationIssue,
] {
  guard effect_unit_publication_body(value, plan, request) is Ok(_) &&
    plan.model is Some(_) &&
    value.source_free_captured is Some(original) &&
    physical_equal(original, @strategy.captured_effect_run_dag(run)) &&
    @strategy.captured_effect_run_matches_preparation(
      run,
      original,
      plan.configuration.graph,
    ) else {
    return Err(Run(ForeignOriginal))
  }
  let program = @strategy.graph_program(plan.graph)
  let stages = @checked.checked_stage_results(program)
  let count = @checked.unit_count(program)
  let mut results = 0L
  for stage in 0..<count {
    guard @stage_results.stage_at(stages, stage) is Some(selected) else {
      return Err(Run(ForeignOriginal))
    }
    results += @results.count(selected).to_int64()
  }
  guard @stage_results.stage_at(stages, unit) is Some(selected) else {
    return Err(Run(ForeignOriginal))
  }
  let selected_count = @results.count(selected)
  // The dependency selector, requested occurrence vector, pin/result arrays
  // and returned original inventory overlap. They contain aliases, not rows.
  guard @shape.collection_construction_extent({
      records: 0L,
      record_references: 0L,
      record_words: 0L,
      reference_arrays: 0L,
      reference_items: 4L * results + count.to_int64(),
      scalar_arrays: 0L,
      scalar_items: results + count.to_int64(),
      maps: 0L,
      map_entries: 3L * results + plan.operations.length().to_int64(),
    })
    is Some(inventory) else {
    return Err(Run(InsufficientCapacity))
  }
  let arrays : @execution.PreparationRepresentationUnits = {
    record_headers: inventory.record_headers,
    reference_slots: inventory.reference_slots,
    scalar_words: inventory.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard @execution.preparation_execution_capacity({
      retained: arrays,
      workspace: arrays,
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(capacity) else {
    return Err(Run(InsufficientCapacity))
  }
  match
    reserve_effect_unit_publication_capacity(value, plan, request, capacity) {
    Ok(_) => ()
    Err(issue) => return Err(Run(issue))
  }
  let inputs = match
    @strategy.pin_captured_effect_acquired_unit_results(
      run, unit, selected_count,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Pin(issue))
  }
  guard effect_unit_publication_body(value, plan, request) is Ok(_) &&
    value.source_free_captured is Some(current) &&
    physical_equal(current, original) &&
    @strategy.captured_effect_local_unit_inputs_match_run(inputs, run) else {
    @strategy.release_captured_effect_local_unit_inputs(inputs) |> ignore
    return Err(Run(Retired))
  }
  Ok(inputs)
}

///|
/// The exact selected ordinary export profile backs encoding/schema work;
/// actual producer rows and checked Named Result fields back the additional
/// projection/stable-order maps before their existing constructor allocates.
/// Cells and field text remain borrowed from the original completed producer.
fn installed_effect_model_unit_result_export_limits(
  value : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  run : @strategy.CapturedEffectRunDAG,
  inputs : @strategy.CapturedEffectLocalUnitInputs,
  index : Int,
  managed? : @execution.ManagedPublicationBridgeLimits? = None,
) -> Result[
  @publication_host.PublicationOutputExportLimits,
  ClientEffectUnitPreparationIssue,
] {
  guard effect_unit_publication_body(value, plan, request) is Ok(_) &&
    value.source_free_captured is Some(original) &&
    physical_equal(original, @strategy.captured_effect_run_dag(run)) &&
    @strategy.captured_effect_local_unit_inputs_match_run(inputs, run) &&
    @strategy.captured_effect_local_unit_result_at(inputs, index)
    is Some(result) else {
    return Err(Run(ForeignOriginal))
  }
  let borrow = @strategy.captured_effect_local_result_borrow(result)
  guard @strategy.captured_any_result_borrow_row_count(borrow) is Some(rows) &&
    client_node_publication_limits_original(
      plan.capacity_plan.exports.wire.max_bytes,
      plan.capacity_plan,
    )
    is Some(limits) &&
    @local.local_export_retention_capacity(plan.capacity_plan.exports)
    is Some(codec) else {
    return Err(Run(InsufficientCapacity))
  }
  if managed is Some(_) &&
    !@strategy.captured_any_result_borrow_requires_managed_export(borrow) {
    return Err(Export(ForeignOutput))
  }
  let port = @execution.managed_result_occurrence_port(
    @strategy.captured_any_result_borrow_occurrence(borrow),
  )
  let fields = @schema.field_count(@results.port_schema(port)).to_int64()
  let terms = @results.port_order_term_count(port).to_int64()
  // Row and stable-sort buffers include old/new growth overlap. Column/name
  // maps and checked order terms retain only original field-name aliases.
  guard @shape.collection_construction_extent({
      records: terms,
      record_references: 0L,
      record_words: 3L * terms,
      reference_arrays: 0L,
      reference_items: fields + terms,
      scalar_arrays: 0L,
      scalar_items: 2L * rows.to_int64() + fields,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(view) &&
    @execution.preparation_execution_capacity({
      retained: {
        record_headers: view.record_headers,
        reference_slots: view.reference_slots,
        scalar_words: view.scalar_words,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      workspace: {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: limits.schema.max_bytes.to_int64(),
        owned_wire_bytes: 0L,
      },
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: codec,
      workspace_bytes: codec,
    })
    is Some(capacity) else {
    return Err(Run(InsufficientCapacity))
  }
  let capacity = if managed is Some(geometry) {
    // The existing Local import allowance owns re-admitted rows, values and
    // decode scratch while the physical original and export view remain held.
    guard @local.local_import_retention_capacity({
        max_rows: geometry.max_rows,
        values: geometry.values,
        wire: {
          max_columns: geometry.entries,
          max_order_work: 0,
          max_bytes: geometry.row.max_bytes,
          max_nodes: geometry.row.max_nodes,
          max_depth: geometry.row.max_depth,
        },
        row: geometry.row,
        max_batch_bytes: Int::max(1, geometry.row.max_bytes),
      })
      is Some(importing) &&
      @execution.checked_preparation_add_product(
        @execution.execution_capacity_retained_bytes(capacity),
        importing,
        1L,
      )
      is Some(retained) &&
      @execution.checked_preparation_add_product(
        @execution.execution_capacity_execution_bytes(capacity),
        importing,
        1L,
      )
      is Some(executing) &&
      @execution.execution_capacity(retained, executing) is Some(capacity) else {
      return Err(Run(InsufficientCapacity))
    }
    capacity
  } else {
    capacity
  }
  match
    reserve_effect_unit_publication_capacity(value, plan, request, capacity) {
    Ok(_) => ()
    Err(issue) => return Err(Run(issue))
  }
  Ok(limits)
}

///|
/// Derive the import geometry from the SAME pinned managed completion. The
/// caller cannot submit an extent record or use another generation's rows.
pub fn[T] installed_effect_model_unit_managed_export_limits(
  value : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  run : @strategy.CapturedEffectRunDAG,
  inputs : @strategy.CapturedEffectLocalUnitInputs,
  index : Int,
  output : @execution.ManagedCompletedOutput[T],
  material : @execution.ManagedRetainedOutput[T],
) -> Result[
  @publication_host.PublicationOutputExportLimits,
  ClientEffectUnitPreparationIssue,
] {
  guard @strategy.captured_effect_local_unit_result_at(inputs, index)
    is Some(result) &&
    @strategy.captured_any_result_borrow_matches_managed(
      @strategy.captured_effect_local_result_borrow(result),
      output,
    ) &&
    @execution.managed_publication_bridge_import_geometry(
      output,
      material,
      plan.capacity_plan.exports.wire.max_columns,
      plan.capacity_plan.exports.wire.max_bytes,
    )
    is Some(geometry) else {
    return Err(Export(ForeignOutput))
  }
  installed_effect_model_unit_result_export_limits(
    value,
    plan,
    request,
    run,
    inputs,
    index,
    managed=Some(geometry),
  )
}

///|
pub fn prepare_installed_effect_model_unit_result_export(
  value : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  run : @strategy.CapturedEffectRunDAG,
  inputs : @strategy.CapturedEffectLocalUnitInputs,
  index : Int,
) -> Result[
  @strategy.CapturedEffectLocalResultExport,
  ClientEffectUnitPreparationIssue,
] {
  let limits = match
    installed_effect_model_unit_result_export_limits(
      value, plan, request, run, inputs, index,
    ) {
    Ok(limits) => limits
    Err(issue) => return Err(issue)
  }
  let export_result = @strategy.start_captured_effect_local_unit_result_export(
    inputs,
    index,
    {
      max_fields: limits.max_result_fields,
      max_mapping_work: limits.max_result_mapping_work,
      max_order_work: limits.max_result_order_work,
      max_workspace_entries: limits.max_result_workspace_entries,
    },
    limits.max_rows,
    limits.values,
    limits.payload_wire,
    limits.logical_wire,
    limits.schema,
    limits.max_batch_bytes,
  )
  let exported = match export_result {
    Ok(value) => value
    Err(issue) => return Err(Export(issue))
  }
  guard effect_unit_publication_body(value, plan, request) is Ok(_) &&
    @strategy.captured_effect_local_unit_result_export_retained(
      inputs, exported,
    ) else {
    @execution.cancel_completed_result_relation_export(
      @strategy.captured_effect_local_result_export_preparation(exported),
    )
    |> ignore
    return Err(Run(Retired))
  }
  Ok(exported)
}

///|
/// Issue only after growing this same adopted parent for the original Result
/// Definition and three semantic bodies. The existing issuer still validates
/// exact Unit/export/receipt/admission; numerical geometry cannot replace it.
pub fn prepare_installed_effect_model_source_unit_artifact(
  value : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  inputs : @strategy.CapturedEffectLocalUnitInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  combined : @publication_host.ClientEffectCombinedSourceUnit,
  receipt : @execution.CompletedRelationExportReceipt,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalResultArtifact,
  ClientEffectUnitPreparationIssue,
] {
  guard effect_unit_publication_body(value, plan, request) is Ok(_) &&
    plan.model is Some(model) &&
    physical_equal(model.definition, run_definition) &&
    @strategy.captured_effect_local_unit_result_export_retained(
      inputs, exported,
    ) else {
    return Err(Run(ForeignOriginal))
  }
  let result = @strategy.captured_effect_local_result_export_result(exported)
  let name = @execution.managed_result_occurrence_name(
    @strategy.captured_any_result_borrow_occurrence(
      @strategy.captured_effect_local_result_borrow(result),
    ),
  )
  let shapes = match
    @publication_host.client_effect_source_unit_artifact_construction_geometry(
      combined, name, receipt, admission, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Artifact(issue))
  }
  guard effect_unit_publication_capacity(
      shapes,
      @publication.publication_contract_identity(run_definition),
    )
    is Some(capacity) else {
    return Err(Run(InsufficientCapacity))
  }
  match
    reserve_effect_unit_publication_capacity(value, plan, request, capacity) {
    Ok(_) => ()
    Err(issue) => return Err(Run(issue))
  }
  let definition = match
    @publication_host.issue_client_effect_local_result_definition(
      plan.prepared,
      @strategy.captured_effect_local_result_stage(result),
      name,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(Artifact(ForeignDefinition))
  }
  let artifact = @publication_host.issue_preconsumer_client_effect_unit_result_artifact(
    plan.prepared,
    inputs,
    exported,
    combined,
    definition,
    receipt,
    admission,
    run_definition,
    max_bytes,
    max_nodes,
    max_depth,
  )
  guard effect_unit_publication_body(value, plan, request) is Ok(_) else {
    return Err(Run(Retired))
  }
  artifact.map_err(issue => Artifact(issue))
}

///|
pub fn prepare_installed_effect_model_unit_manifest(
  value : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  invocation : @publication_host.ClientEffectLocalInvocation,
  artifacts : Array[@publication_host.ClientEffectLocalResultArtifact],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalManifest,
  ClientEffectUnitPreparationIssue,
] {
  guard effect_unit_publication_body(value, plan, request) is Ok(_) else {
    return Err(Run(ForeignOriginal))
  }
  let geometry = match
    @publication_host.client_effect_local_manifest_construction_geometry(
      invocation, artifacts, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Manifest(issue))
  }
  guard effect_unit_publication_capacity(
      [("local_manifest", geometry)],
      @publication_host.client_effect_local_invocation_cid(invocation),
    )
    is Some(capacity) else {
    return Err(Run(InsufficientCapacity))
  }
  match
    reserve_effect_unit_publication_capacity(value, plan, request, capacity) {
    Ok(_) => ()
    Err(issue) => return Err(Run(issue))
  }
  let manifest = @publication_host.issue_client_effect_local_manifest(
    plan.prepared,
    invocation,
    artifacts,
    max_bytes,
    max_nodes,
    max_depth,
  )
  guard effect_unit_publication_body(value, plan, request) is Ok(_) else {
    return Err(Run(Retired))
  }
  manifest.map_err(issue => Manifest(issue))
}

///|
/// Borrow the actual parent for the existing selected Model constructor. This
/// immutable correspondence runs no external current callback and issues no
/// new capacity token, Model/Run owner or permission.
pub fn installed_effect_model_unit_parent(
  value : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : @publication_host.ClientInferPlanGraph,
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  guard effect_unit_publication_body(value, plan, request) is Ok(_) &&
    value.ledger is Some(ledger) &&
    plan.model is Some(model) &&
    physical_equal(model.compiled, compiled) &&
    physical_equal(model.definition, definition) &&
    prepared_installed_effect_model_sequence(plan, graph) is Ok(_) else {
    return Err(ForeignOriginal)
  }
  Ok(ledger)
}

///|
/// The original emitter supplies geometry before its body allocation. Fold
/// the existing constructor layout and extend the same Plan body reservation;
/// no byte DATA from JavaScript or new reservation owner is accepted here.
pub fn reserve_installed_effect_model_unit_body(
  value : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  kind : String,
  shape : @encode.EncodingConstructionGeometry,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard plan.model is Some(model) &&
    effect_unit_publication_capacity(
      [(kind, shape)],
      @publication.publication_contract_identity(model.definition),
    )
    is Some(capacity) else {
    return Err(InsufficientCapacity)
  }
  reserve_effect_unit_publication_capacity(value, plan, request, capacity)
}
