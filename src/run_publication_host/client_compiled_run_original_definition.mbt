///|
/// Read only the binding already issued by this exact compiled Run. Unlike the
/// validating binder, this projection never constructs a new binding or accepts
/// a same-CID replacement as the original definition.
pub fn client_compiled_run_has_original_definition(
  value : ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Bool {
  match value.definition_binding {
    Some(original) => client_compiled_run_definition_facts_match(original, value, definition)
    None => false
  }
}
