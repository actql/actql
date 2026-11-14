///|
/// Immutable installation metadata retained by its original Host. This is not
/// an Account decision, checked query, Run, attempt or Result. The Host owns its
/// publication generation, compiler namespace and closing/replacement fence.
pub struct PreparedPublishedQueryEnvironment {
  priv environment : @program_check.CheckEnvironment
  priv publication : String
  priv context : @query_program.Context
  priv table_writes : Array[@query_program.TableWriteBinding]
  priv update_targets : @query_program.UpdateTargetPublication?
  priv store_targets : @query_program.StoreTargetPublication?
  priv command_targets : @query_program.CommandTargetPublication?
  priv catalog : @program_check.PreparedSourceCatalog
  priv request_copy_nodes : Int
  priv request_copy_utf16 : Int64
}

///|
pub(all) enum PreparedPublicationIssue {
  Publication(PublicationIssue)
  ForeignEnvironment
  Frontend(@source_frontend.Issue)
}

///|
// Constructor-local sharing only. The sealed value retains no reader callback
// or mutable admission cache. Different publication sections consume the same
// existing Catalog and Mapping owners instead of readmitting them.
priv struct PublicationEnvironmentAdmission {
  environment : @program_check.CheckEnvironment
  read_catalog : (
    @program_check.CheckEnvironment,
    @program_check.SourceCatalogLimits,
    @check_environment.Limits?,
  ) -> Result[
    @program_check.PreparedSourceCatalog,
    @program_check.EnvironmentFailure,
  ]
  mut catalog : @program_check.PreparedSourceCatalog?
  mut catalog_contents_bounded : Bool
  mut mappings : @check_environment.MappingContractShapes?
}

///|
fn publication_admission_catalog(
  admission : PublicationEnvironmentAdmission,
) -> @program_check.PreparedSourceCatalog raise PublicationStop {
  if admission.catalog is Some(value) {
    return value
  }
  let value = match
    (admission.read_catalog)(
      admission.environment,
      {
        max_work: 10000000,
        max_bytes: 1048576,
        max_nodes: 65536,
        max_depth: 64,
      },
      if admission.catalog_contents_bounded {
        Some({
          max_bytes: 1048576,
          max_nodes: 16384,
          max_depth: 32,
          max_members: 32768,
        })
      } else {
        None
      },
    ) {
    Ok(value) => value
    Err(@program_check.EnvironmentFailure::BudgetExceeded) =>
      raise PublicationStop(Limit)
    Err(_) => raise PublicationStop(Publication)
  }
  admission.catalog = Some(value)
  value
}

///|
fn publication_admission_contents(
  admission : PublicationEnvironmentAdmission,
) -> @check_environment.CatalogContents raise PublicationStop {
  // Only registry/Catalog admission has the stricter Store/Command bound.
  // Source value and carrier admission retain their original 64-deep bound.
  // These sections precede Source binding; never reuse an unproved admission.
  if admission.catalog is None {
    admission.catalog_contents_bounded = true
  }
  if !admission.catalog_contents_bounded {
    raise PublicationStop(Publication)
  }
  let contents = @check_environment.reference_contents(
    @check_environment.data_policy_references(
      @check_environment.value_contract_policies(
        @check_environment.source_view_shape_values(
          @check_environment.read_mode_shapes(
            @check_environment.carrier_schema_modes(
              @check_environment.source_request_carriers(
                @program_check.source_catalog_contracts(
                  publication_admission_catalog(admission),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  )
  let registry = @check_environment.catalog_registry(contents)
  for
    (bytes, nodes, members) in [
      @check_environment.contract_registry_usage(registry),
      @check_environment.catalog_usage(contents),
    ] {
    if bytes > 1048576 || nodes > 16384 || members > 32768 {
      raise PublicationStop(Publication)
    }
  }
  contents
}

///|
fn publication_admission_mappings(
  admission : PublicationEnvironmentAdmission,
) -> @check_environment.MappingContractShapes raise PublicationStop {
  if admission.mappings is Some(value) {
    return value
  }
  let value = @check_environment.check_mapping_contract_shapes(
    @program_check.checking_environment_wire(admission.environment),
    { max_bytes: 1048576, max_nodes: 16384, max_depth: 32, max_members: 32768, },
    1000000,
  ).unwrap_or_else(() => raise PublicationStop(Publication))
  admission.mappings = Some(value)
  value
}

///|
/// Validate every public section before the Host installs this original.
/// Existing bounded readers supply all indices; no query or supplied Parameter
/// value is retained. Other Hosts may retain the same pure immutable facts.
pub fn prepare_published_query_environment(
  environment : @program_check.CheckEnvironment,
  publication : String,
) -> Result[PreparedPublishedQueryEnvironment, PublicationIssue] {
  prepare_published_query_environment_with_reader(
    environment, publication, source_publication_cursor,
  )
}

///|
fn prepare_published_query_environment_with_reader(
  environment : @program_check.CheckEnvironment,
  publication : String,
  read : (String) -> @decode.Cursor raise PublicationStop,
) -> Result[PreparedPublishedQueryEnvironment, PublicationIssue] {
  prepare_published_query_environment_with_readers(
    environment, publication, read, publication_read_catalog,
  )
}

///|
fn publication_read_catalog(
  environment : @program_check.CheckEnvironment,
  limits : @program_check.SourceCatalogLimits,
  contents_limits : @check_environment.Limits?,
) -> Result[
  @program_check.PreparedSourceCatalog,
  @program_check.EnvironmentFailure,
] {
  match contents_limits {
    None => @program_check.prepare_source_catalog(environment, limits)
    Some(contents_limits) =>
      @program_check.prepare_source_catalog_with_contents_limits(
        environment, limits, contents_limits,
      )
  }
}

///|
fn prepare_published_query_environment_with_readers(
  environment : @program_check.CheckEnvironment,
  publication : String,
  read : (String) -> @decode.Cursor raise PublicationStop,
  read_catalog : (
    @program_check.CheckEnvironment,
    @program_check.SourceCatalogLimits,
    @check_environment.Limits?,
  ) -> Result[
    @program_check.PreparedSourceCatalog,
    @program_check.EnvironmentFailure,
  ],
) -> Result[PreparedPublishedQueryEnvironment, PublicationIssue] {
  let admission = {
    environment,
    read_catalog,
    catalog: None,
    catalog_contents_bounded: false,
    mappings: None,
  }
  bind_published_query_parts_with_reader(
    environment,
    publication,
    None,
    read,
    admission=Some(admission),
  ).map(parts => {
    let (
      context,
      table_writes,
      update_targets,
      store_targets,
      command_targets,
      catalog,
    ) = parts
    let mut request_copy_nodes = 0
    let mut request_copy_utf16 = 0L
    for input in context.inputs {
      if input.source is @query_program.Captured(body) &&
        @decode.open_object(body) is Ok(object) &&
        @decode.lookup(object, "request") is Some(request) {
        let geometry = @decode.observe_subtree_construction_geometry(request)
        request_copy_nodes = Int::max(request_copy_nodes, geometry.nodes)
        request_copy_utf16 = Int64::max(
          request_copy_utf16,
          geometry.total_utf16,
        )
      }
    }
    {
      environment,
      publication,
      context,
      table_writes,
      update_targets,
      store_targets,
      command_targets,
      catalog,
      request_copy_nodes,
      request_copy_utf16,
    }
  })
}

///|
/// A cheap nominal join, never a CID-based replacement or current permission.
pub fn prepared_published_query_environment_matches(
  prepared : PreparedPublishedQueryEnvironment,
  environment : @program_check.CheckEnvironment,
) -> Bool {
  physical_equal(prepared.environment, environment)
}

///|
/// Join a retained publication as well as its nominal Environment. Equal CIDs
/// or an unrelated publication cannot substitute for this admitted original.
pub fn prepared_published_query_environment_publication_matches(
  prepared : PreparedPublishedQueryEnvironment,
  environment : @program_check.CheckEnvironment,
  publication : String,
) -> Bool {
  prepared_published_query_environment_matches(prepared, environment) &&
  prepared.publication == publication
}

///|
/// Formal JSON/YAML preparation uses this same Catalog without manufacturing
/// an alias or a second Environment owner. The Program checker still applies
/// the operation's current input, work and artifact bounds.
pub fn prepared_published_query_catalog(
  prepared : PreparedPublishedQueryEnvironment,
  environment : @program_check.CheckEnvironment,
) -> Result[@program_check.PreparedSourceCatalog, PreparedPublicationIssue] {
  if !prepared_published_query_environment_matches(prepared, environment) {
    return Err(ForeignEnvironment)
  }
  Ok(prepared.catalog)
}

///|
/// Lower a new query with the retained static installation. Only this query's
/// declarations are read here; its parse, names, types, plan and later checking
/// remain ordinary per-query work. No mutable Context or alias array escapes.
pub fn lower_prepared_published_query(
  prepared : PreparedPublishedQueryEnvironment,
  environment : @program_check.CheckEnvironment,
  document : String,
  format : @source_frontend.Format,
  declarations : String?,
  public_primary? : Bool = false,
) -> Result[
  (@source_frontend.Lowered, @program_check.PreparedSourceCatalog),
  PreparedPublicationIssue,
] {
  let context = match
    prepared_published_query_context(prepared, environment, declarations) {
    Err(issue) => return Err(issue)
    Ok(context) => context
  }
  @source_frontend.lower(
    document,
    format,
    Some(context),
    table_writes=prepared.table_writes,
    update_targets=prepared.update_targets,
    store_targets=prepared.store_targets,
    command_targets=prepared.command_targets,
    public_primary~,
  )
  .map(lowered => (lowered, prepared.catalog))
  .map_err(issue => Frontend(issue))
}

///|
fn prepared_published_query_context(
  prepared : PreparedPublishedQueryEnvironment,
  environment : @program_check.CheckEnvironment,
  declarations : String?,
) -> Result[@query_program.Context, PreparedPublicationIssue] {
  if !prepared_published_query_environment_matches(prepared, environment) {
    return Err(ForeignEnvironment)
  }
  let parameters = client_source_declarations(declarations) catch {
    PublicationStop(issue) => return Err(Publication(issue))
  }
  Ok({ ..prepared.context, parameter_declarations: parameters, })
}

///|
/// The same published installation and already parsed original query. Source
/// annotations survive this handoff; no query text, publication or Catalog is
/// reparsed to recover the original Program before its funded check.
pub fn lower_prepared_published_parsed_query(
  prepared : PreparedPublishedQueryEnvironment,
  environment : @program_check.CheckEnvironment,
  query : @query_syntax.Query,
  declarations : String?,
  public_primary? : Bool = false,
  calls_out? : Ref[Int64]? = None,
  limits? : @query_program.Limits? = None,
) -> Result[
  (
    @source_frontend.Lowered,
    @program_check.PreparedSourceCatalog,
    @source_frontend.DiagnosticSource,
  ),
  PreparedPublicationIssue,
] {
  let context = match
    prepared_published_query_context(prepared, environment, declarations) {
    Err(issue) => return Err(issue)
    Ok(context) => context
  }
  lower_prepared_query_in_context(
    prepared,
    query,
    context,
    public_primary,
    calls_out~,
    limits~,
  )
}

///|
/// JSON Effect preparation consumes these same original opaque targets and
/// Catalog. Their static admission is not target custody or execution approval.
pub fn prepared_published_effect_parts(
  prepared : PreparedPublishedQueryEnvironment,
  environment : @program_check.CheckEnvironment,
) -> Result[
  (
    @query_program.UpdateTargetPublication?,
    @query_program.StoreTargetPublication?,
    @query_program.CommandTargetPublication?,
    @program_check.PreparedSourceCatalog,
  ),
  PreparedPublicationIssue,
] {
  if !prepared_published_query_environment_matches(prepared, environment) {
    return Err(ForeignEnvironment)
  }
  Ok(
    (
      prepared.update_targets,
      prepared.store_targets,
      prepared.command_targets,
      prepared.catalog,
    ),
  )
}

///|
/// Project the already interpreted installation Catalog for a funded borrowed
/// preparation phase. Unlike the legacy projection, a tighter later admission
/// cannot silently construct a replacement Catalog. The Root still owns the
/// original installation lifetime and must keep it current until borrows end.
/// Retain this shallow wrapper once with that owner, rather than readmitting
/// the publication or creating another Catalog cache for each query.
pub fn prepared_published_required_catalog(
  prepared : PreparedPublishedQueryEnvironment,
  environment : @program_check.CheckEnvironment,
) -> Result[@program_check.PreparedSourceCatalog, PreparedPublicationIssue] {
  prepared_published_query_catalog(prepared, environment).map(
    @program_check.require_source_catalog_reuse,
  )
}

///|
/// Same admitted publication and original parsed Query, with declarations
/// already read from THIS Request's detached input. No parse or re-admission.
pub fn lower_prepared_query_with_declarations(
  prepared : PreparedPublishedQueryEnvironment,
  environment : @program_check.CheckEnvironment,
  query : @query_syntax.Query,
  declarations : @parameter_binding.Declarations?,
  public_primary? : Bool = false,
  calls_out? : Ref[Int64]? = None,
  limits? : @query_program.Limits? = None,
) -> Result[
  (
    @source_frontend.Lowered,
    @program_check.PreparedSourceCatalog,
    @source_frontend.DiagnosticSource,
  ),
  PreparedPublicationIssue,
] {
  if !prepared_published_query_environment_matches(prepared, environment) {
    return Err(ForeignEnvironment)
  }
  let context = { ..prepared.context, parameter_declarations: declarations, }
  lower_prepared_query_in_context(
    prepared,
    query,
    context,
    public_primary,
    calls_out~,
    limits~,
  )
}

///|
fn lower_prepared_query_in_context(
  prepared : PreparedPublishedQueryEnvironment,
  query : @query_syntax.Query,
  context : @query_program.Context,
  public_primary : Bool,
  calls_out? : Ref[Int64]? = None,
  limits? : @query_program.Limits? = None,
) -> Result[
  (
    @source_frontend.Lowered,
    @program_check.PreparedSourceCatalog,
    @source_frontend.DiagnosticSource,
  ),
  PreparedPublicationIssue,
] {
  if calls_out is Some(observed) {
    observed.val += 1L
  }
  @source_frontend.lower_parsed_with_source(
    query,
    Some(context),
    table_writes=prepared.table_writes,
    update_targets=prepared.update_targets,
    store_targets=prepared.store_targets,
    command_targets=prepared.command_targets,
    public_primary~,
    limits~,
  )
  .map(pair => (pair.0, prepared.catalog, pair.1))
  .map_err(issue => Frontend(issue))
}

///|
/// Largest retained literal Request geometry in this exact installation. These
/// independent maxima bound every alias occurrence, not Catalog bytes or work.
/// The caller must fund repeated copies before lowering through its original
/// Request owner. This projection supplies no capacity or execution authority.
pub fn prepared_published_request_copy_geometry(
  prepared : PreparedPublishedQueryEnvironment,
  environment : @program_check.CheckEnvironment,
) -> Result[(Int, Int64), PreparedPublicationIssue] {
  if !prepared_published_query_environment_matches(prepared, environment) {
    return Err(ForeignEnvironment)
  }
  Ok((prepared.request_copy_nodes, prepared.request_copy_utf16))
}
