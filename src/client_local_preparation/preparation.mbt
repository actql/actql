///|
/// The physical adapter selects a format explicitly; there is no syntax
/// fallback or transport-specific parser. These are original input documents.
pub(all) enum LocalInput {
  Program(String)
  Aql(String)
}

///|
/// Query names come from trusted Host publication configuration, not from
/// aliases supplied by the Client. A context does not grant Source access.
struct LocalInputContext {
  environment_cid : String
  query : @query.Context
}

///|
/// One common-Checker result and its lowerer's durable Program document.
/// The original input remains separate from generated Program coordinates.
pub struct LocalPreparedInput {
  prepared : @host.PreparedClientProgram
  original : LocalInput
  document : String
}

///|
pub fn local_prepared_program(
  value : LocalPreparedInput,
) -> @host.PreparedClientProgram {
  value.prepared
}

///|
pub fn local_prepared_original(value : LocalPreparedInput) -> LocalInput {
  value.original
}

///|
pub fn local_prepared_document(value : LocalPreparedInput) -> String {
  value.document
}

///|
pub(all) enum LocalPreparationIssue {
  Publication(@publication.PublicationIssue)
  Context(@frontend.AliasIssue)
  ForeignEnvironment
  Frontend(@frontend.Issue)
  Preparation(@host.ClientProgramPreparationIssue)
  ArrayProfile(@frontend.ArrayProfileIssue)
  SubmittedInput(@host.ClientSubmittedIntentIssue)
  Declarations(@parameters.Issue)
}

///|
/// Bind the existing query lowerer to a checked publication generation. The
/// Host must first obtain each alias from the existing publication Owner.
pub fn bind_local_input_context(
  environment : @checked.CheckEnvironment,
  aliases : Array[@frontend.PublishedAlias],
  program_id : String,
  parameter_declarations? : @parameters.Declarations? = None,
  input_schemas? : Array[(String, @schema.Schema)] = [],
  source_catalog? : @environment.SourceRequestContracts? = None,
) -> Result[LocalInputContext, LocalPreparationIssue] {
  let environment_cid = @checked.checking_environment_cid(environment)
  match
    @frontend.bind_query_context(
      aliases,
      environment_cid,
      program_id~,
      parameter_declarations~,
      input_schemas~,
      source_catalog~,
    ) {
    Ok(query) => Ok({ environment_cid, query, })
    Err(issue) => Err(Context(issue))
  }
}

///|
/// Both formats enter the same Checker, checked DAG and Stage lowering Owner.
/// Query lowering's parsed Program is retained instead of reparsing generated
/// JSON, which would replace authored provenance. Preparation neither admits
/// a Run nor invokes a Source, Compute, Model or Effect adapter.
pub fn prepare_local_input(
  input : LocalInput,
  environment : @checked.CheckEnvironment,
  bindings : @decode.Cursor?,
  context : LocalInputContext?,
  limits : @host.ClientProgramPreparationLimits,
) -> Result[@host.PreparedClientProgram, LocalPreparationIssue] {
  prepare_local_input_material(input, environment, bindings, context, limits).map(
    local_prepared_program,
  )
}

///|
pub fn prepare_local_input_material(
  input : LocalInput,
  environment : @checked.CheckEnvironment,
  bindings : @decode.Cursor?,
  context : LocalInputContext?,
  limits : @host.ClientProgramPreparationLimits,
) -> Result[LocalPreparedInput, LocalPreparationIssue] {
  let format = match input {
    Program(_) => @frontend.Json
    Aql(_) => @frontend.Text
  }
  prepare_local_input_with_format(
    input, format, environment, bindings, context, limits,
  )
}

///|
/// One existing frontend/Checker path for direct and submitted input. Only the
/// original submitted format selects SQL; the adapter does not parse it.
fn prepare_local_input_with_format(
  input : LocalInput,
  format : @frontend.Format,
  environment : @checked.CheckEnvironment,
  bindings : @decode.Cursor?,
  context : LocalInputContext?,
  limits : @host.ClientProgramPreparationLimits,
) -> Result[LocalPreparedInput, LocalPreparationIssue] {
  if context is Some(context) &&
    context.environment_cid != @checked.checking_environment_cid(environment) {
    return Err(ForeignEnvironment)
  }
  let document = match input {
    Program(document) | Aql(document) => document
  }
  let lowered = match
    @frontend.lower(document, format, context.map(value => value.query)) {
    Ok(value) => value
    Err(issue) => return Err(Frontend(issue))
  }
  let prepared = match lowered.program {
    Some(program) =>
      @host.prepare_parsed_effect_free_client_program(
        program, environment, bindings, limits,
      )
    None =>
      @host.prepare_effect_free_client_program(
        lowered.document,
        lowered.format,
        environment,
        bindings,
        limits,
      )
  }
  let prepared = match prepared {
    Ok(value) => value
    Err(issue) => return Err(Preparation(issue))
  }
  match
    @frontend.check_array_profile(
      @strategy.graph_program(@host.prepared_client_graph(prepared)),
      max_work=1000000,
      max_slots=100000,
    ) {
    Ok(_) => Ok({ prepared, original: input, document: lowered.document, })
    Err(issue) => Err(ArrayProfile(issue))
  }
}

///|
/// Interpret the same installed publication used by the Node Host. The
/// publication Owner checks the exact environment, Source view, policy,
/// schema and alias. Success is name binding, not Run or read admission.
pub fn bind_local_published_input_context(
  environment : @checked.CheckEnvironment,
  publication : String,
  declarations : String?,
) -> Result[LocalInputContext, LocalPreparationIssue] {
  @publication.bind_published_query_context(
    environment, publication, declarations,
  )
  .map(query => {
    environment_cid: @checked.checking_environment_cid(environment),
    query,
  })
  .map_err(issue => Publication(issue))
}
