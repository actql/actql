///|
/// Original Source intake and its one parser/lowerer continuation. This is
/// immutable input provenance, not a Resource, Run or authorization Owner.
struct ClientSourceInput {
  mut original : ClientSourceInput?
  intent : ClientSubmittedIntent
  environment : @checked.CheckEnvironment
  mut publication : String
  mut source_document : String
  mut source_format : String
  selected : @source_frontend.Format
  mut declarations : String?
  mut supplied : @decode.Cursor?
  mut parameters : String?
  mut syntax_started : Bool
  mut query : @query_syntax.Query?
  mut lowering_started : Bool
  mut lowered : (
    @source_frontend.Lowered,
    @checked.PreparedSourceCatalog,
    @source_frontend.DiagnosticSource,
  )?
  mut prepared : ClientSourcePreparation?
}

///|
/// SAME existing bounded submitted Source admission. The caller must fund
/// Source/canonical/index/control coexistence before entering this constructor.
/// No query parser, Catalog lowerer or compiler is called here.
pub fn prepare_client_source_input(
  intent : ClientSubmittedIntent,
  environment : @checked.CheckEnvironment,
  publication : String,
) -> Result[ClientSourceInput, ClientSourcePreparationIssue] {
  try {
    let limits = client_standard_program_preparation_limits()
    let wire = client_submitted_intent_wire(intent)
    let source = source_result(
      @source.parse_json_bytes_preserving(
        @utf8.encode(wire),
        limits.checking.input.source,
      ).map_err(_ => Input),
    )
    let value = @canonical.from_source(
      source,
      limits.checking.input.source.max_nodes,
      limits.checking.input.source.max_depth,
      limits.checking.input.source.max_input_bytes,
      data_keys=true,
    ) catch {
      _ => return Err(Input)
    }
    guard @canonical.object_field(value, "kind")
      is Some(@canonical.String("aql")) &&
      @canonical.object_field(value, "input") is Some(input) &&
      @canonical.object_field(input, "text")
      is Some(@canonical.String(document)) &&
      @canonical.object_field(input, "format")
      is Some(@canonical.String(spelling)) &&
      @canonical.object_field_count(input) is Some(count) &&
      count ==
      (if @canonical.object_field(input, "parameterDeclarations") is Some(_) {
        3
      } else {
        2
      }) else {
      return Err(Input)
    }
    let selected = match @source_frontend.select_format(spelling) {
      Ok(Text) => @source_frontend.Text
      Ok(Sql) => @source_frontend.Sql
      _ => return Err(Input)
    }
    let declarations = match
      @canonical.object_field(input, "parameterDeclarations") {
      None => None
      Some(body) =>
        Some(
          @canonical.stringify_value(body, 1048576, 65536, 64) catch {
            _ => return Err(Input)
          },
        )
    }
    let cursor = source_result(
      @decode.admit(source, limits.checking.input.tree).map_err(_ => Input),
    )
    let root = source_result(@decode.open_object(cursor).map_err(_ => Input))
    // Explicit null is the original absence of supplied values, not a
    // missing/non-null required-field failure.
    let parameters = match @decode.lookup(root, "parameters") {
      Some(value) => value
      None => return Err(Input)
    }
    let supplied = if @decode.is_null(parameters) {
      None
    } else {
      Some(parameters)
    }
    let parameters_wire = match @canonical.object_field(value, "parameters") {
      Some(@canonical.Null) => None
      Some(body) =>
        Some(
          @canonical.stringify_value(body, 65536, 8192, 64) catch {
            _ => return Err(Input)
          },
        )
      None => return Err(Input)
    }
    let input : ClientSourceInput = {
      original: None,
      intent,
      environment,
      publication,
      source_document: document,
      source_format: spelling,
      selected,
      declarations,
      supplied,
      parameters: parameters_wire,
      syntax_started: false,
      query: None,
      lowering_started: false,
      lowered: None,
      prepared: None,
    }
    input.original = Some(input)
    Ok(input)
  } catch {
    ClientSourcePreparationStop(issue) => Err(issue)
  }
}

///|
fn client_source_input_original(input : ClientSourceInput) -> Bool {
  input.original is Some(original) && physical_equal(original, input)
}

///|
pub fn client_source_input_matches(
  input : ClientSourceInput,
  intent : ClientSubmittedIntent,
  environment : @checked.CheckEnvironment,
  publication : String,
) -> Bool {
  client_source_input_original(input) &&
  physical_equal(input.intent, intent) &&
  physical_equal(input.environment, environment) &&
  input.publication == publication
}

///|
/// Borrow only the admitted parser/Parameter inputs, never copied origin DATA.
pub fn client_source_input_parts(
  input : ClientSourceInput,
) -> Result[
  (String, @source_frontend.Format, String?, @decode.Cursor?),
  ClientSourcePreparationIssue,
] {
  if !client_source_input_original(input) {
    return Err(Input)
  }
  Ok(
    (input.source_document, input.selected, input.declarations, input.supplied),
  )
}

///|
/// One original selected parser with its existing declared work observation.
/// A failed or interrupted attempt is never silently parsed again.
pub fn observe_client_source_input_query(
  input : ClientSourceInput,
  source_path? : String = "<source>",
) -> Result[
  (Result[@query_syntax.Query, @source_frontend.Issue], Int64, Bool),
  ClientSourcePreparationIssue,
] {
  if !client_source_input_original(input) || input.syntax_started {
    return Err(Input)
  }
  input.syntax_started = true
  let observed = @source_frontend.observe_parse_query(
    input.source_document,
    input.selected,
    source_path~,
  )
  if observed.0 is Ok(query) {
    input.query = Some(query)
  }
  Ok(observed)
}

///|
/// The SAME original parser result enters the existing prepared publication
/// lowerer once. This is no raw Lowered assembler or completed-compiler API.
pub fn lower_client_source_input_query(
  input : ClientSourceInput,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  environment : @checked.CheckEnvironment,
  query : @query_syntax.Query,
  public_primary? : Bool = false,
) -> Result[
  (
    @source_frontend.Lowered,
    @checked.PreparedSourceCatalog,
    @source_frontend.DiagnosticSource,
  ),
  ClientSourcePreparationIssue,
] {
  if !client_source_input_original(input) || input.lowering_started {
    return Err(Input)
  }
  guard input.query is Some(original) &&
    physical_equal(original, query) &&
    physical_equal(input.environment, environment) &&
    @source_publication.prepared_published_query_environment_publication_matches(
      publication,
      environment,
      input.publication,
    ) else {
    return Err(Input)
  }
  input.lowering_started = true
  match
    @source_publication.lower_prepared_published_parsed_query(
      publication,
      environment,
      query,
      input.declarations,
      public_primary~,
    ) {
    Err(issue) => Err(source_prepared_publication_issue(issue))
    Ok(output) => {
      // Preserve the ordinary Source route's original refusals. A compiled
      // candidate alone does not supply installed target-capture originals.
      guard output.0.program is Some(parsed) else { return Err(Input) }
      for stage in @syntax.stages(parsed) {
        if !@syntax.effect_names(stage).is_empty() {
          if client_submitted_intent_requests_read_only(input.intent) {
            return Err(ReadOnly)
          }
          if output.0.command_selection is Some(_) ||
            output.0.keyed_effect_kind is Some(Upsert | Delete) ||
            output.0.insert_effect {
            return Err(TargetOriginalsUnavailable)
          }
        }
      }
      input.lowered = Some(output)
      Ok(output)
    }
  }
}

///|
// A Source compiler must consume this exact retained lowerer's Program,
// Parameter cursor and Environment. Equal data is not this original trace.
fn source_input_effect_candidate_matches(
  input : ClientSourceInput,
  candidate : @checked.EffectComputationCandidate,
) -> Bool {
  guard client_source_input_original(input) &&
    input.lowered is Some((lowered, _, _)) &&
    lowered.program is Some(parsed) &&
    physical_equal(
      parsed,
      @checked.checked_source_program(
        @checked.effect_computation_checked_program(candidate),
      ),
    ) &&
    physical_equal(
      @checked.checking_environment_wire(input.environment),
      @checked.effect_computation_environment(candidate),
    ) else {
    return false
  }
  match (input.supplied, @checked.effect_computation_supplied(candidate)) {
    (None, None) => true
    (Some(a), Some(b)) => physical_equal(a, b)
    _ => false
  }
}

///|
fn[T] same_client_source_optional(a : T?, b : T?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(a), Some(b)) => physical_equal(a, b)
    _ => false
  }
}

///|
/// The existing Effect compiler receives the original Source association
/// BEFORE constructing its body. No later record copy or mutation binds it.
pub fn observe_prepare_checked_client_source_effect_computation(
  input : ClientSourceInput,
  computation : @checked.EffectComputationCandidate,
  limits : ClientEffectComputationLimits,
  update_targets? : @update_targets.UpdateTargetPublication? = None,
  store_targets? : @update_targets.StoreTargetPublication? = None,
  command_targets? : @update_targets.CommandTargetPublication? = None,
) -> Result[
  (Result[PreparedClientEffectComputation, ClientEffectComputationIssue], Int64),
  ClientSourcePreparationIssue,
] {
  if !source_input_effect_candidate_matches(input, computation) {
    return Err(Input)
  }
  let lowered = input.lowered.unwrap().0
  if !same_client_source_optional(lowered.update_targets, update_targets) ||
    !same_client_source_optional(lowered.store_targets, store_targets) ||
    !same_client_source_optional(lowered.command_targets, command_targets) {
    return Err(Input)
  }
  if client_submitted_intent_requests_read_only(input.intent) {
    for stage in @syntax.stages(lowered.program.unwrap()) {
      if !@syntax.effect_names(stage).is_empty() {
        return Err(ReadOnly)
      }
    }
  }
  // Preserve the original command-target Environment check before lowering.
  if command_targets is Some(publication) &&
    !physical_equal(
      @checked.effect_computation_environment(computation),
      @update_targets.command_target_publication_environment(publication),
    ) {
    return Ok((Err(TargetSelection(ForeignEnvironment)), 0L))
  }
  let work = Ref(0L)
  let result = prepare_checked_client_effect_computation_owned(
    computation,
    limits,
    update_targets,
    store_targets,
    command_targets,
    lowering_work_out=Some(work),
    source_intent=Some(input.intent),
  )
  Ok((result, work.val))
}

///|
/// Select the SAME already compiled body; no parser, lowerer, checker, encoder
/// or replacement body is constructed at this original Source handoff.
pub fn retain_compiled_client_source_input(
  input : ClientSourceInput,
  preparation : ClientSourceProgramPreparation,
) -> Result[ClientSourcePreparation, ClientSourcePreparationIssue] {
  guard client_source_input_original(input) &&
    input.lowered is Some((lowered, _, _)) &&
    lowered.program is Some(parsed) else {
    return Err(Input)
  }
  match preparation {
    Pure(prepared) =>
      if !physical_equal(prepared.source, parsed) ||
        prepared.check_environment_cid !=
        @checked.checking_environment_cid(input.environment) {
        return Err(Input)
      }
    Effect(prepared) => {
      if !physical_equal(prepared.source, parsed) ||
        prepared.check_environment_cid !=
        @checked.checking_environment_cid(input.environment) ||
        !(prepared.source_intent is Some(intent) &&
        physical_equal(intent, input.intent)) {
        return Err(Input)
      }
      if !client_submitted_intent_effect_compatible(input.intent, prepared) {
        return Err(ReadOnly)
      }
    }
  }
  if input.prepared is Some(retained) {
    let same = match (retained.preparation, preparation) {
      (Pure(a), Pure(b)) => physical_equal(a, b)
      (Effect(a), Effect(b)) => physical_equal(a, b)
      _ => false
    }
    return if same { Ok(retained) } else { Err(Input) }
  }
  // Keep the existing Source profile check, not another semantic compiler.
  let checked = match preparation {
    Pure(prepared) => @strategy.graph_program(prepared_client_graph(prepared))
    Effect(prepared) =>
      @checked.effect_program_static_checked_computation(prepared.candidate)
  }
  let profile = check_client_source_array_profile(checked)
  if profile is Err(issue) {
    return Err(issue)
  }
  let retained : ClientSourcePreparation = {
    intent: input.intent,
    environment: input.environment,
    publication: input.publication,
    document: lowered.document,
    parameters: input.parameters,
    source_document: input.source_document,
    source_format: input.source_format,
    declarations: input.declarations,
    preparation,
  }
  input.prepared = Some(retained)
  Ok(retained)
}

///|
/// The existing Request caller cuts only this intake's aliases after its
/// registered constructors have unwound. This is not a Resource return,
/// borrower ACK, cancellation, physical stop or permission to free a parent.
pub fn clear_client_source_input(input : ClientSourceInput) -> Unit {
  input.original = None
  input.query = None
  input.lowered = None
  input.prepared = None
  input.supplied = None
  input.declarations = None
  input.parameters = None
  input.source_document = ""
  input.source_format = ""
  input.publication = ""
}

///|
/// Fixed typed entrance for the existing read-only Source choice. Consumers
/// cannot construct that sum outside its original owner.
pub fn retain_compiled_client_source_pure_input(
  input : ClientSourceInput,
  prepared : PreparedClientProgram,
) -> Result[ClientSourcePreparation, ClientSourcePreparationIssue] {
  retain_compiled_client_source_input(input, Pure(prepared))
}

///|
pub fn retain_compiled_client_source_effect_input(
  input : ClientSourceInput,
  prepared : PreparedClientEffectComputation,
) -> Result[ClientSourcePreparation, ClientSourcePreparationIssue] {
  retain_compiled_client_source_input(input, Effect(prepared))
}
