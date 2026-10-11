///|
/// Trusted Host retention/configuration remains independent of Catalog,
/// Provider permission and approval. Dynamic Mapping and Result selection
/// comes from the original checked preparation and actual capture Owners.
pub(all) struct NativeResidentEffectReviewConfiguration {
  stage : Int
  effect_id : String
  api_version : String
  runtime_bundle_cid : String
  source_binding_cid : String
  store_authority_cid : String
  retention : @publication.PublicationContract
  retention_dependencies : Array[@publication.CapturedEffectDependencyBody]
  dependency_limits : @publication.CapturedEffectDependencyLimits
  preview_limits : @host.ClientCapturedEffectPreviewLimits
  export_limits : @host.PublicationOutputExportLimits
  dispatch_limits : NativeEffectDispatchKeyLimits
  body_limits : @catalog.WriteBodyLimits
  request_limits : @catalog.WriteRequestLimits
  observation_limits : @catalog.TargetObservationLimits
  max_rows : Int
  max_fields : Int
  // Whole evidence validation has its own caller-owned budget, independent
  // of the result-row export workspace.
  max_capture_workspace_entries : Int
  max_work : Int
  max_utf16_units : Int
}

///|
pub(all) enum NativeResidentEffectCatalogPolicyIssue {
  Unavailable
  InvalidLimits
  OriginalScopeMismatch
  OriginalMappingMismatch
  UnsupportedWrite
  Member(@host.ClientEffectMemberDescriptorIssue)
  RowFields(@environment.MappingRowFieldsIssue)
  Declaration(@catalog.DeclarationIssue)
  Mapping(@catalog.ExecutionMappingIssue)
  Projection(@catalog.WriteProjectionIssue)
  MappingUse(@catalog.DeclarationUseIssue)
  Store(@store.NativePublicationStoreIssue)
}

///|
/// Reuse the checked row-field and Connector Mapping Owners. Catalog supplies
/// physical metadata, never the expected authored Mapping identity. This first
/// adapter accepts the existing result-backed create capability only.
fn native_resident_create_mapping_from_shape(
  original : @environment.MappingContractShape,
  catalog : @catalog.CatalogObservation,
  binding : @catalog.CatalogObservationBinding,
  connector_id : String,
  resource : String,
  limits : @catalog.DeclarationLimits,
  max_fields : Int,
  max_work : Int,
) -> Result[
  (@catalog.ExecutionMapping, @catalog.WriteProjection),
  NativeResidentEffectCatalogPolicyIssue,
] {
  if max_fields < 1 ||
    max_work < 1 ||
    max_work > 1000000 ||
    limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 {
    return Err(InvalidLimits)
  }
  if !@catalog.catalog_observation_matches_binding(catalog, binding) {
    return Err(OriginalScopeMismatch)
  }
  let rows = match @environment.check_mapping_row_fields(original, max_work) {
    Ok(value) => value
    Err(issue) => return Err(RowFields(issue))
  }
  let count = @environment.mapping_row_fields_count(rows)
  if count > max_fields {
    return Err(InvalidLimits)
  }
  let sources : Array[@catalog.RowSource] = []
  for index in 0..<count {
    guard @environment.mapping_row_fields_source_at(rows, index)
      is Some((target, Some(source))) &&
      @environment.mapping_row_fields_literal_at(rows, index) is None &&
      @environment.mapping_row_fields_null_behavior_at(rows, index)
      is Some(null_behavior) else {
      return Err(UnsupportedWrite)
    }
    sources.push({ target, source, null_behavior, })
  }
  let implementation = match
    @catalog.salesforce_implementation(binding.connector_revision) {
    Some(value) => value
    None => return Err(UnsupportedWrite)
  }
  let declaration = match
    @catalog.generate_static_declaration(
      catalog,
      binding,
      implementation,
      connector_id,
      [resource],
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Declaration(issue))
  }
  let mapping = match
    @catalog.prepare_execution_mapping(
      declaration,
      resource,
      @catalog.CreateFromResult(sources),
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Mapping(issue))
  }
  if mapping.mapping_ref != @environment.mapping_shape_reference(original) ||
    mapping.mapping_cid != @environment.mapping_shape_cid(original) {
    return Err(OriginalMappingMismatch)
  }
  let projection = match
    @catalog.prepare_write_projection(
      catalog,
      binding,
      resource,
      @catalog.WriteCreate,
      @environment.mapping_row_fields_names(rows),
      max_fields,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Projection(issue))
  }
  match @catalog.check_execution_write(mapping, projection) {
    Ok(_) => Ok((mapping, projection))
    Err(issue) => Err(MappingUse(issue))
  }
}

///|
/// Select the authored Effect's Mapping from the original checked preparation.
/// A matching name in a new Catalog cannot replace that Owner or its CID.
pub fn prepare_native_resident_create_review_mapping(
  prepared : @host.PreparedClientEffectComputation,
  stage : Int,
  effect_id : String,
  catalog : @catalog.CatalogObservation,
  binding : @catalog.CatalogObservationBinding,
  connector_id : String,
  resource : String,
  limits : @catalog.DeclarationLimits,
  max_fields : Int,
  max_work : Int,
) -> Result[
  (@catalog.ExecutionMapping, @catalog.WriteProjection),
  NativeResidentEffectCatalogPolicyIssue,
] {
  let descriptor = match
    @host.client_effect_member_descriptor(prepared, stage, effect_id, max_work) {
    Ok(value) => value
    Err(issue) => return Err(Member(issue))
  }
  if descriptor.0 != 0 || descriptor.2 != "create" {
    return Err(UnsupportedWrite)
  }
  let shapes = @results.effect_mapping_rules_shapes(
    @results.effect_static_candidate_mapping_rules(
      @checked.effect_program_static_effects(
        @host.prepared_client_effect_computation_candidate(prepared),
      ),
    ),
  )
  let count = @results.effect_mapping_shape_count(shapes)
  if count > max_work {
    return Err(InvalidLimits)
  }
  for index in 0..<count {
    let entry = @results.effect_mapping_shape_at(shapes, index).unwrap()
    let selected = @results.effect_result_binding_header(
      @results.effect_mapping_shape_effect(entry),
    )
    if @syntax.effect_header_stage(selected) == stage &&
      @syntax.effect_header_id(selected) == effect_id {
      let original = @results.effect_mapping_shape_contract(entry)
      if @environment.mapping_shape_cid(original) != descriptor.5 {
        return Err(OriginalMappingMismatch)
      }
      return native_resident_create_mapping_from_shape(
        original, catalog, binding, connector_id, resource, limits, max_fields, max_work,
      )
    }
  }
  Err(Unavailable)
}

///|
/// Resolve the Result only from the actual captured inputs and checked member.
/// Multiple matches are refused rather than silently selecting a candidate.
fn native_resident_review_result_index(
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  max_work : Int,
) -> Int? {
  let count = @strategy.captured_effect_local_result_count(inputs)
  if max_work < 1 || count > max_work {
    return None
  }
  let mut selected = -1
  for index in 0..<count {
    if @strategy.captured_effect_local_result_matches_member(
        inputs, index, member_index,
      ) {
      if selected >= 0 {
        return None
      }
      selected = index
    }
  }
  if selected < 0 {
    None
  } else {
    Some(selected)
  }
}

///|
/// Consume the original live capture context only after authenticated Catalog
/// readback and current disclosure checks. No Source/Compute/Provider request
/// occurs here. Any rejection closes the context with its existing Owner and
/// returns that same pending handle if cleanup cannot complete.
pub fn prepare_native_resident_effect_review_from_catalog_custody(
  holder : @resident.ResidentRetainedConsumer,
  journal : @journal.Journal,
  context : @resident.ResidentEffectReviewInputContext,
  custody : @store.EffectCatalogCustody,
  original_binding : @catalog.CatalogObservationBinding,
  connector_id : String,
  resource : String,
  declaration_limits : @catalog.DeclarationLimits,
  configuration : NativeResidentEffectReviewConfiguration,
  current : () -> Bool,
) -> Result[
  NativeResidentEffectReview,
  NativeResidentEffectReviewPreparationFailure,
] {
  let reject = issue => {
    reject_resident_effect_review_context(context, Catalog(issue))
  }
  guard context.matches_holder(holder, journal) &&
    context.retention_matches(configuration.retention) &&
    current() &&
    context.facts(journal) is Some(facts) else {
    return reject(Unavailable)
  }
  let response = match custody.confirm() {
    Ok(value) => value
    Err(issue) => return reject(Store(issue))
  }
  let dispatch = @resident.resident_retained_consumer_request(holder)
  let execution = @remote.dispatch_request_execution_scope(dispatch)
  let catalog = response.catalog
  if !current() ||
    !context.matches_holder(holder, journal) ||
    !@catalog.catalog_observation_matches_binding(catalog, original_binding) ||
    !native_review_catalog_matches_original(
      catalog,
      execution[0],
      execution[1],
      @publication.publication_contract_identity(facts.producer.invocation),
      @remote.dispatch_request_identity(dispatch),
    ) {
    return reject(OriginalScopeMismatch)
  }
  let (mapping, projection) = match
    prepare_native_resident_create_review_mapping(
      facts.materials.prepared,
      configuration.stage,
      configuration.effect_id,
      catalog,
      original_binding,
      connector_id,
      resource,
      declaration_limits,
      configuration.max_fields,
      configuration.max_work,
    ) {
    Ok(value) => value
    Err(issue) => return reject(issue)
  }
  let result_index = match
    native_resident_review_result_index(facts.inputs, 0, configuration.max_work) {
    Some(value) => value
    None => return reject(Unavailable)
  }
  if !current() || !context.matches_holder(holder, journal) {
    return reject(Unavailable)
  }
  let policy : NativeResidentEffectReviewPolicy = {
    stage: configuration.stage,
    effect_id: configuration.effect_id,
    api_version: configuration.api_version,
    runtime_bundle_cid: configuration.runtime_bundle_cid,
    source_binding_cid: configuration.source_binding_cid,
    store_authority_cid: configuration.store_authority_cid,
    retention: configuration.retention,
    retention_dependencies: configuration.retention_dependencies,
    dependency_limits: configuration.dependency_limits,
    preview_limits: configuration.preview_limits,
    export_limits: configuration.export_limits,
    dispatch_limits: configuration.dispatch_limits,
    body_limits: configuration.body_limits,
    request_limits: configuration.request_limits,
    observation_limits: configuration.observation_limits,
    max_rows: configuration.max_rows,
    max_fields: configuration.max_fields,
    max_capture_workspace_entries: configuration.max_capture_workspace_entries,
    max_work: configuration.max_work,
    max_utf16_units: configuration.max_utf16_units,
    result_index,
    mapping,
    projection,
    catalog,
  }
  prepare_native_resident_effect_review_from_original_materials(
    holder, journal, context, policy,
  )
}
