///|
priv enum LocalNativeMockSourceIdentityIssue {
  Read(@run_host.ClientModelReadPreparationIssue)
  Capture(@query.CapturedSourceIssue)
  Logical(@run_host.ClientCapturedSourceLogicalIssue)
  Observation(@row_host.RowHostIssue)
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
// Caller state on the original Model Read, not another resource or cleanup
// owner. Retain the Read before claiming its consumer, and every identity scan
// before advancing. A failed constructor leaves these same originals intact.
priv struct LocalNativeMockModelRead {
  read : @run_host.ClientModelReadPreparation
  mut consumer : @run_host.ClientModelReadConsumer?
  mut scan : @query.CapturedSourceCellIdentityScan?
  identities : Array[@query.CapturedSourceRelationIdentity]
  logicals : Array[@publication.RunEvidenceValue]
  observations : Array[@publication.RunEvidenceValue]
  mut retained : Int64
  mut execution : Int64
}

///|
// This record H1/R6/W2; six arrays for retained evidence, capture/original
// projections and real producer inputs; optional consumer/scan/result frames.
// Per producer: restricted read H1/R4/W1, narrowing closure H1/R2/W1,
// and the supplied-input enum H1/R1. No Source bytes are copied; the original
// physical captures keep their own backing and lifetime.
fn native_mock_model_read_controls(count : Int) -> Int64? {
  guard @execution.preparation_array_representation(1L, count.to_int64(), true)
    is Some(array) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: 7L + 3L * count.to_int64() + 6L * array.record_headers,
    reference_slots: 14L + 7L * count.to_int64() + 6L * array.reference_slots,
    scalar_words: 4L + 2L * count.to_int64() + 6L * array.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
fn LocalNativeMockModelRead::grow(
  self : Self,
  state : LocalNativeMockEffectPlan,
  retained : Int64,
  execution : Int64,
  original : LocalCommandPreparationOriginal,
) -> Unit raise ClientStop {
  let r = Int64::max(self.retained, retained)
  let e = Int64::max(self.execution, execution)
  guard self.consumer is Some(consumer) else {
    stop("LocalOriginalModelSourceIdentityUnavailable")
  }
  if r > self.retained || e > self.execution {
    @run_host.grow_client_model_read_preparing_capacity(
      self.read,
      consumer,
      state.first.model_compiled.unwrap(),
      state.first.definition,
      state.graph,
      r,
      e,
    )
    .map_err(issue => LocalNativeMockSourceIdentityIssue::Read(issue))
    .native_source_identity(original)
    self.retained = r
    self.execution = e
  }
  // Pure original caller identity after a grow callback, including covered
  // steps. A reentrant cleanup cannot replace or retire this construction.
  guard state.model_read is Some(same) && physical_equal(same, self) else {
    stop("LocalOriginalModelSourceIdentityUnavailable")
  }
}

///|
// Only the exact no-keyed checked graph enters this branch. The existing
// Source/Row issuers admit the original whole-input tuples; no request,
// synthetic ContentRef, provider observation or received rows are invented.
fn LocalCommandBusinessPreparation::prepare_mock_model_whole_source(
  self : LocalCommandBusinessPreparation,
  state : LocalNativeMockEffectPlan,
  held : LocalNativeMockModelRead,
  index : Int,
  observed_at : String,
) -> Unit raise ClientStop {
  let limits = state.first._retained_models[0]._retained_limits
  guard state.lookup is None &&
    index == held.identities.length() &&
    state.sources.get(index) is Some(capture) &&
    state.captured_inputs.get(index) is Some(input) &&
    @row_host.row_captured_input_source(input) is Some(source) &&
    state.input_originals.get(index) is Some((original, acquisition)) &&
    held.scan is None else {
    stop("LocalOriginalModelSourceIdentityUnavailable")
  }
  let controls = native_mock_model_read_controls(index + 1).unwrap_or_else(() => {
    stop("LocalOriginalModelSourceIdentityUnavailable")
  })
  // Reuse the closed-protocol construction quote. The existing logical codec
  // is bounded by 4096 bytes and the Source observation codec by 16384. Two
  // original evidence outputs, plus their array/projection controls, coexist
  // with the source identity scan; reserve before any of those constructors.
  let metadata = @run_host.client_protocol_metadata_construction_bytes(
      16384,
      2L,
      copies=2,
      extra_controls=controls,
    ).unwrap_or_else(() => stop("LocalOriginalModelSourceIdentityUnavailable")).0
  let basis_r = @execution.checked_preparation_add_product(
    held.retained,
    metadata,
    1L,
  ).unwrap_or_else(() => stop("LocalOriginalModelSourceIdentityUnavailable"))
  let basis_e = @execution.checked_preparation_add_product(
    held.execution,
    metadata,
    1L,
  ).unwrap_or_else(() => stop("LocalOriginalModelSourceIdentityUnavailable"))
  let grow_scan = (capacity : @execution.ExecutionCapacity) => {
    let r = @execution.checked_preparation_add_product(
      basis_r,
      @execution.execution_capacity_retained_bytes(capacity),
      1L,
    ).unwrap_or_else(() => stop("LocalOriginalModelSourceIdentityUnavailable"))
    let e = @execution.checked_preparation_add_product(
      basis_e,
      @execution.execution_capacity_execution_bytes(capacity),
      1L,
    ).unwrap_or_else(() => stop("LocalOriginalModelSourceIdentityUnavailable"))
    held.grow(state, r, e, self.original)
  }
  let start = @query.captured_source_cell_identity_start_capacity(source).unwrap_or_else(() => {
      stop("LocalOriginalModelSourceIdentityUnavailable")
    },
  )
  grow_scan(start)
  let scan = @query.start_captured_source_cell_identity(
      source,
      limits.identity.rows,
      limits.output_values,
      limits.identity.wire,
      limits.identity.logical_wire,
      limits.identity.schema,
      limits.identity.work,
      limits.identity.workspace,
      16777216,
    )
    .map_err(issue => LocalNativeMockSourceIdentityIssue::Capture(issue))
    .native_source_identity(self.original)
  held.scan = Some(scan)
  while true {
    let next = @query.captured_source_cell_identity_next_capacity(scan).unwrap_or_else(() => {
        stop("LocalOriginalModelSourceIdentityUnavailable")
      },
    )
    grow_scan(next)
    let (done, _) = @query.advance_captured_source_cell_identity(scan, 31, next)
      .map_err(issue => LocalNativeMockSourceIdentityIssue::Capture(issue))
      .native_source_identity(self.original)
    if done {
      break
    }
  }
  let identity = @query.finish_captured_source_cell_identity(scan)
    .map_err(issue => LocalNativeMockSourceIdentityIssue::Capture(issue))
    .native_source_identity(self.original)
  held.identities.push(identity)
  held.scan = None
  let graph = @strategy.checked_effect_computation_graph(
    @run_host.prepared_client_effect_computation_graph(state._retained_prepared),
  )
  let direct = @run_host.select_client_effect_direct_acquisition_occurrences(
    state._retained_prepared,
    limits.output_work,
  ).unwrap_or_else(() => stop("LocalOriginalModelSourceIdentityUnavailable"))
  let (_, _, task) = @run_host.client_direct_acquisition_occurrence_at(
    direct, index,
  ).unwrap_or_else(() => stop("LocalOriginalModelSourceIdentityUnavailable"))
  let logical = @run_host.issue_captured_whole_source_input_logical(
      graph,
      source,
      identity,
      original,
      task~,
    )
    .map_err(issue => LocalNativeMockSourceIdentityIssue::Logical(issue))
    .native_source_identity(self.original)
  held.logicals.push(logical)
  let captured = capture
    .capture()
    .unwrap_or_else(() => stop("LocalOriginalModelSourceIdentityUnavailable"))
  let facts = @row_host.row_input_acquisition_facts(acquisition)
  let observation = @row_host.issue_row_input_source_evidence(
      acquisition,
      captured,
      identity,
      logical,
      @run_host.client_request_authority_scope_cid(state.first.request),
      facts.source_data_policy_cid,
      observed_at,
    )
    .map_err(issue => LocalNativeMockSourceIdentityIssue::Observation(issue))
    .native_source_identity(self.original)
  held.observations.push(observation)
}
