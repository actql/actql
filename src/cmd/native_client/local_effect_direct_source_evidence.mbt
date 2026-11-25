///|
// The Native caller keeps this reservation on the original managed Run until
// the publication consumer and the Source captures have released their aliases.
priv struct LocalNativeMockEffectDirectSources {
  ledger : @initial_resources.Ledger
  capacity : @initial_resources.CapacityReservation
  captures : Array[@query.CapturedInputSource]
  identities : Array[@query.CapturedSourceRelationIdentity]
  logicals : Array[@publication.RunEvidenceValue]
  observations : Array[@publication.RunEvidenceValue]
  mut scan : @query.CapturedSourceCellIdentityScan?
  mut _retained_publication : @run_host.ClientEffectDirectSourcesPublication?
  mut _retained_values_publication : @run_host.ClientEffectSourceFreeInvocationOriginal?
  mut retained : Int64
  mut reserved_r : Int64
  mut reserved_e : Int64
}

///|
fn LocalNativeMockEffectDirectSources::publication_originals(
  self : Self,
) -> (@publication.RunEvidenceValue, @publication.PublicationContract)? {
  match (self._retained_publication, self._retained_values_publication) {
    (Some(publication), None) =>
      Some(
        (
          @run_host.client_effect_direct_sources_publication_observation(
            publication,
          ),
          @run_host.client_effect_direct_sources_publication_invocation(
            publication,
          ),
        ),
      )
    (None, Some(publication)) =>
      Some(
        (
          @run_host.client_effect_source_free_invocation_original_observation(
            publication,
          ),
          @run_host.client_effect_source_free_invocation_original_invocation(
            publication,
          ),
        ),
      )
    _ => None
  }
}

///|
priv suberror LocalDirectSourceEvidenceStop {
  LocalDirectSourceEvidenceStop(LocalNativeMockSourceIdentityIssue)
}

///|
fn[T] direct_source_original(
  value : Result[T, LocalNativeMockSourceIdentityIssue],
) -> T raise LocalDirectSourceEvidenceStop {
  match value {
    Ok(original) => original
    Err(issue) => raise LocalDirectSourceEvidenceStop(issue)
  }
}

///|
fn LocalNativeMockEffectPlan::reserve_mock_effect_publication_metadata(
  self : Self,
  run : @local_values.ClientInstalledManagedRun,
  bytes : Int64,
) -> LocalNativeMockEffectDirectSources raise LocalDirectSourceEvidenceStop {
  guard self.direct_sources is None else {
    raise LocalDirectSourceEvidenceStop(Coverage)
  }
  let ledger = direct_source_original(
    @local_values.installed_effect_managed_sources_ledger(
      run,
      self._retained_prepared,
      self.first.request,
    ).map_err(issue => Installed(issue)),
  )
  let capacity = direct_source_original(
    @initial_resources.reserve_capacity(ledger, bytes, bytes).map_err(issue => {
      Ledger(issue)
    }),
  )
  let held : LocalNativeMockEffectDirectSources = {
    ledger,
    capacity,
    captures: [],
    identities: [],
    logicals: [],
    observations: [],
    scan: None,
    _retained_publication: None,
    _retained_values_publication: None,
    retained: bytes,
    reserved_r: bytes,
    reserved_e: bytes,
  }
  self.direct_sources = Some(held)
  held
}

///|
fn LocalNativeMockEffectDirectSources::grow(
  self : Self,
  next : @execution.ExecutionCapacity,
) -> Unit raise LocalDirectSourceEvidenceStop {
  guard @execution.checked_preparation_add_product(
      self.retained,
      @execution.execution_capacity_retained_bytes(next),
      1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(
      self.retained,
      @execution.execution_capacity_execution_bytes(next),
      1L,
    )
    is Some(e) else {
    raise LocalDirectSourceEvidenceStop(Coverage)
  }
  let r = Int64::max(self.reserved_r, r)
  let e = Int64::max(self.reserved_e, e)
  if r > self.reserved_r || e > self.reserved_e {
    direct_source_original(
      @initial_resources.grow_capacity_reservation(
        self.ledger,
        self.capacity,
        r,
        e,
      ).map_err(issue => Ledger(issue)),
    )
    self.reserved_r = r
    self.reserved_e = e
  }
}

///|
fn LocalNativeMockEffectDirectSources::identify(
  self : Self,
  source : @query.CapturedInputSource,
  bounds : @row_host.RowInputLimits,
) -> @query.CapturedSourceRelationIdentity raise LocalDirectSourceEvidenceStop {
  let wire = bounds.wire
  guard @query.captured_source_cell_identity_start_capacity(source)
    is Some(initial) &&
    @query.captured_source_cell_identity_workspace_slots(
      source,
      bounds.retention,
      wire,
      wire,
    )
    is Some(slots) else {
    raise LocalDirectSourceEvidenceStop(Coverage)
  }
  self.grow(initial)
  let scan = direct_source_original(
    @query.start_captured_source_cell_identity(
      source,
      bounds.max_rows,
      bounds.retention,
      wire,
      wire,
      {
        max_fields: wire.max_columns,
        max_bytes: wire.max_bytes,
        max_nodes: wire.max_nodes,
        max_depth: wire.max_depth,
      },
      bounds.retention.max_work,
      slots,
      wire.max_bytes,
    ).map_err(issue => Capture(issue)),
  )
  self.scan = Some(scan)
  while true {
    guard @query.captured_source_cell_identity_next_capacity(scan) is Some(next) else {
      raise LocalDirectSourceEvidenceStop(Coverage)
    }
    self.grow(next)
    let (done, _) = direct_source_original(
      @query.advance_captured_source_cell_identity(scan, 31, next).map_err(issue => {
        Capture(issue)
      }),
    )
    if done {
      break
    }
  }
  let identity = direct_source_original(
    @query.finish_captured_source_cell_identity(scan).map_err(issue => {
      Capture(issue)
    }),
  )
  self.scan = None
  self.identities.push(identity)
  guard @query.captured_source_relation_identity_retained_capacity(identity)
    is Some(capacity) &&
    @execution.checked_preparation_add_product(
      self.retained,
      @execution.execution_capacity_retained_bytes(capacity),
      1L,
    )
    is Some(retained) &&
    retained <= self.reserved_r &&
    retained <= self.reserved_e else {
    raise LocalDirectSourceEvidenceStop(Coverage)
  }
  self.retained = retained
  identity
}

///|
fn LocalNativeMockEffectPlan::issue_mock_effect_direct_sources(
  self : Self,
  run : @local_values.ClientInstalledManagedRun,
  bound : @run_host.PreparedClientEffectRun,
) -> Result[Unit, LocalNativeMockSourceIdentityIssue] {
  try {
    let count = self.captured_inputs.length()
    let first = self.first
    let prepared = self._retained_prepared
    let plan = self._retained_plan
    guard self.direct_sources is None &&
      first._retained_models.is_empty() &&
      count > 0 &&
      count <= 1024 &&
      count == self.sources.length() &&
      count == self.input_originals.length() &&
      self.effect_capture is Some(captured) &&
      self.source_started_at is Some(started) &&
      self.source_completed_at is Some(completed) &&
      @local_values.prepared_installed_effect_source_occurrences(
        plan,
        prepared,
        first.request,
      )
      is Ok(Some(occurrences)) &&
      @run_host.client_direct_acquisition_occurrence_count(occurrences) == count else {
      return Err(Coverage)
    }
    // Source logical and physical evidence, final observation and Invocation
    // coexist. Include returned arrays, the Common issuer's joined input view
    // and nominal wrappers, while the actual captured rows stay on their Reads.
    guard @execution.preparation_array_representation(
        8L,
        8L * count.to_int64(),
        true,
      )
      is Some(arrays) &&
      @execution.preparation_representation_cost({
        record_headers: 19L + arrays.record_headers + 4L * count.to_int64(),
        reference_slots: 44L + arrays.reference_slots + 8L * count.to_int64(),
        scalar_words: 20L + arrays.scalar_words + 4L * count.to_int64(),
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      })
      is Some(controls) &&
      @run_host.client_protocol_metadata_construction_bytes(
        16384,
        1024L,
        copies=2 * count + 2,
        extra_controls=controls,
      )
      is Some((metadata, _)) else {
      return Err(Coverage)
    }
    let held = self.reserve_mock_effect_publication_metadata(run, metadata)
    let scope = @run_host.client_request_authority_scope_cid(first.request)
    let graph = @strategy.captured_dag_graph(
      @strategy.captured_effect_run_dag(captured),
    )
    for index, input in self.captured_inputs {
      guard @row_host.row_captured_input_source(input) is Some(source) &&
        @run_host.client_direct_acquisition_occurrence_at(occurrences, index)
        is Some((_, _, task)) else {
        return Err(Coverage)
      }
      held.captures.push(source)
      let original = self.input_originals[index]
      let bounds = match original {
        WholeEffectInput(_, acquisition) =>
          @row_host.row_input_acquisition_limits(acquisition)
        QueryEffectInput(_) => {
          guard first._retained_sources[index]._retained_reader is Rows(binding) else {
            return Err(Coverage)
          }
          let page = binding.limits.page
          @local_values.installed_row_input_policy(
            page.max_rows,
            page.max_bytes,
            page.max_nodes,
            page.max_depth,
            page.max_rows,
          )
        }
      }
      let identity = held.identify(source, bounds)
      let logical = direct_source_original(
        (match original {
          WholeEffectInput(acquisition, _) =>
            @run_host.issue_captured_whole_source_input_logical(
              graph,
              source,
              identity,
              acquisition,
              task~,
            )
          QueryEffectInput(acquisition) =>
            @run_host.issue_captured_source_input_logical(
              graph,
              source,
              identity,
              @row_host.row_acquisition_requirement(acquisition),
              task~,
            )
        }).map_err(issue => Logical(issue)),
      )
      held.logicals.push(logical)
      guard self.sources[index].capture() is Ok(physical) else {
        return Err(Coverage)
      }
      let evidence = direct_source_original(
        (match original {
          WholeEffectInput(_, acquisition) => {
            let facts = @row_host.row_input_acquisition_facts(acquisition)
            @row_host.issue_row_input_source_evidence(
              acquisition,
              physical,
              identity,
              logical,
              scope,
              facts.source_data_policy_cid,
              completed,
            )
          }
          QueryEffectInput(acquisition) => {
            let requirement = @row_host.row_acquisition_requirement(acquisition)
            guard @planning.query_requirement_source_evidence_facts(requirement)
              is Some(facts) else {
              return Err(Coverage)
            }
            @row_host.issue_row_source_evidence(
              acquisition,
              physical,
              identity,
              logical,
              scope,
              facts.source_data_policy_cid,
              completed,
            )
          }
        }).map_err(issue => Observation(issue)),
      )
      held.observations.push(evidence)
    }
    guard @run_host.prepared_client_effect_publication_data_policy_cid(prepared)
      is Some(policy) else {
      return Err(Coverage)
    }
    direct_source_original(
      @local_values.begin_installed_effect_operation_controls(
        run,
        prepared,
        first.request,
        plan,
      ).map_err(issue => Installed(issue)),
    )
    |> ignore
    let publication = direct_source_original(
      @local_values.issue_installed_effect_direct_sources_invocation(
        run,
        prepared,
        first.request,
        plan,
        bound,
        captured,
        first.allowed.compilation,
        @run_host.client_effect_allowed_run_admission(first.allowed),
        first.definition,
        held.captures,
        held.identities,
        held.observations,
        held.logicals,
        scope,
        policy,
        started,
        completed,
        16384,
        1024,
        20,
      ).map_err(issue => Invocation(issue)),
    )
    held._retained_publication = Some(publication)
    Ok(())
  } catch {
    LocalDirectSourceEvidenceStop(issue) => Err(issue)
  }
}

///|
// The actual managed Run receives the Common no-external-source Observation
// Set. Its pinned compilation and same checked DAG must agree before binding.
fn LocalNativeMockEffectPlan::issue_mock_effect_values_publication(
  self : Self,
  run : @local_values.ClientInstalledManagedRun,
  bound : @run_host.PreparedClientEffectRun,
  installation : LocalRunInstallation,
) -> Result[Unit, LocalNativeMockSourceIdentityIssue] {
  let first = self.first
  let prepared = self._retained_prepared
  let plan = self._retained_plan
  guard first.is_mock_values_create() &&
    self.source_start is Some(_) &&
    self.captured_inputs.is_empty() &&
    self.effect_capture is Some(captured) &&
    installation.source_free is Some(values) &&
    @run_host.client_protocol_metadata_construction_bytes(
      16384,
      1024L,
      copies=2,
    )
    is Some((metadata, _)) else {
    return Err(Coverage)
  }
  try {
    let held = self.reserve_mock_effect_publication_metadata(run, metadata)
    direct_source_original(
      @local_values.begin_installed_effect_operation_controls(
        run,
        prepared,
        first.request,
        plan,
      ).map_err(issue => Installed(issue)),
    )
    |> ignore
    let original = direct_source_original(
      @run_host.issue_client_effect_source_free_invocation_original(
        first.allowed.compilation,
        values.result_policy_cid,
        16384,
        1024,
        20,
      ).map_err(issue => Invocation(PublicationInvocation(issue))),
    )
    held._retained_values_publication = Some(original)
    direct_source_original(
      @local_values.bind_installed_effect_source_free_invocation(
        run,
        prepared,
        first.request,
        plan,
        bound,
        captured,
        first.allowed.compilation,
        @run_host.client_effect_allowed_run_admission(first.allowed),
        first.definition,
        original,
      ).map_err(issue => Invocation(issue)),
    )
    |> ignore
    Ok(())
  } catch {
    LocalDirectSourceEvidenceStop(issue) => Err(issue)
  }
}

///|
fn LocalNativeMockEffectPlan::stop_mock_effect_direct_source_scan(
  self : Self,
) -> Bool {
  if self.direct_sources is Some(held) && held.scan is Some(scan) {
    if !@query.cancel_captured_source_cell_identity(scan) {
      return false
    }
    held.scan = None
  }
  true
}

///|
// Called after captured consumers and Common operation controls have retired.
fn LocalNativeMockEffectPlan::retire_mock_effect_direct_sources(
  self : Self,
) -> Result[Unit, LocalNativeMockSourceIdentityIssue] {
  guard self.direct_sources is Some(held) else { return Ok(()) }
  if held.scan is Some(_) {
    return Err(Coverage)
  }
  held._retained_publication = None
  held._retained_values_publication = None
  held.captures.clear()
  held.captures.shrink_to_fit()
  held.identities.clear()
  held.identities.shrink_to_fit()
  held.logicals.clear()
  held.logicals.shrink_to_fit()
  held.observations.clear()
  held.observations.shrink_to_fit()
  match @initial_resources.settle_capacity(held.ledger, held.capacity) {
    Err(issue) => Err(Ledger(issue))
    Ok(_) => {
      self.direct_sources = None
      Ok(())
    }
  }
}
