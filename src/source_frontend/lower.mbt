///|
/// Alias for the existing bounded construction owner, retained only by a
/// diagnostic call. It grants no checking or execution authority.
pub type DiagnosticSource = @builder.Source

///|
/// The transport spelling is distinct from the structured Program parser's
/// JSON/YAML enum. Installed Hosts provide a checked source context for query
/// forms; the frontend itself never fetches Catalog facts or grants authority.
pub(all) enum Format {
  Json
  Yaml
  Text
  Sql
} derive(Eq, Debug)

///|
pub(all) struct Lowered {
  document : String
  format : @program.Format
  // Query forms retain their admitted Program with authored expression spans.
  // Checking the serialized document would replace them with generated JSON
  // coordinates. Machine input is admitted by the ordinary document checker.
  program : @program.Program?
  // Retain the trusted publication for the original checked Effect owner.
  update_targets : @query.UpdateTargetPublication?
  store_targets : @query.StoreTargetPublication?
  command_targets : @query.CommandTargetPublication?
  command_selection : @query.ShortCommandSelection?
  keyed_effect_kind : @syntax.KeyedEffectKind?
  insert_effect : Bool
}

///|
pub(all) enum Issue {
  InvalidFormat
  MissingQueryContext
  WrongQueryForm
  QuerySyntax(@syntax.Diagnostic)
  QueryLowering(@query.Issue)
  Encoding
}

///|
/// Original authored origin for an unresolved column expression. This projects
/// retained lowerer provenance without resolving names again. Column failures
/// without provenance and unresolved Source names have no location.
pub fn unknown_column_origin(issue : Issue) -> @origin.Origin? {
  match issue {
    QueryLowering(
      Expression({ issue: UnknownReference, origin: Some(origin), })
    ) if @origin.kind(origin) == @origin.Authored => Some(origin)
    _ => None
  }
}

///|
/// The Host first verifies that each input comes from this exact published
/// Check Environment and Source View generation. This in-process value only
/// carries the already-admitted input into the common query lowerer.
pub(all) enum AliasInput {
  Relation(@query.Input)
}

///|
pub(all) struct PublishedAlias {
  name : Array[@syntax.NamePart]
  source_ref : String
  environment_cid : String
  input : AliasInput
}

///|
pub(all) enum AliasIssue {
  EmptyName
  EmptySourceRef
  EnvironmentMismatch
  InputNameMismatch
  InvalidInputSchema
  ConflictingName
  TooManyAliases
  InvalidProgramId
}

///|
/// Construct one query-only Program context from a generation-bound Host
/// publication. Aliases name inputs; they do not confer read authority.
pub fn bind_query_context(
  aliases : Array[PublishedAlias],
  environment_cid : String,
  program_id? : String = "adhoc.query",
  parameter_declarations? : @parameters.Declarations? = None,
  input_schemas? : Array[(String, @schema.Schema)] = [],
  model_tasks? : @environment.ModelTasks? = None,
  calendar_profile? : @environment.SelectedCalendarProfile? = None,
  source_catalog? : @environment.SourceRequestContracts? = None,
) -> Result[@query.Context, AliasIssue] {
  if aliases.length() > 1024 {
    return Err(TooManyAliases)
  }
  if program_id.is_empty() {
    return Err(InvalidProgramId)
  }
  if model_tasks is Some(tasks) &&
    @environment.cid(@environment.model_tasks_environment(tasks)) !=
    environment_cid {
    return Err(EnvironmentMismatch)
  }
  if calendar_profile is Some(profile) &&
    @environment.cid(
      @environment.calendar_selection_environment(
        @environment.selected_calendar_selection(profile),
      ),
    ) !=
    environment_cid {
    return Err(EnvironmentMismatch)
  }
  if calendar_profile is Some(profile) &&
    model_tasks is Some(tasks) &&
    !physical_equal(
      @environment.calendar_selection_environment(
        @environment.selected_calendar_selection(profile),
      ),
      @environment.model_tasks_environment(tasks),
    ) {
    return Err(EnvironmentMismatch)
  }
  if source_catalog is Some(catalog) {
    let wire = @environment.contract_registry_environment(
      @environment.catalog_registry(
        @environment.reference_contents(
          @environment.data_policy_references(
            @environment.value_contract_policies(
              @environment.source_view_shape_values(
                @environment.read_mode_shapes(
                  @environment.carrier_schema_modes(
                    @environment.source_request_carriers(catalog),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    )
    if @environment.cid(wire) != environment_cid ||
      (
        model_tasks is Some(tasks) &&
        !physical_equal(@environment.model_tasks_environment(tasks), wire)
      ) {
      return Err(EnvironmentMismatch)
    }
    if calendar_profile is Some(profile) &&
      !physical_equal(
        @environment.calendar_selection_environment(
          @environment.selected_calendar_selection(profile),
        ),
        wire,
      ) {
      return Err(EnvironmentMismatch)
    }
  }
  let inputs : Array[@query.Input] = []
  let mut captured = false
  for index, entry in aliases {
    if entry.name.is_empty() || entry.name.any(part => part.value.is_empty()) {
      return Err(EmptyName)
    }
    if entry.source_ref.is_empty() {
      return Err(EmptySourceRef)
    }
    if entry.environment_cid != environment_cid {
      return Err(EnvironmentMismatch)
    }
    for previous in 0..<index {
      if @query.same_relation_path(entry.name, aliases[previous].name) {
        return Err(ConflictingName)
      }
    }
    match entry.input {
      Relation(input) => {
        if !@query.same_relation_path(entry.name, input.relation) {
          return Err(InputNameMismatch)
        }
        inputs.push(input)
        if input.source is @query.Captured(_) {
          captured = true
        }
      }
    }
  }
  for index, (name, schema) in input_schemas {
    if input_schemas[:index].any(previous => previous.0 == name) {
      return Err(InvalidInputSchema)
    }
    let matched = inputs.filter(input => input.name == name)
    guard matched.length() == 1 && matched[0].source is @query.Captured(_) else {
      return Err(InvalidInputSchema)
    }
    let fields = matched[0].visible_fields
    if @schema.field_count(schema) != fields.length() ||
      fields.any(field => @schema.lookup_reference(schema, field) is None) {
      return Err(InvalidInputSchema)
    }
  }
  Ok({
    program_id,
    stage_id: "main",
    stage_result: "rows",
    input_schemas,
    source_catalog,
    model_tasks,
    calendar_profile,
    result_name: "answer",
    captured_stage: if captured {
      Some("capture")
    } else {
      None
    },
    parameter_declarations,
    inputs,
  })
}

///|
pub fn select_format(name : String) -> Result[Format, Issue] {
  match name {
    "json" | "aql-json" => Ok(Json)
    "yaml" | "aql-yaml" => Ok(Yaml)
    "aql" | "aql-text" => Ok(Text)
    "sql" => Ok(Sql)
    _ => Err(InvalidFormat)
  }
}

///|
priv struct SourceLimits {
  construction : @builder.Limits
  max_stages : Int
}

///|
fn source_limits() -> SourceLimits {
  {
    construction: {
      source: { max_input_bytes: 65536, max_nodes: 8192, max_depth: 64, },
      tree: {
        max_nodes: 8192,
        max_depth: 64,
        max_string_bytes: 65536,
        max_total_string_bytes: 65536,
      },
      max_origin_entries: 16384,
      max_output_bytes: 65536,
    },
    max_stages: 32,
  }
}

///|
fn syntax_limits() -> @syntax.QueryLimits {
  let lexical : @syntax.LexicalLimits = {
    max_source_bytes: 65536,
    max_tokens: 8192,
    max_literal_bytes: 65536,
    max_work: 1000000,
  }
  {
    lexical,
    expression: { lexical, max_nodes: 8192, max_depth: 64, max_work: 1000000, },
    max_syntax_nodes: 8192,
    max_cte_count: 100,
    max_work: 1000000,
  }
}

///|
fn query_limits() -> @query.Limits {
  let caps = source_limits()
  {
    source: {
      source: caps.construction.source,
      tree: caps.construction.tree,
      max_origin_entries: caps.construction.max_origin_entries,
      max_output_bytes: caps.construction.max_output_bytes,
    },
    program: {
      source: caps.construction.source,
      tree: caps.construction.tree,
      max_stages: caps.max_stages,
    },
    max_expression_work: 1000000,
    max_join_output_rows: 1000000L,
    max_collection_items: 1000000L,
    max_collection_bytes: 65536L,
  }
}

///|
fn emit(
  program : @program.Program,
  update_targets : @query.UpdateTargetPublication?,
  store_targets : @query.StoreTargetPublication?,
  command_targets : @query.CommandTargetPublication?,
  command_selection : @query.ShortCommandSelection?,
  keyed_effect_kind : @syntax.KeyedEffectKind?,
  insert_effect : Bool,
) -> Result[Lowered, Issue] {
  let document = try {
    let writer = @encode.writer(65536, 8192, 64)
    @program.emit_program_source(program, writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Encoding)
  }
  Ok({
    document,
    format: @program.Json,
    program: Some(program),
    update_targets,
    store_targets,
    command_targets,
    command_selection,
    keyed_effect_kind,
    insert_effect,
  })
}

///|
/// Parse a selected query language without declarations or a Catalog context.
/// This is the same bounded syntax admission used by lowering; syntax success
/// alone says nothing about name resolution, bindings or Program checking.
pub fn parse_query(
  document : String,
  format : Format,
  source_path? : String = "<source>",
) -> Result[@syntax.Query, Issue] {
  observe_parse_query(document, format, source_path~).0
}

///|
/// Same original selected parser plus its completed budgeted prefix. The work
/// excludes lowerer/checker and input-document admission, and is not process
/// CPU or a function invocation counter. Incomplete admission stays explicit.
pub fn observe_parse_query(
  document : String,
  format : Format,
  source_path? : String = "<source>",
  calls_out? : Ref[Int64]? = None,
) -> (Result[@syntax.Query, Issue], Int64, Bool) {
  match format {
    Text | Sql => ()
    Json | Yaml => return (Err(InvalidFormat), 0L, true)
  }
  if calls_out is Some(observed) {
    observed.val += 1L
  }
  let (outcome, spent, complete) = @syntax.observe_selected_query_script(
    document,
    syntax_limits(),
    format == Sql,
    source_path~,
  )
  let result = match outcome {
    Ok(Some(script)) => Ok(@syntax.script_query(script))
    Ok(None) => Err(WrongQueryForm)
    Err(issue) => Err(QuerySyntax(issue))
  }
  (result, spent, complete)
}

///|
/// The unchanged selected lexical and grammar budgets, for one funded phase.
/// This projects policy DATA; it neither grants work nor selects a new limit.
pub fn query_syntax_work_limit() -> Int64 {
  let limits = syntax_limits()
  limits.lexical.max_work.to_int64() + limits.max_work.to_int64()
}

///|
/// Lower only the selected query language. No structural text fallback or
/// compatibility parser is available. The Host checks the resulting Program normally.
/// Retain existing construction annotations only through the diagnostic call.
/// The ordinary lower entry drops this owner before returning.
pub fn lower_with_source(
  document : String,
  format : Format,
  context : @query.Context?,
  source_path? : String = "<source>",
  table_writes? : Array[@query.TableWriteBinding] = [],
  update_targets? : @query.UpdateTargetPublication? = None,
  store_targets? : @query.StoreTargetPublication? = None,
  command_targets? : @query.CommandTargetPublication? = None,
  public_primary? : Bool = false,
) -> Result[(Lowered, @builder.Source?), Issue] {
  match format {
    Json =>
      Ok(
        (
          {
            document,
            format: @program.Json,
            program: None,
            update_targets: None,
            store_targets: None,
            command_targets: None,
            command_selection: None,
            keyed_effect_kind: None,
            insert_effect: false,
          },
          None,
        ),
      )
    Yaml =>
      Ok(
        (
          {
            document,
            format: @program.Yaml,
            program: None,
            update_targets: None,
            store_targets: None,
            command_targets: None,
            command_selection: None,
            keyed_effect_kind: None,
            insert_effect: false,
          },
          None,
        ),
      )
    Text | Sql => {
      let parsed = match parse_query(document, format, source_path~) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      lower_parsed_with_source(
        parsed,
        context,
        table_writes~,
        update_targets~,
        store_targets~,
        command_targets~,
        public_primary~,
      ).map(pair => (pair.0, Some(pair.1)))
    }
  }
}

///|
/// Continue the same admitted query syntax and authored source origins. This
/// entry performs no text parse and issues no checked Program/Run authority.
/// The original frontend compiler, target selection and emission limits remain
/// shared with the ordinary text entry.
pub fn lower_parsed_with_source(
  parsed : @syntax.Query,
  context : @query.Context?,
  table_writes? : Array[@query.TableWriteBinding] = [],
  update_targets? : @query.UpdateTargetPublication? = None,
  store_targets? : @query.StoreTargetPublication? = None,
  command_targets? : @query.CommandTargetPublication? = None,
  public_primary? : Bool = false,
) -> Result[(Lowered, @builder.Source), Issue] {
  guard context is Some(context) else { return Err(MissingQueryContext) }
  // Only a new public read-only Source with no authored RESULT selects
  // this configured primary. Structured Programs, explicit exports and
  // operator-specific Effect output laws keep their existing identities.
  let context = if public_primary && public_implicit_primary(parsed) {
    { ..context, result_name: "main", }
  } else {
    context
  }
  let (program, source, command_selection) = if @syntax.terminal_short_command_effect(
      parsed,
    )
    is Some(_) &&
    command_targets is Some(publication) {
    match
      @query.compile_short_command_with_source(
        parsed,
        context,
        query_limits(),
        publication,
        table_writes~,
        update_targets~,
        store_targets~,
      ) {
      Ok((program, source, selection)) => (program, source, Some(selection))
      Err(issue) => return Err(QueryLowering(issue))
    }
  } else {
    match
      @query.compile_with_source(
        parsed,
        context,
        query_limits(),
        table_writes~,
        update_targets~,
        store_targets~,
        command_targets~,
      ) {
      Ok((program, source)) => (program, source, None)
      Err(issue) => return Err(QueryLowering(issue))
    }
  }
  emit(
    program,
    update_targets,
    store_targets,
    command_targets,
    command_selection,
    @syntax.terminal_effect(parsed).map(clause => clause.kind),
    @syntax.terminal_insert_effect(parsed) is Some(_),
  ).map(lowered => (lowered, source))
}

///|
/// Ordinary lowering drops construction annotations before returning. The
/// diagnostic entry uses this same parser, lowerer and admitted Program.
pub fn lower(
  document : String,
  format : Format,
  context : @query.Context?,
  source_path? : String = "<source>",
  table_writes? : Array[@query.TableWriteBinding] = [],
  update_targets? : @query.UpdateTargetPublication? = None,
  store_targets? : @query.StoreTargetPublication? = None,
  command_targets? : @query.CommandTargetPublication? = None,
  public_primary? : Bool = false,
) -> Result[Lowered, Issue] {
  lower_with_source(
    document,
    format,
    context,
    source_path~,
    table_writes~,
    update_targets~,
    store_targets~,
    command_targets~,
    public_primary~,
  )
  .map(pair => pair.0)
  .map_err(issue => {
    match issue {
      QueryLowering(cause) => QueryLowering(@query.issue_without_source(cause))
      _ => issue
    }
  })
}

///|
fn public_implicit_primary(query : @syntax.Query) -> Bool {
  if @syntax.terminal_effect(query) is Some(_) ||
    @syntax.terminal_table_effect(query) is Some(_) ||
    @syntax.terminal_store_effect(query) is Some(_) ||
    @syntax.terminal_insert_effect(query) is Some(_) ||
    @syntax.terminal_short_command_effect(query) is Some(_) ||
    @syntax.terminal_command_effect_count(query) > 0 {
    return false
  }
  for index in 0..<@syntax.operation_count(query) {
    if @syntax.operation_at(query, index) is Some(RetainResult(_)) {
      return false
    }
  }
  for index in 0..<@syntax.final_operation_count(query) {
    if @syntax.final_operation_at(query, index) is Some(RetainResult(_)) {
      return false
    }
  }
  true
}
