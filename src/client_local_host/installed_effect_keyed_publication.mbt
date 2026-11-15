///|
// The existing publication phase owns both Source-only codec entrances. Its
// actual emitter geometry is measured before allocation and grows this SAME
// body; an emission refusal cannot acquire another Source/Run or change Allow.
fn reserve_installed_effect_keyed_encoding(
  owner : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  identity : String,
  name : String,
  geometry : @encode.EncodingConstructionGeometry,
  complete_body? : Bool = false,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard effect_unit_publication_capacity(
      [(name, geometry)], identity, complete_body~,
    )
    is Some(capacity) else {
    return Err(InsufficientCapacity)
  }
  reserve_effect_unit_publication_capacity(owner, plan, request, capacity)
}

///|
/// The same installed issuer consumes both completed Source observations.
/// It never labels a Model contribution or a partial Source as a Unit result.
pub fn issue_installed_effect_keyed_invocation(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
  bound : @publication_host.PreparedClientEffectRun,
  captured : @strategy.CapturedEffectRunDAG,
  compilation : @publication_host.ClientEffectCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  lookup : @publication_host.ClientKeyedLookupInput,
  started : String,
  completed : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  ClientClosedValuesPreparationIssue,
] {
  let control = match
    begin_installed_effect_publication_invocation(
      owner,
      prepared,
      request,
      plan,
      bound,
      captured,
      compilation,
      admission,
      definition,
      plan.captures.length(),
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  defer {
    owner.effect_operation_opening = false
  }
  guard plan.model is None &&
    plan.keyed_original is Some(original) &&
    owner.ledger is Some(ledger) &&
    @publication_host.client_effect_keyed_lookup_matches_parent(
      lookup, original, ledger,
    ) else {
    return Err(ForeignOriginal)
  }
  guard @execution.preparation_representation_cost({
      record_headers: 4L,
      reference_slots: 10L,
      scalar_words: 2L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(callback_bytes) &&
    @execution.execution_capacity(callback_bytes, callback_bytes)
    is Some(callback_capacity) else {
    return Err(Installed(InsufficientCapacity))
  }
  match
    reserve_effect_unit_publication_capacity(
      owner, plan, request, callback_capacity,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Installed(issue))
  }
  let failed : Ref[ClientInstalledManagedRunIssue?] = Ref(None)
  let before = (name, geometry) => {
    match
      reserve_installed_effect_keyed_encoding(
        owner,
        plan,
        request,
        @publication.publication_contract_identity(definition),
        name,
        geometry,
        // Only these two invocation emitters measured their self-CID field.
        // Source Unit scope/local-invocation callbacks remain preimages.
        complete_body=true,
      ) {
      Ok(_) => true
      Err(issue) => {
        failed.val = Some(issue)
        false
      }
    }
  }
  let issued = @publication_host.issue_client_effect_keyed_captured_invocation(
    original,
    lookup,
    admission,
    definition,
    started,
    completed,
    max_bytes,
    max_nodes,
    max_depth,
    before_body=Some(before),
  )
  if failed.val is Some(issue) {
    return Err(Installed(issue))
  }
  match issued {
    Err(issue) => Err(PublicationInvocation(issue))
    Ok(value) =>
      finish_installed_effect_publication_invocation(
        owner, plan, bound, captured, control, definition, value,
      )
  }
}

///|
/// Retain cleanup/data provenance for the same checked Source Unit. The
/// existing actual Host/read binding remains independently checked by Core.
pub fn prepare_installed_effect_keyed_source_unit(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
  host : @strategy.CapturedEffectRunDAG,
  lookup : @publication_host.ClientKeyedLookupInput,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectKeyedSourceUnit,
  ClientEffectUnitPreparationIssue,
] {
  guard physical_equal(prepared, plan.prepared) &&
    plan.model is None &&
    plan.keyed_original is Some(original) &&
    owner.ledger is Some(ledger) &&
    @publication_host.client_effect_keyed_lookup_matches_parent(
      lookup, original, ledger,
    ) &&
    effect_unit_publication_body(owner, plan, request) is Ok(_) else {
    return Err(Run(ForeignOriginal))
  }
  guard @publication_host.client_effect_keyed_cached_dependency_bodies(
      original, lookup, retention,
    )
    is Some(bodies) &&
    @execution.preparation_array_representation(
      3L,
      (bodies.length().to_int64() + 2L) * 2L + 2L,
      true,
    )
    is Some(arrays) else {
    return Err(Run(ForeignOriginal))
  }
  let containers : @execution.PreparationRepresentationUnits = {
    record_headers: arrays.record_headers + bodies.length().to_int64() + 4L,
    reference_slots: arrays.reference_slots +
    (bodies.length().to_int64() + 2L) * 3L +
    6L,
    scalar_words: arrays.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let units = @publication_host.client_effect_keyed_source_unit_construction_inventory()
  guard @execution.compose_preparation_representation([
      units,
      containers,
      // Closed bridge controls: refusal Ref/Some/callback 4H8R2W;
      // nominal value, token, WeakMap and return carrier 4H13R2W;
      // mapping/filter closures and transient iteration 4H5R2W.
      // The two metadata tuples and all per-body records/arrays are above;
      // original wire strings stay borrowed, never cloned or re-admitted.
      {
        record_headers: 12L,
        reference_slots: 26L,
        scalar_words: 6L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(units) &&
    @execution.preparation_representation_cost(units) is Some(bytes) &&
    @execution.execution_capacity(bytes, bytes) is Some(capacity) else {
    return Err(Run(InsufficientCapacity))
  }
  match
    reserve_effect_unit_publication_capacity(owner, plan, request, capacity) {
    Err(issue) => return Err(Run(issue))
    Ok(_) => ()
  }
  let failed : Ref[ClientInstalledManagedRunIssue?] = Ref(None)
  let result = @publication_host.prepare_client_effect_keyed_source_unit(
    original,
    lookup,
    host,
    retention,
    max_bytes,
    max_nodes,
    max_depth,
    before_body=Some((name, geometry) => {
      match
        reserve_installed_effect_keyed_encoding(
          owner,
          plan,
          request,
          @publication.publication_contract_identity(retention),
          name,
          geometry,
        ) {
        Ok(_) => true
        Err(issue) => {
          failed.val = Some(issue)
          false
        }
      }
    }),
  )
  if failed.val is Some(issue) {
    return Err(Run(issue))
  }
  result.map_err(issue => Evidence(issue))
}

///|
/// Same original publication body backs the measured Artifact before issue.
pub fn prepare_installed_effect_keyed_result_artifact(
  owner : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  inputs : @strategy.CapturedEffectInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  source : @publication_host.ClientEffectKeyedSourceUnit,
  definition : @publication_host.ClientEffectLocalResultDefinition,
  receipt : @execution.CompletedRelationExportReceipt,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalResultArtifact,
  ClientEffectUnitPreparationIssue,
] {
  guard plan.model is None &&
    plan.keyed_original is Some(_) &&
    effect_unit_publication_body(owner, plan, request) is Ok(_) else {
    return Err(Run(ForeignOriginal))
  }
  let result = @strategy.captured_effect_local_result_export_result(exported)
  let name = @execution.managed_result_occurrence_name(
    @strategy.captured_any_result_borrow_occurrence(
      @strategy.captured_effect_local_result_borrow(result),
    ),
  )
  let shapes = match
    @publication_host.client_effect_keyed_source_unit_artifact_construction_geometry(
      plan.prepared,
      source,
      name,
      receipt,
      admission,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Err(issue) => return Err(Artifact(issue))
    Ok(value) => value
  }
  guard effect_unit_publication_capacity(
      shapes,
      @publication.publication_contract_identity(run_definition),
    )
    is Some(capacity) else {
    return Err(Run(InsufficientCapacity))
  }
  match
    reserve_effect_unit_publication_capacity(owner, plan, request, capacity) {
    Err(issue) => return Err(Run(issue))
    Ok(_) => ()
  }
  let issued = @publication_host.issue_keyed_source_client_effect_local_result_artifact(
    plan.prepared,
    inputs,
    exported,
    source,
    definition,
    receipt,
    admission,
    run_definition,
    invocation,
    observation,
    max_bytes,
    max_nodes,
    max_depth,
  )
  guard effect_unit_publication_body(owner, plan, request) is Ok(_) else {
    return Err(Run(Retired))
  }
  issued.map_err(issue => Artifact(issue))
}
