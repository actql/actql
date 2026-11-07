///|
extern "js" fn request_keyed_prefix_original_throw(
  body : (() -> Bool) -> Unit,
) -> Bool =
  #|(body) => { const original = new Error('keyed-prefix-original-input'); let calls = 0; try { body(() => { calls++; throw original; }); return false; } catch (error) { if (error !== original) throw error; return calls === 1; } }

///|
// Actual Request/RowRun/empty Direct capture/key-set/provider. Resource/current,
// installation and stop ports are explicit; no physical Source, Account, Store
// or ordinary installed runtime acceptance is implied by this component.
priv struct RequestKeyedPrefixFixture {
  original : RequestKeyedConstructorFixture
  selected : ClientInstalledManagedKeyedPreparation
  run : ClientInstalledManagedRun
  read : ClientInstalledSourceRead
  source : @query.CapturedInputSource
  lookup : @publication_host.ClientKeyedLookupInput
}

///|
fn request_keyed_prefix_fixture(
  current? : () -> Bool = () => true,
  available? : () -> Bool = () => true,
) -> RequestKeyedPrefixFixture raise {
  let original = request_keyed_constructor_fixture(current~)
  let selected = request_keyed_constructor(original).unwrap()
  prepare_request_keyed_serialization_compilation(
    original.parent,
    original.input,
    selected,
    original.graph,
    manifests=original.manifests,
    compilation_limits=original.compilation_limits,
  ).unwrap()
  |> ignore
  complete_request_content_preparation(
    original.parent,
    original.input,
    original.request,
    selected,
  ).unwrap()
  let run = begin_request_content_managed_run(original.parent, original.request).unwrap()
  let (read, _, acquisition, direct) = begin_installed_managed_capture_source_read(
    run,
    original.prepared,
    original.request,
    original.original.3,
    selected.direct_stage,
  ).unwrap()
  let ledger = prepare_installed_managed_run_ledger(
    run,
    original.prepared,
    original.request,
    [direct],
    [8192L],
    [4096L],
    original.contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let rows = start_installed_source_read_rows(
    read,
    acquisition,
    "request-keyed-empty-source",
    _ => true,
    8192L,
    4096L,
  ).unwrap()
  let issuer = @admitted.bind_reference_issuer((_, _) => true, _ => true)
  @row_source_host.begin_row_run(
    rows,
    4096,
    3,
    3,
    reference_issuer=Some(issuer),
  ).unwrap()
  @row_source_host.begin_row_run_listing_request(rows, None, 0L).unwrap()
  @row_source_host.begin_row_run_listing_page(
    rows,
    @utf8.encode("{\"items\":[],\"request_token\":null,\"next_token\":null}"),
    0L,
  ).unwrap()
  let mut page_completed = false
  for _ in 0..<10000 {
    match @row_source_host.advance_row_run_listing_page(rows, 1, 0L).unwrap() {
      @row_source_host.ListingPageContinue(_) => ()
      @row_source_host.ListingPageComplete(rows~, ..) => {
        assert_eq(rows, 0)
        page_completed = true
        break
      }
    }
  }
  assert_true(page_completed)
  @row_source_host.finish_row_run(rows).unwrap()
  @row_source_host.begin_row_capture(rows).unwrap()
  let mut completed = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(rows, 256).unwrap().0 {
      completed = true
      break
    }
  }
  assert_true(completed)
  let captured = @row_source_host.capture_row_run(rows).unwrap()
  let source = @query.restrict_captured_source(
    @row_source_host.row_capture_source(captured).unwrap(),
    available,
  )
  let left = @publication_host.prepare_client_keyed_capture_left_read(
    original.keyed,
    source,
    10000,
    4096,
  ).unwrap()
  let lookup = @publication_host.start_client_keyed_lookup_input(
    left, ledger, 4096, 1000000,
  ).unwrap()
  @publication_host.finish_client_keyed_lookup_input(lookup).unwrap() |> ignore
  { original, selected, run, read, source, lookup, }
}

///|
fn request_keyed_prefix_close(value : RequestKeyedPrefixFixture) -> Unit raise {
  assert_true(
    cleanup_installed_managed_keyed_serialization_prefix(
      value.run,
      value.selected,
    ).unwrap(),
  )
  assert_true(
    @publication_host.cleanup_client_keyed_lookup_input(value.lookup, 1000000).unwrap(),
  )
  retire_installed_source_read(value.read).unwrap()
  assert_false(
    @resources.return_preparation_body_borrow(value.original.holder).unwrap(),
  )
  retire_installed_managed_run(value.run).unwrap()
  assert_eq(
    @resources.ledger_usage(value.original.parent.ledger).live_reservations,
    0,
  )
}

///|
test "keyed Request starts the same retained prefix once after reservation and returns its original empty output" {
  let active : Ref[ClientInstalledManagedRun?] = Ref(None)
  let fenced = Ref(false)
  let value = request_keyed_prefix_fixture(current=() => {
    if active.val is Some(run) {
      fenced.val = retire_installed_managed_run(run) is Err(CleanupPending)
    }
    true
  })
  let before = @resources.ledger_usage(value.original.parent.ledger)
  active.val = Some(value.run)
  let prefix = start_installed_managed_keyed_serialization_prefix(
    value.run,
    value.original.prepared,
    value.selected,
    value.source,
    value.lookup,
  ).unwrap()
  active.val = None
  assert_true(fenced.val)
  assert_true(physical_equal(prefix.ledger, value.original.parent.ledger))
  assert_true(
    value.run.serialization_prefix is Some(original) &&
    physical_equal(original, prefix),
  )
  let started = @resources.ledger_usage(value.original.parent.ledger)
  assert_true(started.reserved_attempts > before.reserved_attempts)
  assert_true(
    start_installed_managed_keyed_serialization_prefix(
      value.run,
      value.original.prepared,
      value.selected,
      value.source,
      value.lookup,
    )
    is Err(AlreadyBound),
  )
  assert_eq(@resources.ledger_usage(value.original.parent.ledger), started)
  assert_true(retire_installed_managed_run(value.run) is Err(CleanupPending))
  let mut output : @execution.CompletedOutput? = None
  for _ in 0..<10000 {
    match advance_client_serialization_prefix(prefix, 64).unwrap() {
      @local.Complete(value, ..) => {
        output = Some(value)
        break
      }
      @local.Continue(..) | @local.Waiting(..) | @local.Settling(_, ..) => ()
      _ => fail("original empty keyed prefix did not complete")
    }
  }
  assert_eq(@execution.completed_row_count(output.unwrap()), 0)
  request_keyed_prefix_close(value)
}

///|
test "keyed Request input callback keeps original cause and cleans only the reserved never-entered provider slot" {
  let throwing : Ref[(() -> Bool)?] = Ref(None)
  let value = request_keyed_prefix_fixture(available=() => {
    match throwing.val {
      None => true
      Some(callback) => callback()
    }
  })
  let before = @resources.ledger_usage(value.original.parent.ledger)
  assert_true(
    request_keyed_prefix_original_throw(callback => {
      throwing.val = Some(callback)
      start_installed_managed_keyed_serialization_prefix(
        value.run,
        value.original.prepared,
        value.selected,
        value.source,
        value.lookup,
      )
      |> ignore
    }),
  )
  throwing.val = None
  let prefix = value.run.serialization_prefix.unwrap()
  assert_true(prefix.child is None && prefix.child_cleaned && prefix.released)
  assert_false(value.run.source_free_opening)
  let after = @resources.ledger_usage(value.original.parent.ledger)
  assert_eq(after.live_reservations, before.live_reservations)
  assert_true(
    start_installed_managed_keyed_serialization_prefix(
      value.run,
      value.original.prepared,
      value.selected,
      value.source,
      value.lookup,
    )
    is Err(AlreadyBound),
  )
  request_keyed_prefix_close(value)
}

///|
test "keyed Request prefix refuses a copied Plan or current decline before exposing another child" {
  let allowed = Ref(true)
  let value = request_keyed_prefix_fixture(current=() => allowed.val)
  let copied = { ..value.selected, }
  let before = @resources.ledger_usage(value.original.parent.ledger)
  assert_true(
    start_installed_managed_keyed_serialization_prefix(
      value.run,
      value.original.prepared,
      copied,
      value.source,
      value.lookup,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(value.original.parent.ledger), before)
  allowed.val = false
  assert_true(
    start_installed_managed_keyed_serialization_prefix(
      value.run,
      value.original.prepared,
      value.selected,
      value.source,
      value.lookup,
    )
    is Err(_),
  )
  allowed.val = true
  assert_true(value.run.serialization_prefix is None)
  assert_false(value.run.source_free_opening)
  request_keyed_prefix_close(value)
}
