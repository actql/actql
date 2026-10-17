///|
// Original bounded input admission shared by the Host check and existing Node
// preparation. This decodes DATA; it does not check a Program or issue a grant.
pub(all) enum LocalProgramInputIssue {
  InvalidFormat
  SuppliedSyntax(@source.ParseError)
  SuppliedAdmission(@decode.Issue)
}

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
      let parsed = match
        @source.parse_json_bytes(
          @utf8.encode(body),
          { max_input_bytes: 65536, max_nodes: 8192, max_depth: 64, },
          source_path="Client Parameters",
        ) {
        Ok(value) => value
        Err(issue) => return Err(SuppliedSyntax(issue))
      }
      match
        @decode.admit(parsed, {
          max_nodes: 8192,
          max_depth: 64,
          max_string_bytes: 65536,
          max_total_string_bytes: 65536,
        }) {
        Ok(value) => Some(value)
        Err(issue) => return Err(SuppliedAdmission(issue))
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
