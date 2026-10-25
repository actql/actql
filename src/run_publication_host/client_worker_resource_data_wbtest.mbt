///|
// Independent scalar vectors, not a live ticket, physical supplier or Store.
fn worker_resource_test_data() -> @resources.BackedExecutionOriginalData {
  {
    allocation_bytes: 128L,
    extent: {
      offset: 16L,
      length: 80L,
      payload_offset: 8L,
      payload_length: 64L,
    },
    access: @resources.ExclusiveWrite,
    limits: {
      planning_work: 8,
      attempts: 2,
      holdings: 4,
      transfer_bytes: 100L,
      retained_bytes: 20L,
      execution_bytes: 30L,
    },
    cumulative: {
      planning_work: 2,
      attempts: 1,
      transferred_bytes: 7L,
      uncertain_transfer_bytes: 3L,
    },
    occupation: {
      holdings: 1,
      reserved_attempts: 0,
      live_reservations: 0,
      live_delegations: 0,
    },
    peak_retention_bytes: 10L,
    provision: {
      transfer_bytes: 90L,
      retained_bytes: 5L,
      execution_bytes: 7L,
      open: true,
      cleanup_pending: true,
    },
    region_closing: false,
    read_use: @resources.Pending,
    final_usage: None,
  }
}

///|
test "worker resource DATA preserves independent debt Unknown and unavailable final usage" {
  let data = worker_resource_test_data()
  let body = client_worker_resource_original_body(data).unwrap()
  // Independently written field/value oracle, not re-encoded product output.
  let expected =
    #|{"access":"exclusive_write","allocation_bytes":"128","extent_offset":"16","extent_length":"80","payload_offset":"8","payload_length":"64","limit_planning_work":"8","limit_attempts":"2","limit_holdings":"4","limit_transfer_bytes":"100","limit_retained_bytes":"20","limit_execution_bytes":"30","cumulative_planning_work":"2","cumulative_attempts":"1","occupied_holdings":"1","cumulative_transferred_bytes":"7","cumulative_uncertain_transfer_bytes":"3","peak_retention_bytes":"10","provision_transfer_bytes":"90","provision_retained_bytes":"5","provision_execution_bytes":"7","provision_open":"true","provision_cleanup_pending":"true","region_closing":"false","read_use":"pending","final_observed":"false","final_planning_work":"","final_attempts":"","final_holdings":"","final_transferred_bytes":"","final_uncertain_transfer_bytes":"","final_reserved_transfer_bytes":"","final_held_bytes":"","final_reserved_retention_bytes":"","final_reserved_execution_bytes":"","final_peak_retention_bytes":"","occupied_reserved_attempts":"0","occupied_live_reservations":"0","occupied_live_delegations":"0","final_reserved_attempts":"","final_live_reservations":"","final_live_delegations":""}
  assert_eq(body, @utf8.encode(expected))
  let observation = read_client_worker_resource_original(body).unwrap()
  let saved = @resources.unresolved_backed_execution_data(observation)
  assert_eq(saved, data)
  assert_eq(saved.cumulative.transferred_bytes, 7L)
  assert_eq(saved.cumulative.uncertain_transfer_bytes, 3L)
  assert_eq(saved.provision.transfer_bytes, 90L)
  assert_true(saved.provision.cleanup_pending)
  assert_true(saved.final_usage is None)
  let text = @utf8.decode(body)
  assert_true(text.contains("\"cumulative_uncertain_transfer_bytes\":\"3\""))
  assert_true(text.contains("\"final_observed\":\"false\""))
  assert_true(text.contains("\"final_planning_work\":\"\""))
}

///|
test "worker resource DATA keeps Int64 above JSON safe number and rejects repaired decimals" {
  let original = worker_resource_test_data()
  let data = {
    ..original,
    limits: { ..original.limits, transfer_bytes: 9223372036854775807L, },
    cumulative: {
      ..original.cumulative,
      transferred_bytes: 9007199254740993L,
      uncertain_transfer_bytes: 7L,
    },
    provision: { ..original.provision, transfer_bytes: 9214364837600034807L, },
  }
  let body = client_worker_resource_original_body(data).unwrap()
  let saved = @resources.unresolved_backed_execution_data(
    read_client_worker_resource_original(body).unwrap(),
  )
  assert_eq(saved.cumulative.transferred_bytes, 9007199254740993L)
  assert_eq(saved.limits.transfer_bytes, 9223372036854775807L)
  assert_true(
    worker_resource_integer("9223372036854775807") is Some(9223372036854775807L),
  )
  for
    invalid in [
      "9223372036854775808", "00", "01", "+1", "-0", "1.0", "1e2", " 1", "", "１",
    ] {
    assert_true(worker_resource_integer(invalid) is None)
  }
  let text = @utf8.decode(body)
  for
    replacement in [
      "\"09007199254740993\"", "9007199254740993", "\"9.007199254740993e15\"",
    ] {
    assert_true(
      read_client_worker_resource_original(
        @utf8.encode(text.replace(old="\"9007199254740993\"", new=replacement)),
      )
      is Err(_),
    )
  }
}

///|
test "worker resource DATA rejects duplicate unknown truncated inconsistent or oversized fields" {
  let data = worker_resource_test_data()
  let body = client_worker_resource_original_body(data).unwrap()
  let text = @utf8.decode(body)
  for
    invalid in [
      text.replace(old="{", new="{\"extra\":\"x\","),
      text.replace(old="{", new="{\"access\":\"exclusive_write\","),
      text.replace(
        old="\"provision_transfer_bytes\":\"90\"",
        new="\"provision_transfer_bytes\":\"91\"",
      ),
      text.replace(
        old="\"limit_attempts\":\"2\"",
        new="\"limit_attempts\":\"2147483648\"",
      ),
      text.replace(
        old="\"provision_open\":\"true\"",
        new="\"provision_open\":\"yes\"",
      ),
      text.replace(
        old="\"final_planning_work\":\"\"",
        new="\"final_planning_work\":\"0\"",
      ),
      text.replace(
        old="\"read_use\":\"pending\"",
        new="\"read_use\":\"unknown\"",
      ),
      "{}",
      " ".repeat(8193),
    ] {
    assert_true(
      read_client_worker_resource_original(@utf8.encode(invalid)) is Err(_),
    )
  }
  assert_true(
    client_worker_resource_original_body({
      ..data,
      cumulative: { ..data.cumulative, uncertain_transfer_bytes: 101L, },
    })
    is Err(InvalidOriginal),
  )
}

///|
test "worker resource DATA preserves conservative closed Unknown and distinct observed final census" {
  let data = worker_resource_test_data()
  let unknown = {
    ..data,
    cumulative: {
      planning_work: 8,
      attempts: 2,
      transferred_bytes: 7L,
      uncertain_transfer_bytes: 93L,
    },
    provision: {
      transfer_bytes: 0L,
      retained_bytes: 0L,
      execution_bytes: 0L,
      open: false,
      cleanup_pending: false,
    },
    read_use: @resources.Retired,
    occupation: {
      holdings: 0,
      reserved_attempts: 0,
      live_reservations: 0,
      live_delegations: 0,
    },
  }
  let restored = @resources.unresolved_backed_execution_data(
    read_client_worker_resource_original(
      client_worker_resource_original_body(unknown).unwrap(),
    ).unwrap(),
  )
  assert_true(restored.final_usage is None)
  assert_eq(restored.cumulative.uncertain_transfer_bytes, 93L)
  let final_census : @resources.LedgerUsage = {
    planning_work: 2,
    attempts: 1,
    holdings: 1,
    reserved_attempts: 0,
    live_reservations: 0,
    live_delegations: 0,
    transferred_bytes: 7L,
    uncertain_transfer_bytes: 3L,
    reserved_transfer_bytes: 90L,
    held_bytes: 2L,
    reserved_retention_bytes: 1L,
    reserved_execution_bytes: 0L,
    peak_retention_bytes: 10L,
  }
  let observed = {
    ..unknown,
    cumulative: data.cumulative,
    final_usage: Some(final_census),
  }
  let saved = @resources.unresolved_backed_execution_data(
    read_client_worker_resource_original(
      client_worker_resource_original_body(observed).unwrap(),
    ).unwrap(),
  )
  assert_eq(saved.final_usage, Some(final_census))
  // Neither observation contains a nominal ticket, permission or stop ACK.
  assert_eq(unknown.final_usage, None)
}
