///|
/// The trusted Host admits this metadata only after its existing publication
/// and authorization Owners close the unfiltered registration range for this
/// original call. It is not a client-supplied declaration or execution permit.
pub struct ClientCheckSourceNamespace {
  priv name : String
  priv context_ref : String
  priv source_revision : String
  priv environment_cid : String
  priv context : @query_program.Context
}

///|
#export_name("clientProgramCheckSourceNamespace")
pub fn client_program_check_source_namespace(
  environment : @program_check.CheckEnvironment,
  publication : String,
  namespace_name : String,
  configuration_revision : String,
  context_ref : String,
  source_revision : String,
) -> ClientCheckSourceNamespace? {
  if namespace_name.is_empty() ||
    @utf8.encode(namespace_name).length() > 256 ||
    !check_namespace_reference(configuration_revision, "sha256:") ||
    !check_namespace_reference(context_ref, "ctx:") ||
    !check_namespace_reference(source_revision, "rev:") {
    return None
  }
  let context = client_source_context(environment, publication, None) catch {
    _ => return None
  }
  Some({
    name: namespace_name,
    context_ref,
    source_revision,
    environment_cid: @program_check.checking_environment_cid(environment),
    context,
  })
}

///|
fn check_namespace_reference(value : String, prefix : String) -> Bool {
  value.has_prefix(prefix) &&
  value.length() == prefix.length() + 64 &&
  value[prefix.length():]
  .to_owned()
  .iter()
  .all(character => {
    let code = character.to_int()
    (code >= 48 && code <= 57) || (code >= 97 && code <= 102)
  })
}

///|
fn check_source_alias_absence(
  source_namespace : ClientCheckSourceNamespace?,
  issue : @query_program.Issue,
) -> CheckFinding {
  match source_namespace {
    Some(complete) if @query_program.unresolved_relation_namespace_presence(
        issue,
        complete.context,
      )
      is Some(false) => {
      let reference = @query_program.unresolved_relation_reference(issue).unwrap()
      QueryAliasAbsent(complete.name, reference)
    }
    _ => Unresolved("source_resolution")
  }
}

///|
fn write_check_query_alias_absence(
  writer : @encode.Writer,
  findings : Array[CheckFinding],
) -> Unit raise @encode.EncodeFailure {
  for finding in findings {
    if finding is QueryAliasAbsent(name, reference) {
      @encode.key(writer, "facts")
      @encode.begin_object(writer)
      @encode.key(writer, "namespace")
      @encode.string_value(writer, name)
      @encode.key(writer, "reference")
      @encode.begin_array(writer)
      for part in reference {
        @encode.begin_object(writer)
        @encode.key(writer, "value")
        @encode.string_value(writer, part.value)
        @encode.key(writer, "quoted")
        @encode.bool_value(writer, part.quoted)
        @encode.end_object(writer)
      }
      @encode.end_array(writer)
      @encode.end_object(writer)
      break
    }
  }
}
