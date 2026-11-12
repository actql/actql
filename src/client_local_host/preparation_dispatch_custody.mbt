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
      name != "local_manifest" {
      guard effect_unit_sealed_geometry(name, geometry, identity)
        is Some(sealed_body) &&
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
  let mut failure : ClientInstalledManagedRunIssue? = None
  let result = @publication_host.client_effect_combined_source_unit_catalog_bodies(
    unit,
    max_bytes,
    max_nodes,
    max_depth,
    before_body=Some(fn(bytes, nodes, depth) {
      if failure is Some(_) {
        return false
      }
      guard effect_unit_publication_body(value, plan, request) is Ok(actual) &&
        physical_equal(actual, holder) else {
        failure = Some(Retired)
        return false
      }
      guard @encode.text_writer_construction_inventory(bytes, nodes, depth)
        is Some(writer) &&
        @resources.preparation_body_borrow_reserved_extents(holder)
        is Ok((r, e)) else {
        failure = Some(InsufficientCapacity)
        return false
      }
      let inventory : @execution.PreparationRepresentationUnits = {
        record_headers: writer.record_headers,
        reference_slots: writer.reference_slots,
        scalar_words: writer.scalar_words,
        owned_utf16_units: writer.owned_utf16_units,
        owned_wire_bytes: bytes.to_int64(),
      }
      let retained : @execution.PreparationRepresentationUnits = {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: bytes.to_int64(),
        owned_wire_bytes: 0L,
      }
      guard @execution.preparation_execution_capacity({
          retained,
          workspace: inventory,
          retained_nodes: 0L,
          workspace_nodes: 0L,
          retained_bytes: 0L,
          workspace_bytes: 0L,
        })
        is Some(capacity) &&
        @execution.checked_preparation_add_product(
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
        failure = Some(InsufficientCapacity)
        return false
      }
      match
        @resources.reserve_preparation_publication_phase(
          holder,
          plan,
          next_r,
          Int64::max(e, next_e),
        ) {
        Err(issue) => {
          failure = Some(Preparation(issue))
          return false
        }
        Ok(_) => ()
      }
      guard effect_unit_publication_body(value, plan, request) is Ok(actual) &&
        physical_equal(actual, holder) else {
        failure = Some(Retired)
        return false
      }
      true
    }),
  )
  if failure is Some(issue) {
    return Err(Run(issue))
  }
  guard effect_unit_publication_body(value, plan, request) is Ok(actual) &&
    physical_equal(actual, holder) else {
    return Err(Run(Retired))
  }
  result.map_err(issue => Evidence(issue))
}
