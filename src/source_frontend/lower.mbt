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
) -> Result[@query.Context, AliasIssue] {
  if aliases.length() > 1024 {
    return Err(TooManyAliases)
  }
  if program_id.is_empty() {
    return Err(InvalidProgramId)
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
  Ok({
    program_id,
    stage_id: "main",
    stage_result: "rows",
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
    "aql-text" => Ok(Text)
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
fn emit(program : @program.Program) -> Result[Lowered, Issue] {
  let document = try {
    let writer = @encode.writer(65536, 8192, 64)
    @program.emit_program_source(program, writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Encoding)
  }
  Ok({ document, format: @program.Json, })
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
  match format {
    Text | Sql => ()
    Json | Yaml => return Err(InvalidFormat)
  }
  let query_form = match
    @syntax.starts_query(document, syntax_limits().lexical, source_path~) {
    Ok(value) => value
    Err(issue) => return Err(QuerySyntax(issue))
  }
  if !query_form {
    return Err(WrongQueryForm)
  }
  if format == Sql {
    match @syntax.starts_sql(document, syntax_limits().lexical, source_path~) {
      Ok(true) => ()
      Ok(false) => return Err(WrongQueryForm)
      Err(issue) => return Err(QuerySyntax(issue))
    }
  }
  match @syntax.parse_query(document, syntax_limits(), source_path~) {
    Ok(value) => Ok(value)
    Err(issue) => Err(QuerySyntax(issue))
  }
}

///|
/// Lower only the selected query language. No structural text fallback or
/// compatibility parser is available. The Host checks the resulting Program normally.
pub fn lower(
  document : String,
  format : Format,
  context : @query.Context?,
  source_path? : String = "<source>",
) -> Result[Lowered, Issue] {
  match format {
    Json => Ok({ document, format: @program.Json, })
    Yaml => Ok({ document, format: @program.Yaml, })
    Text | Sql => {
      let parsed = match parse_query(document, format, source_path~) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      guard context is Some(context) else { return Err(MissingQueryContext) }
      let program = match @query.compile(parsed, context, query_limits()) {
        Ok(value) => value
        Err(issue) => return Err(QueryLowering(issue))
      }
      emit(program)
    }
  }
}
