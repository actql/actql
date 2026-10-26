///|
// Explicit caller selection only. It is not a fresh-state witness or an issue
// policy: the original Native Session proves eligibility and owns all cleanup.
priv struct LocalInitialSigningAdoptionOptions {
  initialize_signing : Bool
  ttl_ms : Double
  max_records : Int
  max_snapshot_bytes : Int64
  initial_host_signing : (String, String, String)?
}

///|
// Public init requests this branch after admitting the same installed Native
// image. Ordinary adopt without that request keeps the original reader.
// Missing old material cannot select generation; no failure falls back to the
// legacy initializer or a second key, policy, operation or initialization.
fn local_open_initial_signing_adoption(
  session : @local_host.NativeLocalAdoptionSession,
  sqlite : @local_sqlite.Library,
  crypto : @local_crypto.Library,
  options : LocalInitialSigningAdoptionOptions,
) -> Result[
  @local_host.NativeLocalHostConnection,
  @local_host.NativeLocalAdoptionIssue,
] {
  if !options.initialize_signing {
    return session.open_journal(
      sqlite,
      crypto,
      options.ttl_ms,
      options.max_records,
      options.max_snapshot_bytes,
    )
  }
  let material = match
    session.create_initial_signing_material(
      crypto,
      host_signing_subject=options.initial_host_signing,
    ) {
    Ok(value) => value
    // The original Session retains this same failed acquisition/Writer until
    // actual cleanup acknowledgement. The enclosing caller closes that Session
    // before reporting any result; a cleanup failure cannot become adoption.
    Err(original) => return Err(original.issue())
  }
  session.open_journal_with_initial_signing_material(
    material,
    @run_host.client_local_default_signing_bootstrap_policy(),
    sqlite,
    crypto,
    options.ttl_ms,
    options.max_records,
    options.max_snapshot_bytes,
  )
}
