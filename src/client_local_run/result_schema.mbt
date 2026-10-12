///|
/// The original Result receipt owns both fields. This read-only projection
/// retains the original preflight/Result relation and current Run/Source checks;
/// neither field is Store completion or current publisher authority.
pub(all) enum LocalResultSchemaIssue {
  Preflight(LocalPublicationIntentIssue)
  Output(@host.PublicationOutputExportIssue)
}

///|
pub(all) enum LocalResultSchemaField {
  Identity
  Wire
}

///|
pub fn local_preflight_result_schema_field(
  preflight : LocalPublicationPreflight,
  result : Int,
  original : LocalResultPublication,
  account : @authorization.AdmittedAccountConfiguration,
  field : LocalResultSchemaField,
) -> Result[String, LocalResultSchemaIssue] {
  match
    reuse_local_preflight_result_publication(
      preflight,
      result,
      original,
      original.output,
      account,
    ) {
    Err(issue) => return Err(Preflight(issue))
    Ok(_) => ()
  }
  let projected = match field {
    Identity => original.output.result_schema_cid()
    Wire => original.output.result_schema_wire()
  }
  projected.map_err(issue => Output(issue))
}
