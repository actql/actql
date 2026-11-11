///|
// Original bounded input admission shared by the Host check and existing Node
// preparation. This decodes DATA; it does not check a Program or issue a grant.
pub(all) enum LocalProgramInputIssue {
  InvalidFormat
  SuppliedSyntax(@source.ParseError)
  SuppliedAdmission(@decode.Issue)
} derive(Debug)

///|
pub fn admit_local_program_input(
  format : String,
  parameters : String?,
) -> Result[(@syntax.Format, @decode.Cursor?), LocalProgramInputIssue] {
  let selected = match format {
    "json" => @syntax.Json
    "yaml" => @syntax.Yaml
    _ => return Err(InvalidFormat)
  }
  let supplied = match parameters {
    None => None
    Some(body) => {
      let (source_limits, tree_limits) = local_parameter_input_limits()
      match admit_local_parameter_document(body, source_limits, tree_limits) {
        Ok(value) => Some(value)
        Err(issue) => return Err(issue)
      }
    }
  }
  Ok((selected, supplied))
}

///|
priv suberror CheckPublicationStop {
  CheckPublicationStop(@publication.PublicationIssue)
}

///|
fn source_publication_cursor(
  wire : String,
) -> @decode.Cursor raise CheckPublicationStop {
  match @publication.read_publication_data(wire) {
    Ok(value) => value
    Err(issue) => raise CheckPublicationStop(issue)
  }
}

///|
fn check_published_context(
  environment : @checked.CheckEnvironment,
  publication : String,
  declarations : String?,
) -> @query.Context raise CheckPublicationStop {
  match
    @publication.bind_published_query_context(
      environment, publication, declarations,
    ) {
    Ok(context) => context
    Err(issue) => raise CheckPublicationStop(issue)
  }
}

///|
/// The existing Local supplied-values limits, shared by textual and captured
/// intake. These are selected DATA, never another resource allowance.
pub fn local_parameter_input_limits() -> (@source.ParseLimits, @decode.Limits) {
  (
    { max_input_bytes: 65536, max_nodes: 8192, max_depth: 64, },
    {
      max_nodes: 8192,
      max_depth: 64,
      max_string_bytes: 65536,
      max_total_string_bytes: 65536,
    },
  )
}

///|
/// Continue the exact captured native values through the SAME Local reader
/// policy. Its existing normalized-key semantics and refusal limits remain;
/// no document serialization, Program preparation or second check is run.
pub fn[T] admit_captured_local_parameters(
  input : T,
  reader : @source.JsonDataReader[T],
  limits? : (@source.ParseLimits, @decode.Limits)? = None,
) -> Result[@decode.Cursor, LocalProgramInputIssue] {
  let (source_limits, tree_limits) = match limits {
    Some(selected) => selected
    None => local_parameter_input_limits()
  }
  let parsed = match
    @source.admit_captured_json(
      input,
      reader,
      source_limits,
      normalize_keys=true,
      source_path="Client Parameters",
    ) {
    Err(issue) => return Err(SuppliedSyntax(issue))
    Ok(value) => value
  }
  @decode.admit(parsed.node, tree_limits).map_err(issue => {
    SuppliedAdmission(issue)
  })
}

///|
/// One original textual Parameters admission. The fixed caller supplies its
/// selected syntax bounds after backing this parser/index coexistence on its
/// existing Request. These DATA cannot supply funding, currentness or a grant.
/// The same normalized-key reader is shared with the default Local entry.
pub fn admit_local_parameter_document(
  body : String,
  source_limits : @source.ParseLimits,
  tree_limits : @decode.Limits,
) -> Result[@decode.Cursor, LocalProgramInputIssue] {
  let parsed = match
    @source.parse_json_bytes(
      @utf8.encode(body),
      source_limits,
      source_path="Client Parameters",
    ) {
    Ok(value) => value
    Err(issue) => return Err(SuppliedSyntax(issue))
  }
  @decode.admit(parsed, tree_limits).map_err(issue => SuppliedAdmission(issue))
}
