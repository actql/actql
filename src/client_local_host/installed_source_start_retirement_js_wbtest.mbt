///|
// Actual Request/Plan/provider acquisition. The current callback reaches the
// original constructor before its RowRun is returned; no Source I/O occurs.
#cfg(target="js")
test "Source provider start retains its original child when current reenters retirement" {
  let observe : Ref[(() -> Unit)?] = Ref(None)
  let attempts = Ref(0)
  let pending = Ref(true)
  let (parent, owner, plan, declaration) = pure_provider_capture_fixture(current=() => {
    if observe.val is Some(callback) {
      callback()
    }
    true
  })
  let (read, _, acquisition, _) = begin_installed_managed_capture_source_read(
    owner,
    plan.prepared,
    plan.request,
    declaration,
    0,
  ).unwrap()
  observe.val = Some(() => {
    if !(read.start is Unstarted) && read.run is None {
      attempts.val += 1
      pending.val = pending.val &&
        retire_installed_source_read(read) is Err(CleanupPending)
    }
  })
  let opened = start_installed_source_read_provider_rows(
    read,
    acquisition,
    Some(plan.captures[0].provider.unwrap().1),
    "source-start-reentrant",
    _ => true,
    4096L,
    2048L,
  )
  observe.val = None
  // Retain and retire the actual returned child even on the original red.
  // Its absence from a retired read is not physical cleanup evidence.
  if opened is Ok(run) {
    @row_source_host.close_accounted_row_run(run).unwrap()
  }
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_true(attempts.val > 0)
  assert_true(pending.val)
}
