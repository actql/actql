///|
/// The same authored source selects one existing checked computation Owner.
pub enum ClientSourceProgramPreparation {
  Pure(PreparedClientProgram)
  Effect(PreparedClientEffectComputation)
}

///|
pub struct ClientSourcePreparation {
  intent : ClientSubmittedIntent
  environment : @checked.CheckEnvironment
  publication : String
  document : String
  parameters : String?
  source_document : String
  source_format : String
  declarations : String?
  preparation : ClientSourceProgramPreparation
}

///|
pub(all) enum ClientSourcePreparationIssue {
  Input
  Publication(@source_publication.PublicationIssue)
  Frontend(@source_frontend.Issue)
  Syntax(@syntax.SyntaxError)
  Pure(ClientProgramPreparationIssue)
  Effect(ClientEffectComputationIssue)
  ArrayProfile(@source_frontend.ArrayProfileIssue)
  TargetOriginalsUnavailable
  ReadOnly
  Materials(ClientEffectRunMaterialsIssue)
}

///|
priv suberror ClientSourcePreparationStop {
  ClientSourcePreparationStop(ClientSourcePreparationIssue)
}

///|
fn[T] source_result(
  value : Result[T, ClientSourcePreparationIssue],
) -> T raise ClientSourcePreparationStop {
  match value {
    Ok(value) => value
    Err(issue) => raise ClientSourcePreparationStop(issue)
  }
}

///|
/// Installation publication supplies names, never acquisition or permission.
/// Read the original admitted envelope, including declarations and values;
/// retain the lowerer's parsed Program instead of parsing its emitted JSON.
pub fn prepare_client_source_computation(
  intent : ClientSubmittedIntent,
  environment : @checked.CheckEnvironment,
  publication : String,
) -> Result[ClientSourcePreparation, ClientSourcePreparationIssue] {
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
    let context = source_result(
      @source_publication.bind_published_query_context(
        environment, publication, declarations,
      ).map_err(issue => ClientSourcePreparationIssue::Publication(issue)),
    )
    let table_writes = source_result(
      @source_publication.published_table_writes(environment, publication).map_err(issue => {
        ClientSourcePreparationIssue::Publication(issue)
      }),
    )
    let update_targets = source_result(
      @source_publication.published_update_targets(environment, publication).map_err(issue => {
        ClientSourcePreparationIssue::Publication(issue)
      }),
    )
    let store_targets = source_result(
      @source_publication.published_store_targets(environment, publication).map_err(issue => {
        ClientSourcePreparationIssue::Publication(issue)
      }),
    )
    let command_targets = source_result(
      @source_publication.published_command_targets(environment, publication).map_err(issue => {
        ClientSourcePreparationIssue::Publication(issue)
      }),
    )
    let lowered = source_result(
      @source_frontend.lower(
        document,
        selected,
        Some(context),
        table_writes~,
        update_targets~,
        store_targets~,
        command_targets~,
      ).map_err(issue => ClientSourcePreparationIssue::Frontend(issue)),
    )
    guard lowered.program is Some(parsed) else { return Err(Input) }
    for stage in @syntax.stages(parsed) {
      if !@syntax.effect_names(stage).is_empty() {
        if client_submitted_intent_requests_read_only(intent) {
          return Err(ReadOnly)
        }
        // These forms still require the original installed target capture port.
        // Static publication alone cannot supply that physical correspondence.
        if lowered.command_selection is Some(_) ||
          lowered.keyed_effect_kind is Some(Upsert | Delete) ||
          lowered.insert_effect {
          return Err(TargetOriginalsUnavailable)
        }
        let prepared = source_result(
          prepare_parsed_client_effect_computation(
            parsed,
            environment,
            supplied,
            [],
            client_standard_effect_computation_limits(),
            update_targets=lowered.update_targets,
            store_targets=lowered.store_targets,
            command_targets=lowered.command_targets,
          ).map_err(issue => ClientSourcePreparationIssue::Effect(issue)),
        )
        let prepared = { ..prepared, source_intent: Some(intent), }
        source_result(
          @source_frontend.check_array_profile(
            @checked.effect_program_static_checked_computation(
              prepared_client_effect_computation_candidate(prepared),
            ),
            max_work=1000000,
            max_slots=100000,
          ).map_err(issue => ClientSourcePreparationIssue::ArrayProfile(issue)),
        )
        |> ignore
        let (original_program, original_parameters, _) = match client_effect_original_input_wires(prepared) {
          Ok(value) => value
          Err(issue) => return Err(Materials(issue))
        }
        return Ok({
          intent,
          environment,
          publication,
          document: original_program,
          parameters: original_parameters,
          source_document: document,
          source_format: spelling,
          declarations,
          preparation: Effect(prepared),
        })
      }
    }
    let prepared = source_result(
      prepare_parsed_effect_free_client_program(
        parsed, environment, supplied, limits,
      ).map_err(issue => ClientSourcePreparationIssue::Pure(issue)),
    )
    source_result(
      @source_frontend.check_array_profile(
        @strategy.graph_program(prepared_client_graph(prepared)),
        max_work=1000000,
        max_slots=100000,
      ).map_err(issue => ClientSourcePreparationIssue::ArrayProfile(issue)),
    )
    |> ignore
    Ok({
      intent,
      environment,
      publication,
      document: lowered.document,
      parameters: parameters_wire,
      source_document: document,
      source_format: spelling,
      declarations,
      preparation: Pure(prepared),
    })
  } catch {
    ClientSourcePreparationStop(issue) => Err(issue)
  }
}

///|
pub fn client_source_computation_preparation(
  value : ClientSourcePreparation,
) -> ClientSourceProgramPreparation {
  value.preparation
}

///|
pub fn client_source_computation_originals(
  value : ClientSourcePreparation,
) -> (String, String, String, String) {
  (
    client_submitted_intent_wire(value.intent),
    client_submitted_intent_cid(value.intent),
    @checked.checking_environment_cid(value.environment),
    value.publication,
  )
}

///|
/// Existing Run material codecs consume the retained lowerer's Program, not
/// a replacement for the separately retained original submitted source.
pub fn client_source_computation_material(
  value : ClientSourcePreparation,
) -> (String, String?) {
  (value.document, value.parameters)
}

///|
pub fn client_source_computation_source(
  value : ClientSourcePreparation,
) -> (String, String, String?) {
  (value.source_document, value.source_format, value.declarations)
}

///|
/// Reuse only the same admitted intent and nominal checked Environment.
pub fn client_source_computation_matches(
  value : ClientSourcePreparation,
  intent : ClientSubmittedIntent,
  environment : @checked.CheckEnvironment,
) -> Bool {
  physical_equal(value.intent, intent) &&
  physical_equal(value.environment, environment)
}

///|
pub fn client_source_computation_request(
  value : ClientSourcePreparation,
  authority_scope_cid : String,
  request_id : String,
) -> Result[ClientRequestIdentity, ClientRequestIdentityIssue] {
  let input = client_submitted_intent_cid(value.intent)
  match value.preparation {
    Pure(prepared) =>
      prepare_client_request_identity(
        prepared, authority_scope_cid, request_id, input,
      )
    Effect(prepared) =>
      prepare_client_effect_request_identity(
        prepared, authority_scope_cid, request_id, input,
      )
  }
}
