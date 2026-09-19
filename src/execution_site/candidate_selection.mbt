///|
/// Select a Site candidate by known duration and then by its stable key.
/// Negative return values are adapter-facing validation results, not durable
/// protocol state.
pub fn select_site_candidate_index(
  durations : Array[Int64],
  selection_keys : Array[String],
) -> Int {
  if durations.length() != selection_keys.length() {
    return -2
  }
  let mut selected = -1
  for index = 0; index < durations.length(); index = index + 1 {
    if durations[index] < 0L || selection_keys[index].length() == 0 {
      return -2
    }
    for prior = 0; prior < index; prior = prior + 1 {
      if selection_keys[prior] == selection_keys[index] {
        return -3
      }
    }
    if selected < 0 ||
      durations[index] < durations[selected] ||
      (
        durations[index] == durations[selected] &&
        selection_keys[index].lexical_compare(selection_keys[selected]) < 0
      ) {
      selected = index
    }
  }
  selected
}

///|
/// Adapter-facing result codes for pure Site candidate planning. The codes are
/// not persistent protocol state; they keep environment wrappers from
/// reimplementing applicability and duration rules.
pub(all) enum SiteCandidatePlanResult {
  SiteCandidateAccepted(Int64)
  SiteCandidateMissingDuration
  SiteCandidateCapacityExceeded
  SiteCandidateTransferUnsupported
  SiteCandidateTransferProviderMissing
  SiteCandidateSourceRevoked
  SiteCandidateTransferEstimateMissing
  SiteCandidateInvalid
} derive(Eq, Debug)

///|
/// Decide whether one implementation placement may enter common comparison.
/// The adapter supplies only observed placement and provider facts. This
/// function owns exclusion precedence, finite estimate validation, and the
/// duration charged once for each distinct physical Transfer.
pub fn plan_site_candidate(
  duration_milliseconds : Int64?,
  startup_milliseconds : Int64?,
  capacity_supported : Bool,
  accepts_site_transfer : Bool,
  transfer_provider_available : Bool,
  transfer_milliseconds : Int64?,
  transfer_required : Array[Bool],
  shared_transfer : Array[Bool],
  source_revoked : Array[Bool],
  estimate_available : Array[Bool],
  transfer_bytes : Array[Int64],
  retained_bytes : Array[Int64],
  execution_bytes : Array[Int64],
) -> SiteCandidatePlanResult {
  let length = transfer_required.length()
  if shared_transfer.length() != length ||
    source_revoked.length() != length ||
    estimate_available.length() != length ||
    transfer_bytes.length() != length ||
    retained_bytes.length() != length ||
    execution_bytes.length() != length {
    return SiteCandidateInvalid
  }
  guard duration_milliseconds is Some(duration) &&
    startup_milliseconds is Some(startup) else {
    return SiteCandidateMissingDuration
  }
  if duration < 0L || startup < 0L || duration > 9223372036854775807L - startup {
    return SiteCandidateInvalid
  }
  if !capacity_supported {
    return SiteCandidateCapacityExceeded
  }
  let mut total = duration + startup
  for index = 0; index < length; index = index + 1 {
    if !transfer_required[index] {
      if shared_transfer[index] ||
        source_revoked[index] ||
        estimate_available[index] ||
        transfer_bytes[index] != 0L ||
        retained_bytes[index] != 0L ||
        execution_bytes[index] != 0L {
        return SiteCandidateInvalid
      }
      continue
    }
    if !accepts_site_transfer {
      return SiteCandidateTransferUnsupported
    }
    if !transfer_provider_available {
      return SiteCandidateTransferProviderMissing
    }
    if source_revoked[index] {
      return SiteCandidateSourceRevoked
    }
    if !estimate_available[index] {
      return SiteCandidateTransferEstimateMissing
    }
    if transfer_bytes[index] < 0L ||
      retained_bytes[index] < 0L ||
      execution_bytes[index] < 0L {
      return SiteCandidateInvalid
    }
    if !shared_transfer[index] {
      guard transfer_milliseconds is Some(transfer_duration) else {
        return SiteCandidateMissingDuration
      }
      if transfer_duration < 0L ||
        total > 9223372036854775807L - transfer_duration {
        return SiteCandidateInvalid
      }
      total += transfer_duration
    }
  }
  SiteCandidateAccepted(total)
}

///|
/// Stable projection consumed by environment adapters.
pub fn site_candidate_plan_projection(
  result : SiteCandidatePlanResult,
) -> (Int, Int64) {
  match result {
    SiteCandidateAccepted(duration) => (0, duration)
    SiteCandidateMissingDuration => (1, 0L)
    SiteCandidateCapacityExceeded => (2, 0L)
    SiteCandidateTransferUnsupported => (3, 0L)
    SiteCandidateTransferProviderMissing => (4, 0L)
    SiteCandidateSourceRevoked => (5, 0L)
    SiteCandidateTransferEstimateMissing => (6, 0L)
    SiteCandidateInvalid => (7, 0L)
  }
}
