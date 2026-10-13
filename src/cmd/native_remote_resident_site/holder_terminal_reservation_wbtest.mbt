///|
/// Actual Site Owner arithmetic with a returning diagnostic model. This does
/// not execute the Native terminal abort or prove physical process retirement.
test "terminal consumes diagnostic before original reservation settlement" {
  let site = @site.create_site("terminal", 1, "runtime", 1, 1, 200L, 100L).unwrap()
  let original = @site.start_site_operation(site, 160L, 80L).unwrap()
  let trace = []
  let valid = Ref(true)
  retain_holder_terminal_reservation(
    original,
    () => {
      trace.push("consume")
      valid.val = valid.val &&
        @site.site_status(site)[7] == 160L &&
        @site.site_status(site)[8] == 80L &&
        @site.start_site_operation(site, 1L, 1L) is None
    },
    received => {
      trace.push("settle")
      valid.val = valid.val &&
        physical_equal(received, original) &&
        @site.site_status(site)[7] == 160L
      valid.val = valid.val && @site.settle_site_operation(received)
    },
  )
  assert_true(valid.val)
  assert_eq(trace, ["consume", "settle"])
  assert_eq(@site.site_status(site)[7], 0L)
  assert_eq(@site.site_status(site)[8], 0L)
  assert_false(@site.settle_site_operation(original))
}

///|
test "snapshot ACK leaves terminal remainder and workspace reserved" {
  let site = @site.create_site("terminal", 1, "runtime", 1, 1, 200L, 100L).unwrap()
  let original = @site.start_site_operation(site, 160L, 80L).unwrap()
  let snapshot = @site.retain_site_operation_holding(original, 100L).unwrap()
  assert_true(@site.release_site_holding(snapshot))
  let valid = Ref(true)
  retain_holder_terminal_reservation(
    original,
    () => {
      valid.val = valid.val &&
        @site.site_status(site)[6] == 0L &&
        @site.site_status(site)[7] == 60L &&
        @site.site_status(site)[8] == 80L &&
        @site.retain_site_operation_holding(original, 1L) is None
    },
    received => valid.val = valid.val && @site.settle_site_operation(received),
  )
  assert_true(valid.val)
  assert_eq(@site.site_status(site)[7], 0L)
  assert_eq(@site.site_status(site)[8], 0L)
}

///|
test "revocation during diagnostic is not an early capacity ACK" {
  let site = @site.create_site("terminal", 1, "runtime", 1, 1, 200L, 100L).unwrap()
  let original = @site.start_site_operation(site, 160L, 80L).unwrap()
  let valid = Ref(true)
  retain_holder_terminal_reservation(
    original,
    () => {
      @site.revoke_site(site)
      valid.val = valid.val &&
        !@site.site_operation_available(original) &&
        @site.site_status(site)[7] == 160L &&
        @site.site_status(site)[8] == 80L
    },
    received => valid.val = valid.val && @site.settle_site_operation(received),
  )
  assert_true(valid.val)
  assert_eq(@site.site_status(site)[7], 0L)
  assert_eq(@site.site_status(site)[8], 0L)
}
