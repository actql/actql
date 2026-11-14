///|
/// One original Request continuation, not another issuer or Resource owner.
/// All fixed controls (including work-return closures) use the original 4096B
/// exclusive driver group; variable original/audit/journal data is quoted below.
priv struct ClientRequestProgramNormalization {
  original : @publication_host.PreparedClientProgram
  compiler : @publication_host.ClientProgramPreparationLimits
  limits : @publication_host.ClientLocalNormalizationLimits
  baseline : (Int64, Int64)
  audit_quote : (Int64, Int64)
  mut audit : @publication_host.ClientLocalNormalizationPreparation?
  mut retained : Int64?
  mut construction : @publication_host.ClientLocalNormalizationConstruction?
  mut publication_quote : (Int64, Int64, Int64)?
  mut work : @resources.PreparationPhaseWorkContinuation64?
  mut returned : Bool
  mut charged_work : Int64
  mut spent_work : Int64
  mut result : Result[
    @publication_host.ClientLocalNormalization,
    ClientRequestNormalizationIssue,
  ]?
}

///|
pub suberror ClientRequestNormalizationIssue {
  Preparation(ClientRequestPreparationIssue)
  Normalization(@publication_host.ClientLocalNormalizationIssue)
}

///|
/// Same original compiler policy; a maximum is not work consumed, an
/// allocation, a permission or an output row allowance. Explicit standalone
/// normalization retains its separate 10000/1024/32/8 contract unchanged.
pub fn[I] prepare_request_program_normalization(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[
  @publication_host.ClientLocalNormalization,
  ClientRequestNormalizationIssue,
] {
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(Preparation(ForeignOriginal))
  }
  guard owner.phase == ProgramCompiled &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_data is Some(data) &&
    owner.computation_limits is Some(compiler) else {
    return Err(Preparation(WrongPhase))
  }
  if owner.program_normalization is None &&
    @publication_host.prepared_client_local_normalization_original(prepared)
    is Some(cached) {
    match check_request_program_normalization_current(owner, input, capacity) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    match
      @publication_host.prepared_client_local_normalization_evidence(
        prepared, cached,
      ) {
      Err(issue) => return Err(Normalization(issue))
      Ok(evidence) => {
        let codec = compiler.checking.compilation.artifacts
        if !@publication.run_evidence_value_fits(
            evidence,
            codec.bytes,
            codec.nodes,
            codec.depth,
          ) {
          return Err(Normalization(Evidence(RunEvidenceInvalidWire)))
        }
        return Ok(cached)
      }
    }
  }
  if owner.program_normalization is None {
    // The fixed Request entrance backs these scalar/Option/quote controls
    // before any fallible current/grow callback. No variable wire exists yet.
    let base = match
      @resources.preparation_capacity_working_extents(capacity, input) {
      Err(issue) => return Err(Preparation(Capacity(issue)))
      Ok(value) => value
    }
    guard program_check_data_extent_cost(data) is Some(bytes) &&
      @execution.checked_preparation_add_product(base.0, bytes, 1L) is Some(r) &&
      @execution.checked_preparation_add_product(base.1, bytes, 1L) is Some(e) else {
      return Err(Preparation(Policy))
    }
    let codec = compiler.checking.compilation.artifacts
    owner.program_normalization = Some({
      original: prepared,
      compiler,
      limits: {
        max_work: compiler.checking.compilation.work,
        max_wire_bytes: codec.bytes,
        max_nodes: codec.nodes,
        max_depth: codec.depth,
      },
      baseline: base,
      audit_quote: (r, e),
      audit: None,
      retained: None,
      construction: None,
      publication_quote: None,
      work: None,
      returned: false,
      charged_work: 0L,
      spent_work: 0L,
      result: None,
    })
  }
  let selected = owner.program_normalization.unwrap()
  if !physical_equal(selected.original, prepared) ||
    !physical_equal(selected.compiler, compiler) {
    return Err(Preparation(ForeignOriginal))
  }
  if selected.result is Some(result) {
    if result is Ok(_) {
      match
        check_request_program_normalization_current(owner, input, capacity) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
    }
    return result
  }
  // This fence covers every capacity callback and original constructor.
  owner.phase = Selecting
  let result = prepare_request_program_normalization_owned(
    owner, input, selected, capacity,
  )
  owner.phase = ProgramCompiled
  result
}

///|
fn[I] prepare_request_program_normalization_owned(
  owner : ClientRequestPreparation[I],
  input : I,
  selected : ClientRequestProgramNormalization,
  capacity : @resources.PreparationCapacity[
    I,
    @publication_host.PreparedClientProgram,
  ],
) -> Result[
  @publication_host.ClientLocalNormalization,
  ClientRequestNormalizationIssue,
] {
  if selected.audit is None {
    match
      @resources.reserve_working_preparation_phase(
        capacity,
        input,
        selected.audit_quote.0,
        selected.audit_quote.1,
      ) {
      Err(issue) => return Err(Preparation(Capacity(issue)))
      Ok(_) => ()
    }
    let work = match
      @resources.begin_preparation_phase_work_continuation64(
        capacity,
        input,
        @resources.NormalizationAudit,
        selected.limits.max_work.to_int64(),
      ) {
      Err(issue) => return Err(Preparation(Work(issue)))
      Ok(value) => value
    }
    selected.work = Some(work)
    let (audit, known) = @publication_host.observe_prepare_client_local_normalization(
      selected.original,
      selected.limits,
    )
    selected.charged_work = known.to_int64()
    if audit is Ok(original) {
      // Retain before any current/Resource failure; never repeat this audit.
      selected.audit = Some(original)
    }
    let charged = @resources.spend_preparation_phase_work_continuation64(
      work,
      known.to_int64(),
    )
    if audit is Err(issue) {
      return fail_request_program_normalization(
        owner,
        selected,
        Normalization(issue),
      )
    }
    if charged is Err(issue) {
      return fail_request_program_normalization(
        owner,
        selected,
        Preparation(Work(issue)),
      )
    }
  }
  let audit = selected.audit.unwrap()
  let work = selected.work.unwrap()
  if selected.retained is None {
    guard @publication_host.client_local_normalization_retained_extent(audit)
      is Some((extent, text, inspected)) &&
      @execution.preparation_representation_cost({
        record_headers: extent.record_headers,
        reference_slots: extent.reference_slots,
        scalar_words: extent.scalar_words,
        owned_utf16_units: text,
        owned_wire_bytes: 0L,
      })
      is Some(retained) else {
      return fail_request_program_normalization(
        owner,
        selected,
        Preparation(Policy),
      )
    }
    selected.retained = Some(retained)
    selected.charged_work += inspected
    match
      @resources.spend_preparation_phase_work_continuation64(work, inspected) {
      Err(issue) =>
        return fail_request_program_normalization(
          owner,
          selected,
          Preparation(Work(issue)),
        )
      Ok(_) => ()
    }
  }
  let retained = selected.retained.unwrap()
  if selected.construction is None {
    if !selected.returned {
      match @resources.return_preparation_phase_work_continuation64(work) {
        Err(issue) =>
          return fail_request_program_normalization(
            owner,
            selected,
            Preparation(Work(issue)),
          )
        Ok(_) => selected.returned = true
      }
    }
    // Audit-only slot/collector/writer frames have returned. Its exact retained
    // array/text inventory stays beside the SAME compiler; no stop ACK is made.
    match
      @resources.reconcile_working_preparation_phase(
        capacity,
        input,
        selected.baseline.0 + retained,
        selected.baseline.1 + retained,
      ) {
      Err(issue) => return Err(Preparation(Capacity(issue)))
      Ok(_) => ()
    }
    match @resources.resume_preparation_phase_work_continuation64(work) {
      Err(issue) =>
        return fail_request_program_normalization(
          owner,
          selected,
          Preparation(Work(issue)),
        )
      Ok(_) => selected.returned = false
    }
    let construction = match
      @publication_host.measure_client_local_normalization_construction(audit) {
      Err(issue) =>
        return fail_request_program_normalization(
          owner,
          selected,
          Normalization(issue),
        )
      Ok(value) => value
    }
    selected.construction = Some(construction)
    // The SAME emitter's two measured metadata passes; this is a known
    // dimension of work, not a VM instruction count or policy-sized debit.
    let measured = construction.body.bytes.to_int64() +
      construction.body.nodes.to_int64() +
      construction.complete.bytes.to_int64() +
      construction.complete.nodes.to_int64()
    selected.charged_work += measured
    match
      @resources.spend_preparation_phase_work_continuation64(work, measured) {
      Err(issue) =>
        return fail_request_program_normalization(
          owner,
          selected,
          Preparation(Work(issue)),
        )
      Ok(_) => ()
    }
  }
  let construction = selected.construction.unwrap()
  if selected.publication_quote is None {
    guard request_normalization_publication_extents(construction)
      is Some((output, scratch)) &&
      @execution.checked_preparation_add_product(
        selected.baseline.0,
        retained,
        1L,
      )
      is Some(r) &&
      @execution.checked_preparation_add_product(r, output, 1L) is Some(r) &&
      @execution.checked_preparation_add_product(
        selected.baseline.1,
        retained,
        1L,
      )
      is Some(e) &&
      @execution.checked_preparation_add_product(e, output, 1L) is Some(e) &&
      @execution.checked_preparation_add_product(e, scratch, 1L) is Some(e) else {
      return fail_request_program_normalization(
        owner,
        selected,
        Preparation(Policy),
      )
    }
    selected.publication_quote = Some((r, e, scratch))
  }
  if !selected.returned {
    match @resources.return_preparation_phase_work_continuation64(work) {
      Err(issue) =>
        return fail_request_program_normalization(
          owner,
          selected,
          Preparation(Work(issue)),
        )
      Ok(_) => selected.returned = true
    }
  }
  let quote = selected.publication_quote.unwrap()
  match
    @resources.reserve_working_preparation_phase(
      capacity,
      input,
      quote.0,
      quote.1,
    ) {
    Err(issue) => return Err(Preparation(Capacity(issue)))
    Ok(_) => ()
  }
  match @resources.resume_preparation_phase_work_continuation64(work) {
    Err(issue) =>
      return fail_request_program_normalization(
        owner,
        selected,
        Preparation(Work(issue)),
      )
    Ok(_) => selected.returned = false
  }
  let emitted = construction.body.bytes.to_int64() * 4L
  // Keep the existing declared writer/UTF8/hash share BEFORE its constructor.
  match @resources.spend_preparation_phase_work_continuation64(work, emitted) {
    Err(issue) =>
      return fail_request_program_normalization(
        owner,
        selected,
        Preparation(Work(issue)),
      )
    Ok(_) => selected.charged_work += emitted
  }
  let result = @publication_host.finish_prepared_client_local_normalization(
    audit,
  ).map_err(issue => Normalization(issue))
  selected.result = Some(result)
  if result is Err(issue) {
    return fail_request_program_normalization(owner, selected, issue)
  }
  match finish_request_program_normalization_work(owner) {
    Err(issue) =>
      return fail_request_program_normalization(
        owner,
        selected,
        Preparation(issue),
      )
    Ok(_) => ()
  }
  // Only after the original sealer/writer frames returned. Its exact issued
  // evidence and audit remain retained through the existing Plan/Run lifetime.
  match
    @resources.reconcile_working_preparation_phase(
      capacity,
      input,
      quote.0,
      quote.1 - quote.2,
    ) {
    Err(issue) =>
      return fail_request_program_normalization(
        owner,
        selected,
        Preparation(Capacity(issue)),
      )
    Ok(_) => result
  }
}

///|
fn[I] fail_request_program_normalization(
  owner : ClientRequestPreparation[I],
  selected : ClientRequestProgramNormalization,
  primary : ClientRequestNormalizationIssue,
) -> Result[
  @publication_host.ClientLocalNormalization,
  ClientRequestNormalizationIssue,
] {
  selected.result = Some(Err(primary))
  // Preserve the actual primary. A failed work return remains attached to this
  // SAME Request and is closed by its existing after-cleanup retirement.
  ignore(finish_request_program_normalization_work(owner))
  Err(primary)
}

///|
fn[I] finish_request_program_normalization_work(
  owner : ClientRequestPreparation[I],
) -> Result[Unit, ClientRequestPreparationIssue] {
  if owner.program_normalization is Some(original) &&
    original.work is Some(work) {
    match @resources.finish_preparation_phase_work_continuation64(work) {
      Err(issue) => return Err(Work(issue))
      Ok(spent) => {
        original.spent_work = spent
        original.work = None
      }
    }
  }
  Ok(())
}

///|
/// Same original phase-budget DATA. Known charged dimensions and finished
/// receipt debit stay separate from policy maxima, CPU work and physical ACK.
/// Failed constructors retain a partial prefix, never a full failure claim.
pub fn[I] request_program_normalization_work(
  owner : ClientRequestPreparation[I],
  input : I,
) -> (Int64, Int64, Bool)? {
  guard owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_normalization is Some(state) else {
    return None
  }
  Some(
    (
      state.charged_work,
      state.spent_work,
      state.work is None && state.result is Some(Ok(_)),
    ),
  )
}

///|
// Immutable evidence may be reused without re-audit. The Request continuation
// still checks this SAME working capacity/current original, with reentry fenced
// before its callback. Retired/foreign/stopping owners cannot acquire it by
// retaining a copied successful result or an old Prepared normalization alias.
fn[I] check_request_program_normalization_current(
  owner : ClientRequestPreparation[I],
  input : I,
  capacity : @resources.PreparationCapacity[
    I,
    @publication_host.PreparedClientProgram,
  ],
) -> Result[Unit, ClientRequestNormalizationIssue] {
  owner.phase = Selecting
  let result = @resources.check_working_preparation_capacity_current(
    capacity, input,
  )
  owner.phase = ProgramCompiled
  result.map_err(issue => Preparation(Capacity(issue)))
}
