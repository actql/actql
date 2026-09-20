///|
fn emit_site_journal_binding(
  site_key : String,
  site_generation : Int,
  runtime_revision : String,
  protocol_version : String,
) -> Result[String, DispatchIssue] {
  if site_key.is_empty() ||
    site_generation < 0 ||
    !valid_cid(runtime_revision) ||
    protocol_version != "actql-remote-site/0.1" {
    return Err(InvalidJournal)
  }
  let writer = @encode.writer(4096, 8, 1) catch {
    _ => return Err(InvalidJournal)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "protocol_version")
    @encode.string_value(writer, protocol_version)
    @encode.key(writer, "runtime_revision")
    @encode.string_value(writer, runtime_revision)
    @encode.key(writer, "site_generation")
    @encode.number_value(writer, site_generation.to_double())
    @encode.key(writer, "site_key")
    @encode.string_value(writer, site_key)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-site-binding/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidJournal)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(InvalidJournal) })
}

///|
/// Canonical durable binding for the current Site journal authority.
pub fn site_dispatch_binding_json(
  journal : SiteDispatchJournal,
) -> Result[String, DispatchIssue] {
  emit_site_journal_binding(
    @site.site_key(journal.site),
    @site.site_generation(journal.site),
    @site.site_runtime_revision(journal.site),
    journal.protocol_version,
  )
}

///|
/// Canonical durable binding installed atomically with a generation restart.
pub fn site_restart_next_binding_json(
  restart : SiteRestartTransition,
) -> Result[String, DispatchIssue] {
  emit_site_journal_binding(
    @site.site_key(restart.replacement),
    @site.site_generation(restart.replacement),
    @site.site_runtime_revision(restart.replacement),
    restart.journal.protocol_version,
  )
}
