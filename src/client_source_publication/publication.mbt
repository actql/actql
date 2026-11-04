///|
/// Existing Host publication interpretation shared by Node and embedded Hosts.
/// Publication is trusted installation metadata, never a Client read grant.
pub(all) enum PublicationIssue {
  Publication
  Limit
  UnsupportedCarrier
  Declarations
  Alias(@source_frontend.AliasIssue)
}

///|
pub fn bind_published_query_context(
  environment : @program_check.CheckEnvironment,
  publication : String,
  declarations : String?,
) -> Result[@query_program.Context, PublicationIssue] {
  Ok(client_source_context(environment, publication, declarations)) catch {
    PublicationStop(issue) => Err(issue)
  }
}

///|
/// Interpret one original publication for the ordinary Source lowerer. The
/// returned installation metadata is not a capture, grant or currentness proof.
pub fn bind_published_query_parts(
  environment : @program_check.CheckEnvironment,
  publication : String,
  declarations : String?,
) -> Result[
  (
    @query_program.Context,
    Array[@query_program.TableWriteBinding],
    @query_program.UpdateTargetPublication?,
    @query_program.StoreTargetPublication?,
    @query_program.CommandTargetPublication?,
  ),
  PublicationIssue,
] {
  bind_published_query_parts_with_reader(
    environment, publication, declarations, source_publication_cursor,
  ).map(parts => {
    let (context, table, update, store, command, _) = parts
    (context, table, update, store, command)
  })
}

///|
/// Retain the original Catalog interpretation for the subsequent checker.
/// Its configured Environment and current compilation bounds still apply.
pub fn bind_published_query_parts_with_catalog(
  environment : @program_check.CheckEnvironment,
  publication : String,
  declarations : String?,
) -> Result[
  (
    @query_program.Context,
    Array[@query_program.TableWriteBinding],
    @query_program.UpdateTargetPublication?,
    @query_program.StoreTargetPublication?,
    @query_program.CommandTargetPublication?,
    @program_check.PreparedSourceCatalog,
  ),
  PublicationIssue,
] {
  bind_published_query_parts_with_reader(
    environment, publication, declarations, source_publication_cursor,
  )
}

///|
// Keep the one original read at this boundary. The private reader parameter
// permits a work counter around the actual parser without a public test port.
fn bind_published_query_parts_with_reader(
  environment : @program_check.CheckEnvironment,
  publication : String,
  declarations : String?,
  read : (String) -> @decode.Cursor raise PublicationStop,
  admission? : PublicationEnvironmentAdmission? = None,
) -> Result[
  (
    @query_program.Context,
    Array[@query_program.TableWriteBinding],
    @query_program.UpdateTargetPublication?,
    @query_program.StoreTargetPublication?,
    @query_program.CommandTargetPublication?,
    @program_check.PreparedSourceCatalog,
  ),
  PublicationIssue,
] {
  try {
    let root = read(publication)
    // Preserve the complete unused-section checks and their original order.
    source_publication_closed(root)
    let store = match
      published_store_targets_from_root(environment, root, admission~) {
      Ok(value) => value
      Err(issue) => raise PublicationStop(issue)
    }
    let command = match
      published_command_targets_from_root(environment, root, admission~) {
      Ok(value) => value
      Err(issue) => raise PublicationStop(issue)
    }
    let (context, catalog) = client_source_context_from_root(
      environment,
      root,
      declarations,
      admission~,
    )
    let table = table_write_publication_from_root(environment, root, admission~)
    let update = match
      published_update_targets_from_root(environment, root, admission~) {
      Ok(value) => value
      Err(_) => raise PublicationStop(Publication)
    }
    Ok((context, table, update, store, command, catalog))
  } catch {
    PublicationStop(issue) => Err(issue)
  }
}

///|
priv suberror PublicationStop {
  PublicationStop(PublicationIssue)
}

///|
/// Bounded original publication DATA for downstream Host projection. Successful
/// parsing is not environment/currentness validation, namespace custody or a grant.
pub fn read_publication_data(
  wire : String,
) -> Result[@decode.Cursor, PublicationIssue] {
  Ok(source_publication_cursor(wire)) catch {
    PublicationStop(issue) => Err(issue)
  }
}

///|
fn source_publication_cursor(
  wire : String,
) -> @decode.Cursor raise PublicationStop {
  let (source_limits, tree_limits) = source_publication_input_limits()
  let node = @source.parse_json_bytes(@utf8.encode(wire), source_limits).unwrap_or_else(() => {
      raise PublicationStop(Publication)
    },
  )
  @decode.admit(node, tree_limits).unwrap_or_else(() => {
    raise PublicationStop(Publication)
  })
}

///|
fn source_publication_field(
  value : @decode.Cursor,
  name : String,
) -> @decode.Cursor raise PublicationStop {
  let object = @decode.open_object(value).unwrap_or_else(() => {
    raise PublicationStop(Publication)
  })
  @decode.required(object, name).unwrap_or_else(() => {
    raise PublicationStop(Publication)
  })
}

///|
fn source_publication_text(
  value : @decode.Cursor,
  name : String,
) -> String raise PublicationStop {
  @decode.text(source_publication_field(value, name)).unwrap_or_else(() => {
    raise PublicationStop(Publication)
  })
}

///|
fn source_publication_members(
  environment : @check_environment.WireEnvironment,
  section : @check_environment.Section,
  key : String,
) -> Map[String, @decode.Cursor] raise PublicationStop {
  let count = @check_environment.member_count(environment, section)
  if count > 32768 {
    raise PublicationStop(Limit)
  }
  let entries : Map[String, @decode.Cursor] = Map([])
  for index in 0..<count {
    let body = @check_environment.member_body(
      @check_environment.member_at(environment, section, index).unwrap(),
    )
    let identity = source_publication_text(body, key)
    if entries.contains(identity) {
      raise PublicationStop(Publication)
    }
    entries[identity] = body
  }
  entries
}

///|
fn source_publication_contract(
  registry : Map[String, @decode.Cursor],
  reference : @decode.Cursor,
  kind : String,
) -> @decode.Cursor raise PublicationStop {
  let identity = source_publication_text(reference, "cid")
  guard registry.get(identity) is Some(envelope) else {
    raise PublicationStop(Publication)
  }
  if source_publication_text(envelope, "kind") != kind ||
    source_publication_text(envelope, "id") !=
    source_publication_text(reference, "id") ||
    source_publication_text(envelope, "version") !=
    source_publication_text(reference, "version") {
    raise PublicationStop(Publication)
  }
  source_publication_field(envelope, "body")
}

///|
fn client_source_context(
  environment : @program_check.CheckEnvironment,
  publication : String,
  declarations : String?,
) -> @query_program.Context raise PublicationStop {
  let root = source_publication_cursor(publication)
  source_publication_closed(root)
  match published_store_targets_from_root(environment, root) {
    Ok(_) => ()
    Err(issue) => raise PublicationStop(issue)
  }
  match published_command_targets_from_root(environment, root) {
    Ok(_) => ()
    Err(issue) => raise PublicationStop(issue)
  }
  client_source_context_from_root(environment, root, declarations).0
}

///|
fn source_publication_closed(
  root : @decode.Cursor,
) -> Unit raise PublicationStop {
  @decode.closed_object(root, [
    "environmentCid", "aliases", "tableWrites", "updateTargets", "storeTargets",
    "commandTargets",
  ]).unwrap_or_else(() => raise PublicationStop(Publication))
  |> ignore
}

///|
fn client_source_context_from_root(
  environment : @program_check.CheckEnvironment,
  root : @decode.Cursor,
  declarations : String?,
  admission? : PublicationEnvironmentAdmission? = None,
) -> (@query_program.Context, @program_check.PreparedSourceCatalog) raise PublicationStop {
  let environment_cid = @program_check.checking_environment_cid(environment)
  if source_publication_text(root, "environmentCid") != environment_cid {
    raise PublicationStop(Publication)
  }
  let aliases = @decode.elements(source_publication_field(root, "aliases")).unwrap_or_else(() => {
      raise PublicationStop(Publication)
    },
  )
  if aliases.length() > 1024 {
    raise PublicationStop(Limit)
  }
  let wire = @program_check.checking_environment_wire(environment)
  let views = source_publication_members(
    wire,
    @check_environment.SourceViews,
    "contract_cid",
  )
  let registry = source_publication_members(
    wire,
    @check_environment.ContractRegistry,
    "cid",
  )
  let published : Array[@source_frontend.PublishedAlias] = []
  let mut field_count = 0
  let prepared_catalog = match admission {
    Some(admission) => publication_admission_catalog(admission)
    None =>
      match
        @program_check.prepare_source_catalog(environment, {
          max_work: 10000000,
          max_bytes: 1048576,
          max_nodes: 65536,
          max_depth: 64,
        }) {
        Ok(value) => value
        Err(@program_check.EnvironmentFailure::BudgetExceeded) =>
          raise PublicationStop(Limit)
        Err(_) => raise PublicationStop(Publication)
      }
  }

  let input_schemas = []
  let mut schema_work = 1000000
  for index, entry in aliases {
    @decode.closed_object(entry, [
      "name", "sourceRef", "sourceViewContractCid", "schemaContractCid", "request",
    ]).unwrap_or_else(() => raise PublicationStop(Publication))
    |> ignore
    let name = @query_syntax.parse_relation_path(
      source_publication_text(entry, "name"),
      {
        max_source_bytes: 1024,
        max_tokens: 256,
        max_literal_bytes: 1024,
        max_work: 16384,
      },
    ).unwrap_or_else(() => raise PublicationStop(Publication))
    let source_ref = source_publication_text(entry, "sourceRef")
    guard views.get(source_publication_text(entry, "sourceViewContractCid"))
      is Some(view) else {
      raise PublicationStop(Publication)
    }
    let output = source_publication_field(view, "output")
    if source_publication_text(output, "carrier") != "relation" {
      raise PublicationStop(UnsupportedCarrier)
    }
    let schema_ref = source_publication_field(output, "schema")
    if source_publication_text(schema_ref, "cid") !=
      source_publication_text(entry, "schemaContractCid") {
      raise PublicationStop(Publication)
    }
    let schema = source_publication_contract(
      registry, schema_ref, "carrier_schema",
    )
    let policy = source_publication_contract(
      registry,
      source_publication_field(output, "data_policy"),
      "data_policy",
    )
    if source_publication_text(policy, "source_ref") != source_ref {
      raise PublicationStop(Publication)
    }
    let fields = @decode.object_field_names(
      source_publication_field(schema, "fields"),
    ).unwrap_or_else(() => raise PublicationStop(Publication))
    if fields.length() > 8192 || fields.length() > 65536 - field_count {
      raise PublicationStop(Limit)
    }
    field_count += fields.length()
    let (checked_schema, used_work) = @check_environment.read_relation_schema_fields(
      source_publication_field(schema, "fields"),
      65536,
      8192,
      64,
      schema_work,
    ).unwrap_or_else(() => raise PublicationStop(Publication))
    schema_work -= used_work
    input_schemas.push(("source_\{index}", checked_schema))
    let connector = source_publication_text(view, "connector_id")
    let view_id = source_publication_text(view, "view_id")
    let prefix = "connector://" + connector + "/"
    let suffix = "#" + view_id
    if !source_ref.has_prefix(prefix) ||
      !source_ref.has_suffix(suffix) ||
      source_ref.length() <= prefix.length() + suffix.length() {
      raise PublicationStop(Publication)
    }
    let resource = source_ref[prefix.length():source_ref.length() -
    suffix.length()].to_owned()
    let request = source_publication_request(entry)
    let input = source_publication_input(connector, resource, view_id, request)
    published.push({
      name,
      source_ref,
      environment_cid,
      input: @source_frontend.Relation({
        relation: name,
        name: "source_\{index}",
        source: @query_program.Captured(input),
        visible_fields: fields,
        graph_bindings: [],
      }),
    })
  }
  let parameter_declarations = client_source_declarations(declarations)
  match
    @source_frontend.bind_query_context(
      published,
      environment_cid,
      parameter_declarations~,
      input_schemas~,
      source_catalog=Some(
        @program_check.source_catalog_contracts(prepared_catalog),
      ),
      model_tasks=@program_check.checking_environment_model_tasks(environment),
      calendar_profile=@program_check.checking_environment_calendar_profile(
        environment,
      ),
    ) {
    Ok(value) => (value, prepared_catalog)
    Err(issue) => raise PublicationStop(Alias(issue))
  }
}

///|
fn client_source_declarations(
  declarations : String?,
) -> @parameter_binding.Declarations? raise PublicationStop {
  match declarations {
    None => None
    Some(body) => {
      let cursor = source_publication_cursor(body) catch {
        _ => raise PublicationStop(Declarations)
      }
      Some(
        read_source_parameter_declarations(cursor).unwrap_or_else(() => {
          raise PublicationStop(Declarations)
        }),
      )
    }
  }
}

///|
/// The existing publication JSON/index limits; these DATA do not grant backing.
/// Both native declarations and the textual publication reader use this owner.
pub fn source_publication_input_limits() -> (
  @source.ParseLimits,
  @decode.Limits,
) {
  (
    { max_input_bytes: 1048576, max_nodes: 16384, max_depth: 32, },
    {
      max_nodes: 16384,
      max_depth: 32,
      max_string_bytes: 65536,
      max_total_string_bytes: 1048576,
    },
  )
}

///|
fn read_source_parameter_declarations(
  cursor : @decode.Cursor,
) -> Result[@parameter_binding.Declarations, @parameter_binding.Issue] {
  @parameter_binding.read_declarations(Some(cursor), {
    max_parameters: 1024,
    max_nodes: 8192,
    max_depth: 64,
    max_text_bytes: 65536,
  })
}

///|
/// Admit detached native declaration DATA under the same existing limits and
/// label semantics. The Request retains this original index and typed result;
/// no document serialization or second declaration admission is required.
pub fn[T] admit_captured_query_declarations(
  input : T,
  reader : @source.JsonDataReader[T],
) -> Result[(@decode.Cursor, @parameter_binding.Declarations), PublicationIssue] {
  let (source_limits, tree_limits) = source_publication_input_limits()
  let source = match @source.admit_captured_json(input, reader, source_limits) {
    Err(_) => return Err(Declarations)
    Ok(value) => value
  }
  let indexed = match @decode.admit(source.node, tree_limits) {
    Err(_) => return Err(Declarations)
    Ok(value) => value
  }
  read_source_parameter_declarations(indexed)
  .map(value => (indexed, value))
  .map_err(_ => Declarations)
}

///|
// Installation request values are literal DATA. Only the existing direct-field
// reference forms are excluded; nested business keys are never templates.
fn source_publication_request(
  entry : @decode.Cursor,
) -> @decode.Cursor? raise PublicationStop {
  let object = @decode.open_object(entry).unwrap_or_else(() => {
    raise PublicationStop(Publication)
  })
  let request = @decode.lookup(object, "request")
  if request is Some(value) {
    guard @decode.object_length(value) is Some(count) else {
      raise PublicationStop(Publication)
    }
    for index in 0..<count {
      let (_, field) = @decode.field_at(value, index).unwrap()
      if @decode.object_length(field) == Some(1) {
        let (name, _) = @decode.field_at(field, 0).unwrap()
        if name == "$param" || name == "$binding" {
          raise PublicationStop(Publication)
        }
      }
    }
  }
  request
}

///|
// The existing admitted-source emitter preserves keys, order, nulls and values.
// No schema defaults, correlation keys, Parameters or policy are synthesized.
fn emit_source_publication_input(
  writer : @encode.Writer,
  connector : String,
  resource : String,
  view : String,
  request : @decode.Cursor?,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  for
    (key, value) in [
      ("connector", connector),
      ("resource", resource),
      ("view", view),
    ] {
    @encode.key(writer, key)
    @encode.string_value(writer, value)
  }
  if request is Some(value) {
    @encode.key(writer, "request")
    @stage_syntax.emit_admitted_source_value(value, writer)
  }
  @encode.end_object(writer)
}

///|
// Bound the exact original emission before allocating its text and index. The
// installing Host must fund that complete overlap before entering this constructor;
// writer limits are not a Resource reservation or physical backing receipt.
fn source_publication_input(
  connector : String,
  resource : String,
  view : String,
  request : @decode.Cursor?,
  max_bytes? : Int = 1048576,
) -> @decode.Cursor raise PublicationStop {
  try {
    // Preserve the old absent-request bounds, including its failure behavior.
    let (bytes, nodes, depth) = if request is None {
      (Int::min(max_bytes, 16384), 32, 8)
    } else {
      let measure = @encode.measuring_writer(max_bytes, 16384, 32)
      emit_source_publication_input(measure, connector, resource, view, request)
      @encode.finish_measurement_usage(measure)
    }
    let writer = @encode.writer(bytes, nodes, depth)
    emit_source_publication_input(writer, connector, resource, view, request)
    source_publication_cursor(@encode.finish(writer))
  } catch {
    _ => raise PublicationStop(Publication)
  }
}
