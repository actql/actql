///|
/// Host-local source preparation. Publication input is installation metadata,
/// not Client-supplied schema, an acquisition receipt or a read grant.
pub(all) enum ClientSourcePreparationIssue {
  Publication
  Limit
  UnsupportedCarrier
  Declarations
  Alias(@source_frontend.AliasIssue)
  Frontend(@source_frontend.Issue)
}

///|
fn client_source_preparation_issue_code(
  issue : ClientSourcePreparationIssue,
) -> String {
  match issue {
    Publication | Alias(_) => "source_rejected"
    Limit => "source_limit"
    UnsupportedCarrier => "source_unsupported"
    Declarations => "source_declarations"
    Frontend(issue) =>
      match issue {
        MissingQueryContext => "source_missing_input"
        Encoding => "source_encoding"
        QueryLowering(issue) =>
          match issue {
            UnsupportedProjection
            | UnsupportedGrouping
            | UnsupportedAggregate
            | UnsupportedHaving
            | UnsupportedOrdering
            | UnsupportedAnalytic
            | UnsupportedSet
            | UnsupportedJoin
            | UnsupportedCte
            | UnsupportedGraph => "source_unsupported"
            _ => "source_rejected"
          }
        QuerySyntax({ issue: Limit(_), .. }) => "source_limit"
        _ => "source_invalid_input"
      }
  }
}

///|
priv suberror ClientSourceStop {
  ClientSourceStop(ClientSourcePreparationIssue)
}

///|
fn source_publication_cursor(
  wire : String,
) -> @decode.Cursor raise ClientSourceStop {
  let node = @source.parse_json_bytes(@utf8.encode(wire), {
    max_input_bytes: 1048576,
    max_nodes: 16384,
    max_depth: 32,
  }).unwrap_or_else(() => raise ClientSourceStop(Publication))
  @decode.admit(node, {
    max_nodes: 16384,
    max_depth: 32,
    max_string_bytes: 65536,
    max_total_string_bytes: 1048576,
  }).unwrap_or_else(() => raise ClientSourceStop(Publication))
}

///|
fn source_publication_field(
  value : @decode.Cursor,
  name : String,
) -> @decode.Cursor raise ClientSourceStop {
  let object = @decode.open_object(value).unwrap_or_else(() => {
    raise ClientSourceStop(Publication)
  })
  @decode.required(object, name).unwrap_or_else(() => {
    raise ClientSourceStop(Publication)
  })
}

///|
fn source_publication_text(
  value : @decode.Cursor,
  name : String,
) -> String raise ClientSourceStop {
  @decode.text(source_publication_field(value, name)).unwrap_or_else(() => {
    raise ClientSourceStop(Publication)
  })
}

///|
fn source_publication_members(
  environment : @check_environment.WireEnvironment,
  section : @check_environment.Section,
  key : String,
) -> Map[String, @decode.Cursor] raise ClientSourceStop {
  let count = @check_environment.member_count(environment, section)
  if count > 32768 {
    raise ClientSourceStop(Limit)
  }
  let entries : Map[String, @decode.Cursor] = Map([])
  for index in 0..<count {
    let body = @check_environment.member_body(
      @check_environment.member_at(environment, section, index).unwrap(),
    )
    let identity = source_publication_text(body, key)
    if entries.contains(identity) {
      raise ClientSourceStop(Publication)
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
) -> @decode.Cursor raise ClientSourceStop {
  let identity = source_publication_text(reference, "cid")
  guard registry.get(identity) is Some(envelope) else {
    raise ClientSourceStop(Publication)
  }
  if source_publication_text(envelope, "kind") != kind ||
    source_publication_text(envelope, "id") !=
    source_publication_text(reference, "id") ||
    source_publication_text(envelope, "version") !=
    source_publication_text(reference, "version") {
    raise ClientSourceStop(Publication)
  }
  source_publication_field(envelope, "body")
}

///|
fn client_source_context(
  environment : @program_check.CheckEnvironment,
  publication : String,
  declarations : String?,
) -> @query_program.Context raise ClientSourceStop {
  let root = source_publication_cursor(publication)
  @decode.closed_object(root, ["environmentCid", "aliases"]).unwrap_or_else(() => {
    raise ClientSourceStop(Publication)
  })
  |> ignore
  let environment_cid = @program_check.checking_environment_cid(environment)
  if source_publication_text(root, "environmentCid") != environment_cid {
    raise ClientSourceStop(Publication)
  }
  let aliases = @decode.elements(source_publication_field(root, "aliases")).unwrap_or_else(() => {
      raise ClientSourceStop(Publication)
    },
  )
  if aliases.length() > 1024 {
    raise ClientSourceStop(Limit)
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
  for index, entry in aliases {
    @decode.closed_object(entry, [
      "name", "sourceRef", "sourceViewContractCid", "schemaContractCid",
    ]).unwrap_or_else(() => raise ClientSourceStop(Publication))
    |> ignore
    let name = @query_syntax.parse_relation_path(
      source_publication_text(entry, "name"),
      {
        max_source_bytes: 1024,
        max_tokens: 256,
        max_literal_bytes: 1024,
        max_work: 16384,
      },
    ).unwrap_or_else(() => raise ClientSourceStop(Publication))
    let source_ref = source_publication_text(entry, "sourceRef")
    guard views.get(source_publication_text(entry, "sourceViewContractCid"))
      is Some(view) else {
      raise ClientSourceStop(Publication)
    }
    let output = source_publication_field(view, "output")
    if source_publication_text(output, "carrier") != "relation" {
      raise ClientSourceStop(UnsupportedCarrier)
    }
    let schema_ref = source_publication_field(output, "schema")
    if source_publication_text(schema_ref, "cid") !=
      source_publication_text(entry, "schemaContractCid") {
      raise ClientSourceStop(Publication)
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
      raise ClientSourceStop(Publication)
    }
    let fields = @decode.object_field_names(
      source_publication_field(schema, "fields"),
    ).unwrap_or_else(() => raise ClientSourceStop(Publication))
    if fields.length() > 8192 || fields.length() > 65536 - field_count {
      raise ClientSourceStop(Limit)
    }
    field_count += fields.length()
    let connector = source_publication_text(view, "connector_id")
    let view_id = source_publication_text(view, "view_id")
    let prefix = "connector://" + connector + "/"
    let suffix = "#" + view_id
    if !source_ref.has_prefix(prefix) ||
      !source_ref.has_suffix(suffix) ||
      source_ref.length() <= prefix.length() + suffix.length() {
      raise ClientSourceStop(Publication)
    }
    let resource = source_ref[prefix.length():source_ref.length() -
    suffix.length()].to_owned()
    let input = try {
      let writer = @encode.writer(16384, 32, 8)
      @encode.begin_object(writer)
      for
        (key, value) in [
          ("connector", connector),
          ("resource", resource),
          ("view", view_id),
        ] {
        @encode.key(writer, key)
        @encode.string_value(writer, value)
      }
      @encode.end_object(writer)
      source_publication_cursor(@encode.finish(writer))
    } catch {
      _ => raise ClientSourceStop(Publication)
    }
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
  let parameter_declarations = match declarations {
    None => None
    Some(body) => {
      let cursor = source_publication_cursor(body) catch {
        _ => raise ClientSourceStop(Declarations)
      }
      Some(
        @parameter_binding.read_declarations(Some(cursor), {
          max_parameters: 1024,
          max_nodes: 8192,
          max_depth: 64,
          max_text_bytes: 65536,
        }).unwrap_or_else(() => raise ClientSourceStop(Declarations)),
      )
    }
  }
  match
    @source_frontend.bind_query_context(
      published,
      environment_cid,
      parameter_declarations~,
    ) {
    Ok(value) => value
    Err(issue) => raise ClientSourceStop(Alias(issue))
  }
}

///|
#export_name("clientProgramCheckingEnvironmentCid")
pub fn client_program_checking_environment_cid(
  environment : @program_check.CheckEnvironment,
) -> String {
  @program_check.checking_environment_cid(environment)
}

///|
#export_name("clientProgramSourcePublicationValid")
pub fn client_program_source_publication_valid(
  environment : @program_check.CheckEnvironment,
  publication : String,
) -> Bool {
  try {
    client_source_context(environment, publication, None) |> ignore
    true
  } catch {
    _ => false
  }
}

///|
#export_name("clientProgramPrepareSourceWithParameters")
pub fn client_program_prepare_source_with_parameters(
  document : String,
  format : String,
  environment : @program_check.CheckEnvironment,
  publication : String,
  declarations : String?,
  parameters : String?,
) -> ClientProgramBridgeOutcome {
  let context = client_source_context(environment, publication, declarations) catch {
    ClientSourceStop(issue) => return Rejected(SourcePreparation(issue))
  }
  let selected = match @source_frontend.select_format(format) {
    Ok(Text) => @source_frontend.Text
    Ok(Sql) => @source_frontend.Sql
    _ => return Rejected(InvalidFormat)
  }
  let lowered = match
    @source_frontend.lower(document, selected, Some(context)) {
    Ok(value) => value
    Err(issue) => return Rejected(SourcePreparation(Frontend(issue)))
  }
  client_program_prepare_effect_free_with_parameters(
    lowered.document,
    "json",
    environment,
    parameters,
  )
}
