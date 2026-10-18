///|
#borrow(session, other, library, crypto)
extern "C" fn journal_transport_probe(
  session : @local_host.NativeLocalAdoptionSession,
  other : @local_host.NativeLocalAdoptionSession,
  library : @local_sqlite.Library,
  crypto : @local_crypto.Library,
  ttl_ms : Double,
  expected_issue : Int,
) -> Int = "actql_native_local_journal_transport_probe"

///|
fn transport_original(
  name : String,
) -> (
  @local_host.NativeLocalAdoptionSession,
  @local_sqlite.Library,
  @local_crypto.Library,
) raise {
  let (host, settings, crypto, _) = effect_finite_cli_host(name)
  host.close_owned_root_descriptors().unwrap()
  let session = @local_host.begin_native_local_host_adoption(
    settings.state_parent,
    settings.state_name,
    settings.managed_root,
    settings.account_file,
    settings.account_id,
    crypto,
    existing_only=true,
    configuration_files=settings.installation_files,
  ).unwrap()
  (
    session,
    @local_sqlite.load_library(settings.sqlite_library).unwrap(),
    crypto,
  )
}

///|
test "regular C journal transport preserves actual successful originals borrowed inputs and owned slots" {
  @local_host.register_native_local_journal_capture_roots()
  let (session, library, crypto) = transport_original("transport-success")
  let (other, _, _) = transport_original("transport-success-other")
  let intent = session.intent_cid()
  assert_eq(
    journal_transport_probe(session, other, library, crypto, 100.0, 0),
    0,
  )
  assert_eq(session.intent_cid(), intent)
  assert_true(session.close())
}

///|
test "regular C journal transport keeps original refusal distinct from close and refuses foreign replies" {
  @local_host.register_native_local_journal_capture_roots()
  let (session, library, crypto) = transport_original("transport-refusal")
  let (other, _, _) = transport_original("transport-refusal-other")
  let intent = session.intent_cid()
  assert_eq(journal_transport_probe(session, other, library, crypto, 0.0, 4), 0)
  assert_eq(session.intent_cid(), intent)
  assert_true(session.close())
}
