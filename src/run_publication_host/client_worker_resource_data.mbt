///|
/// Fixed-size private transport of Resource-owned DATA. This codec neither
/// authenticates Host/Store/physical originals nor creates nominal authority.
fn worker_resource_keys() -> Array[String] {
  [
    "access", "allocation_bytes", "extent_offset", "extent_length", "payload_offset",
    "payload_length", "limit_planning_work", "limit_attempts", "limit_holdings",
    "limit_transfer_bytes", "limit_retained_bytes", "limit_execution_bytes", "cumulative_planning_work",
    "cumulative_attempts", "occupied_holdings", "cumulative_transferred_bytes", "cumulative_uncertain_transfer_bytes",
    "peak_retention_bytes", "provision_transfer_bytes", "provision_retained_bytes",
    "provision_execution_bytes", "provision_open", "provision_cleanup_pending", "region_closing",
    "read_use", "final_observed", "final_planning_work", "final_attempts", "final_holdings",
    "final_transferred_bytes", "final_uncertain_transfer_bytes", "final_reserved_transfer_bytes",
    "final_held_bytes", "final_reserved_retention_bytes", "final_reserved_execution_bytes",
    "final_peak_retention_bytes", "occupied_reserved_attempts", "occupied_live_reservations",
    "occupied_live_delegations", "final_reserved_attempts", "final_live_reservations",
    "final_live_delegations",
  ]
}

///|
/// Encode only after the existing Resource reader admits all cross-field laws.
/// Decimal strings preserve Int64 values across transport without float repair.
pub fn client_worker_resource_original_body(
  data : @resources.BackedExecutionOriginalData,
) -> Result[Bytes, ClientLocalOriginalCodecIssue] {
  if @resources.admit_unresolved_backed_execution_data(data) is Err(_) {
    return Err(InvalidOriginal)
  }
  let fields : Array[(String, String)] = [
    (
      "access",
      match data.access {
        @resources.ReadOnly => "read_only"
        @resources.ExclusiveWrite => "exclusive_write"
      },
    ),
    ("allocation_bytes", data.allocation_bytes.to_string()),
    ("extent_offset", data.extent.offset.to_string()),
    ("extent_length", data.extent.length.to_string()),
    ("payload_offset", data.extent.payload_offset.to_string()),
    ("payload_length", data.extent.payload_length.to_string()),
    ("limit_planning_work", data.limits.planning_work.to_string()),
    ("limit_attempts", data.limits.attempts.to_string()),
    ("limit_holdings", data.limits.holdings.to_string()),
    ("limit_transfer_bytes", data.limits.transfer_bytes.to_string()),
    ("limit_retained_bytes", data.limits.retained_bytes.to_string()),
    ("limit_execution_bytes", data.limits.execution_bytes.to_string()),
    ("cumulative_planning_work", data.cumulative.planning_work.to_string()),
    ("cumulative_attempts", data.cumulative.attempts.to_string()),
    ("occupied_holdings", data.occupation.holdings.to_string()),
    (
      "cumulative_transferred_bytes",
      data.cumulative.transferred_bytes.to_string(),
    ),
    (
      "cumulative_uncertain_transfer_bytes",
      data.cumulative.uncertain_transfer_bytes.to_string(),
    ),
    ("peak_retention_bytes", data.peak_retention_bytes.to_string()),
    ("provision_transfer_bytes", data.provision.transfer_bytes.to_string()),
    ("provision_retained_bytes", data.provision.retained_bytes.to_string()),
    ("provision_execution_bytes", data.provision.execution_bytes.to_string()),
    ("provision_open", data.provision.open.to_string()),
    ("provision_cleanup_pending", data.provision.cleanup_pending.to_string()),
    ("region_closing", data.region_closing.to_string()),
    (
      "read_use",
      match data.read_use {
        @resources.NotIssued => "not_issued"
        @resources.Pending => "pending"
        @resources.Closing => "closing"
        @resources.Retired => "retired"
      },
    ),
    ("final_observed", (data.final_usage is Some(_)).to_string()),
  ]
  for
    (name, text) in (match data.final_usage {
      None =>
        [
          ("final_planning_work", ""),
          ("final_attempts", ""),
          ("final_holdings", ""),
          ("final_transferred_bytes", ""),
          ("final_uncertain_transfer_bytes", ""),
          ("final_reserved_transfer_bytes", ""),
          ("final_held_bytes", ""),
          ("final_reserved_retention_bytes", ""),
          ("final_reserved_execution_bytes", ""),
          ("final_peak_retention_bytes", ""),
        ]
      Some(usage) =>
        [
          ("final_planning_work", usage.planning_work.to_string()),
          ("final_attempts", usage.attempts.to_string()),
          ("final_holdings", usage.holdings.to_string()),
          ("final_transferred_bytes", usage.transferred_bytes.to_string()),
          (
            "final_uncertain_transfer_bytes",
            usage.uncertain_transfer_bytes.to_string(),
          ),
          (
            "final_reserved_transfer_bytes",
            usage.reserved_transfer_bytes.to_string(),
          ),
          ("final_held_bytes", usage.held_bytes.to_string()),
          (
            "final_reserved_retention_bytes",
            usage.reserved_retention_bytes.to_string(),
          ),
          (
            "final_reserved_execution_bytes",
            usage.reserved_execution_bytes.to_string(),
          ),
          ("final_peak_retention_bytes", usage.peak_retention_bytes.to_string()),
        ]
    }) {
    fields.push((name, text))
  }
  fields.push(
    (
      "occupied_reserved_attempts",
      data.occupation.reserved_attempts.to_string(),
    ),
  )
  fields.push(
    (
      "occupied_live_reservations",
      data.occupation.live_reservations.to_string(),
    ),
  )
  fields.push(
    ("occupied_live_delegations", data.occupation.live_delegations.to_string()),
  )
  match data.final_usage {
    None => {
      fields.push(("final_reserved_attempts", ""))
      fields.push(("final_live_reservations", ""))
      fields.push(("final_live_delegations", ""))
    }
    Some(usage) => {
      fields.push(
        ("final_reserved_attempts", usage.reserved_attempts.to_string()),
      )
      fields.push(
        ("final_live_reservations", usage.live_reservations.to_string()),
      )
      fields.push(
        ("final_live_delegations", usage.live_delegations.to_string()),
      )
    }
  }
  client_local_original_record_body(fields)
}

///|
fn worker_resource_integer(text : String) -> Int64? {
  if text.is_empty() || text.length() > 19 {
    return None
  }
  // The existing scalar Owner checks Int64 range; this transport adds only
  // canonical nonnegative spelling, as in the existing Resource document codec.
  match @scalar.read_decimal_int64(text) {
    Ok(value) if value >= 0L && value.to_string() == text => Some(value)
    _ => None
  }
}

///|
/// Closed fields and the existing canonical codec reject extra/duplicate fields,
/// whitespace repairs, floats and leading zeros. Admission returns DATA only.
pub fn read_client_worker_resource_original(
  body : Bytes,
) -> Result[
  @resources.UnresolvedBackedExecutionOriginal,
  ClientLocalOriginalCodecIssue,
] {
  let fields = match
    client_local_original_record_fields(body, worker_resource_keys()) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let access = match fields[0] {
    "read_only" => @resources.ReadOnly
    "exclusive_write" => @resources.ExclusiveWrite
    _ => return Err(InvalidOriginal)
  }
  let numbers : Array[Int64] = []
  for i in 1..<21 {
    guard worker_resource_integer(fields[i]) is Some(value) else {
      return Err(InvalidOriginal)
    }
    numbers.push(value)
  }
  for i in [5, 6, 7, 11, 12, 13] {
    if numbers[i] > 2147483647L {
      return Err(InvalidOriginal)
    }
  }
  let flags : Array[Bool] = []
  for i in [21, 22, 23, 25] {
    match fields[i] {
      "true" => flags.push(true)
      "false" => flags.push(false)
      _ => return Err(InvalidOriginal)
    }
  }
  let read_use = match fields[24] {
    "not_issued" => @resources.NotIssued
    "pending" => @resources.Pending
    "closing" => @resources.Closing
    "retired" => @resources.Retired
    _ => return Err(InvalidOriginal)
  }
  let final_usage : @resources.LedgerUsage? = if flags[3] {
    let values : Array[Int64] = []
    for i in 26..<36 {
      guard worker_resource_integer(fields[i]) is Some(value) else {
        return Err(InvalidOriginal)
      }
      values.push(value)
    }
    for i in 39..<42 {
      guard worker_resource_integer(fields[i]) is Some(value) else {
        return Err(InvalidOriginal)
      }
      values.push(value)
    }
    for i in [0, 1, 2, 10, 11, 12] {
      if values[i] > 2147483647L {
        return Err(InvalidOriginal)
      }
    }
    Some({
      planning_work: values[0].to_int(),
      attempts: values[1].to_int(),
      holdings: values[2].to_int(),
      transferred_bytes: values[3],
      uncertain_transfer_bytes: values[4],
      reserved_transfer_bytes: values[5],
      held_bytes: values[6],
      reserved_retention_bytes: values[7],
      reserved_execution_bytes: values[8],
      peak_retention_bytes: values[9],
      reserved_attempts: values[10].to_int(),
      live_reservations: values[11].to_int(),
      live_delegations: values[12].to_int(),
    })
  } else {
    for i in [26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 39, 40, 41] {
      if fields[i] != "" {
        return Err(InvalidOriginal)
      }
    }
    None
  }
  let occupation : Array[Int] = []
  for i in 36..<39 {
    guard worker_resource_integer(fields[i]) is Some(value) &&
      value <= 2147483647L else {
      return Err(InvalidOriginal)
    }
    occupation.push(value.to_int())
  }
  let data : @resources.BackedExecutionOriginalData = {
    allocation_bytes: numbers[0],
    extent: {
      offset: numbers[1],
      length: numbers[2],
      payload_offset: numbers[3],
      payload_length: numbers[4],
    },
    access,
    limits: {
      planning_work: numbers[5].to_int(),
      attempts: numbers[6].to_int(),
      holdings: numbers[7].to_int(),
      transfer_bytes: numbers[8],
      retained_bytes: numbers[9],
      execution_bytes: numbers[10],
    },
    cumulative: {
      planning_work: numbers[11].to_int(),
      attempts: numbers[12].to_int(),
      transferred_bytes: numbers[14],
      uncertain_transfer_bytes: numbers[15],
    },
    occupation: {
      holdings: numbers[13].to_int(),
      reserved_attempts: occupation[0],
      live_reservations: occupation[1],
      live_delegations: occupation[2],
    },
    peak_retention_bytes: numbers[16],
    provision: {
      transfer_bytes: numbers[17],
      retained_bytes: numbers[18],
      execution_bytes: numbers[19],
      open: flags[0],
      cleanup_pending: flags[1],
    },
    region_closing: flags[2],
    read_use,
    final_usage,
  }
  @resources.admit_unresolved_backed_execution_data(data).map_err(_ => {
    InvalidOriginal
  })
}
