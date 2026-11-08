///|
priv enum LocalNativeMockSourceIdentityIssue {
  Read(@run_host.ClientModelReadPreparationIssue)
  Source(@query.CapturedSourceIssue)
  Capacity
  ForeignOriginal
}

///|
fn[T] Result::native_source_identity(
  self : Result[T, LocalNativeMockSourceIdentityIssue],
  original : LocalCommandPreparationOriginal,
) -> T raise ClientStop {
  match self {
    Ok(value) => value
    Err(issue) => {
      original.retain_primary(CommandBusinessSourceIdentity(issue))
      stop("LocalOriginalModelSourceIdentityUnavailable")
    }
  }
}

///|
// These are monotone actual constructor peaks on one original preparation.
// The existing Model basis and earlier Source peaks remain held. No ceiling,
// provider body maximum, second Read/consumer or physical ACK is invented.
fn LocalCommandBusinessPreparation::grow_mock_source_identity_read(
  self : LocalCommandBusinessPreparation,
  state : LocalNativeMockEffectPlan,
  read : @run_host.ClientModelReadPreparation,
  consumer : @run_host.ClientModelReadConsumer,
  compiled : @run_host.ClientCompiledRun,
  base_retained : Int64,
  base_execution : Int64,
  completed_retained : Int64,
  completed_execution : Int64,
  next_retained : Int64,
  next_execution : Int64,
  held_retained : Int64,
  held_execution : Int64,
) -> (Int64, Int64) raise ClientStop {
  let pending = state.source_identities.length().to_int64() + 1L
  // The actual growing original-identity reference array, including old/new
  // backing coexistence. No row/field/schema policy maximum allocates here.
  let controls = @execution.preparation_representation_cost({
    record_headers: 1L,
    reference_slots: 4L * pending,
    scalar_words: 2L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  if base_retained > 9223372036854775807L - completed_retained ||
    base_execution > 9223372036854775807L - completed_execution ||
    next_retained >
    9223372036854775807L - base_retained - completed_retained - controls ||
    next_execution >
    9223372036854775807L - base_execution - completed_execution - controls {
    Err(LocalNativeMockSourceIdentityIssue::Capacity).native_source_identity(
      self.original,
    )
  }
  let retained = Int64::max(
    held_retained,
    base_retained + completed_retained + next_retained + controls,
  )
  let execution = Int64::max(
    held_execution,
    base_execution + completed_execution + next_execution + controls,
  )
  if retained > held_retained || execution > held_execution {
    @run_host.grow_client_model_read_preparing_capacity(
      read,
      consumer,
      compiled,
      state.first.definition,
      state.graph,
      retained,
      execution,
    )
    .map_err(issue => LocalNativeMockSourceIdentityIssue::Read(issue))
    .native_source_identity(self.original)
  }
  // A current callback may retire the caller while Resource retains its
  // completed growth. Preserve that charge but construct nothing afterward.
  if !(state.model_read is Some(original) && physical_equal(original, read)) ||
    !(self.original.business is Some(business) &&
    business.effect_model is Some(original) &&
    physical_equal(original, state)) {
    Err(LocalNativeMockSourceIdentityIssue::ForeignOriginal).native_source_identity(
      self.original,
    )
  }
  (retained, execution)
}
