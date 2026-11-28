///|
// Size the fresh body's generated wire and the complete sealed value. Source
// text, the parser, canonical conversion, validators, hash and final writer
// have their own bounds. Only the final seal's tree, wire and CID escape.
fn portable_run_metadata_body_layout(
  geometry : @encode.EncodingConstructionGeometry,
  identity_key : String,
  normalize_units : Int64,
  definition~ : Bool,
) -> (Int64, Int64)? {
  guard @canonical.nfc_lf_retained_output_units(normalize_units)
    is Some(normalized) &&
    @execution.checked_preparation_add_product(
      geometry.bytes.to_int64() + identity_key.length().to_int64() + 77L,
      normalized,
      6L,
    )
    is Some(wire) else {
    return None
  }
  // The flat body adds at most one field. The caller keeps the original
  // parser limits even when this conservative output bound is larger.
  let bytes = Int64::min(wire, 100000L).to_int()
  let nodes = geometry.nodes + 1
  guard @publication.run_evidence_admission_construction_inventory(
      bytes,
      nodes,
      geometry.depth,
    )
    is Some(codec) &&
    @encode.text_writer_live_key_inventory(
      geometry.bytes,
      geometry.largest_object,
      geometry.depth,
    )
    is Some(emitter) else {
    return None
  }
  // Definition additionally constructs its closed field-rule specification.
  // Include both validation passes without counting them as retained values.
  let shape = if definition {
    match @publication.saved_run_definition_validation_construction(nodes) {
      Some(value) => value
      None => return None
    }
  } else {
    { record_headers: 0L, reference_slots: 0L, scalar_words: 0L, }
  }
  guard @execution.preparation_representation_cost({
      record_headers: codec.retained.record_headers + 1L,
      reference_slots: codec.retained.reference_slots + 1L,
      scalar_words: codec.retained.scalar_words + 1L,
      owned_utf16_units: codec.retained_utf16_units +
      identity_key.length().to_int64(),
      owned_wire_bytes: 0L,
    })
    is Some(held) &&
    @execution.preparation_representation_cost({
      record_headers: codec.record_headers +
      emitter.record_headers +
      2L * shape.record_headers,
      reference_slots: codec.reference_slots +
      emitter.reference_slots +
      2L * shape.reference_slots,
      scalar_words: codec.scalar_words +
      emitter.scalar_words +
      2L * shape.scalar_words,
      owned_utf16_units: codec.owned_utf16_units +
      emitter.owned_utf16_units +
      geometry.bytes.to_int64(),
      owned_wire_bytes: codec.owned_wire_bytes,
    })
    is Some(codec_peak) else {
    return None
  }
  // The save/restore inventory is conservative for fresh sealing but still
  // prices only its exact derived geometry. Carry the final seal separately.
  @execution.checked_preparation_add_product(held, codec_peak, 1L).map(peak => {
    (held, peak)
  })
}

///|
// Use only freshly issued flat metadata. The compiler's Plan and material
// are already held on the Request. Earlier sealed evidence stays live
// while the next writer, parser and seal are constructed in order.
fn portable_run_metadata_extents(
  artifact : @publication_host.ClientTaskCompilation,
  context : String,
  policy : String,
  scope_id : String,
  run_id : String,
  created_at : String,
  valid_until : String,
) -> (Int64, Int64, Int64)? {
  let measured = Ref(0L)
  let body_work = Some((units : Int) => {
    match
      @execution.checked_preparation_add_product(
        measured.val,
        units.to_int64(),
        1L,
      ) {
      None => false
      Some(next) => {
        measured.val = next
        true
      }
    }
  })
  let template = @publication_host.client_task_compilation_template(artifact)
  let plan = @publication_host.client_task_compilation_compiled_plan(artifact)
  guard @publication.measure_fresh_source_free_run_definition_body(
      template,
      plan,
      context,
      policy,
      scope_id,
      run_id,
      created_at,
      valid_until,
      body_work~,
    )
    is Ok(definition) &&
    @publication_host.measure_client_allowed_run_evidence_bodies(
      template,
      plan,
      context,
      policy,
      valid_until,
      100000,
      10000,
      100,
      body_work~,
    )
    is Ok((prepared, authorization)) &&
    portable_run_metadata_body_layout(
      prepared,
      "prepared_invocation_cid",
      0L,
      definition=false,
    )
    is Some((prepared_held, prepared_peak)) &&
    portable_run_metadata_body_layout(
      authorization,
      "run_authorization_cid",
      0L,
      definition=false,
    )
    is Some((authorization_held, authorization_peak)) &&
    portable_run_metadata_body_layout(
      definition,
      "run_definition_cid",
      scope_id.length().to_int64() + run_id.length().to_int64(),
      definition=true,
    )
    is Some((definition_held, definition_peak)) else {
    return None
  }
  // CompiledRun, RunPublicationAdmission, Definition binding and their
  // bounded read/return carriers. They borrow the exact checked inputs,
  // Plan and the three seals above. No Plan tree or restoration decoder.
  // Include the prospective quote's geometry, codecs and measuring frames.
  let work_control = @resources.preparation_phase_work_construction_inventory()
  guard @execution.preparation_representation_cost({
      record_headers: 76L + work_control.record_headers,
      reference_slots: 180L + work_control.reference_slots,
      scalar_words: 181L + work_control.scalar_words,
      owned_utf16_units: 256L,
      owned_wire_bytes: 128L,
    })
    is Some(controls) &&
    @execution.checked_preparation_add_product(
      prepared_held, authorization_held, 1L,
    )
    is Some(evidence_held) &&
    @execution.checked_preparation_add_product(controls, evidence_held, 1L)
    is Some(held) &&
    @execution.checked_preparation_add_product(held, definition_held, 1L)
    is Some(held) &&
    @execution.checked_preparation_add_product(
      prepared_held, authorization_peak, 1L,
    )
    is Some(with_authorization) &&
    @execution.checked_preparation_add_product(
      evidence_held, definition_peak, 1L,
    )
    is Some(with_definition) &&
    @execution.checked_preparation_add_product(
      controls,
      Int64::max(prepared_peak, Int64::max(with_authorization, with_definition)),
      1L,
    )
    is Some(peak) else {
    return None
  }
  // Finish of each text writer copies its bounded emitted bytes. Its
  // measuring counterpart counts the same pre-finish work but writes no text.
  @execution.checked_preparation_add_product(
    measured.val,
    prepared.bytes.to_int64() +
    authorization.bytes.to_int64() +
    definition.bytes.to_int64(),
    1L,
  ).map(work => (held, peak, work))
}

///|
priv struct PortableModelMetadataInputs {
  request : @publication_host.ClientRequestIdentity
  context : String
  policy : String
  scope_id : String
  run_id : String
  created_at : String
  valid_until : String
} derive(Eq)

///|
fn portable_run_metadata_measuring_bytes() -> Int64? {
  guard @encode.text_writer_live_key_inventory(0, 10, 1) is Some(writer) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: 3L * writer.record_headers + 35L,
    reference_slots: 3L * writer.reference_slots + 59L,
    scalar_words: 3L * writer.scalar_words + 82L,
    owned_utf16_units: 3L * writer.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
/// Fund fresh Portable metadata for this exact compiled Request. A declined
/// grow keeps the absolute target and its original Run inputs, without
/// exposing the compiler artifact or issuing any invocation or Definition.
/// The later constructor must still recheck and consume this exact selection.
pub fn[I] reserve_request_portable_model_run_metadata(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  context : String,
  policy : String,
  scope_id : String,
  run_id : String,
  created_at : String,
  valid_until : String,
) -> Result[Unit, ClientRequestProgramPlanIssue] {
  guard owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_compilation is Some(@publication_host.Tasks(artifact)) &&
    !owner.program_body_attempted else {
    return Err(Preparation(ForeignOriginal))
  }
  let identity = @publication_host.prepared_client_identity(prepared)
  guard @publication_host.client_request_program_cid(request) ==
    identity.program_definition_cid &&
    @publication_host.client_request_parameters_cid(request) ==
    identity.parameter_values_cid &&
    (
      owner.submitted_intent is None ||
      (
        owner.submitted_intent is Some(intent) &&
        @publication_host.client_request_input_cid(request) ==
        @publication_host.client_submitted_intent_cid(intent)
      )
    ) else {
    return Err(Preparation(ForeignOriginal))
  }
  let selection : PortableModelMetadataInputs = {
    request,
    context,
    policy,
    scope_id,
    run_id,
    created_at,
    valid_until,
  }
  let starting = owner.phase
  let selected_target = match starting {
    PortableModelArtifactReady => None
    PortableModelMetadataQuoted(previous, r, e, work) if physical_equal(
        previous.request,
        request,
      ) &&
      previous == selection => Some((r, e, work))
    _ => return Err(Preparation(ForeignOriginal))
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      let (r, e, work) = match selected_target {
        Some(target) => target
        None => {
          let (base_r, base_e) = match
            @resources.preparation_capacity_working_extents(capacity, input) {
            Ok(value) => value
            Err(issue) => return Err(Preparation(Capacity(issue)))
          }
          // These three measuring writers emit only a single flat object,
          // retain no output text and unwind before the quoted constructor.
          // Hold their frames, key tables and geometry/control carriers.
          guard portable_run_metadata_measuring_bytes() is Some(measurement) &&
            @execution.checked_preparation_add_product(base_r, measurement, 1L)
            is Some(scan_r) &&
            @execution.checked_preparation_add_product(base_e, measurement, 1L)
            is Some(scan_e) else {
            return Err(Preparation(Policy))
          }
          match
            @resources.reserve_working_preparation_phase(
              capacity, input, scan_r, scan_e,
            ) {
            Err(issue) => {
              owner.phase = starting
              return Err(Preparation(Capacity(issue)))
            }
            Ok(_) => ()
          }
          guard portable_run_metadata_extents(
              artifact, context, policy, scope_id, run_id, created_at, valid_until,
            )
            is Some((held, peak, work)) &&
            @execution.checked_preparation_add_product(scan_r, held, 1L)
            is Some(r) &&
            @execution.checked_preparation_add_product(scan_e, peak, 1L)
            is Some(e) else {
            return Err(Preparation(Policy))
          }
          (r, e, work)
        }
      }
      owner.program_invocation_quote = Some((r, e))
      let result = @resources.reserve_working_preparation_phase(
        capacity, input, r, e,
      )
      owner.phase = match result {
        Ok(_) => PortableModelMetadataReserved(selection, work)
        Err(_) => PortableModelMetadataQuoted(selection, r, e, work)
      }
      result.map_err(issue => Preparation(Capacity(issue)))
    },
    () => if owner.phase == Selecting { owner.phase = ProgramBodyFailed },
  )
}

///|
priv struct PortableModelRunOriginal {
  request : @publication_host.ClientRequestIdentity
  mut compiled : @publication_host.ClientCompiledRun
  definition : @publication.PublicationContract
  body_work : Int64
  mut materials_attempted : Bool
  mut materials : String?
  mut submission : @local_preparation.LocalSubmittedPreparation?
}

///|
impl Eq for PortableModelRunOriginal with fn equal(self, other) {
  physical_equal(self, other)
}

///|
pub suberror ClientRequestPortableModelMetadataIssue {
  MetadataPreparation(ClientRequestPreparationIssue)
  MetadataIssuance(@publication_host.ClientCompiledRunIssue)
}

///|
/// Issue the fresh metadata only from the reserved original and the admitted
/// submit decision. The compiled Run and Definition stay in this Request for
/// the durable admission owner. This does not publish rows or start a task.
pub fn[I] issue_request_portable_model_run_metadata(
  owner : ClientRequestPreparation[I],
  input : I,
  permit : @authorization.DispatchAuthorization,
  account : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
) -> Result[Unit, ClientRequestPortableModelMetadataIssue] {
  guard owner.phase is PortableModelMetadataReserved(selection, writer_work) &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_compilation is Some(@publication_host.Tasks(artifact)) &&
    !owner.program_body_attempted &&
    account.configuration_cid() == selection.policy &&
    tuple.resource == "run" &&
    tuple.operation == "submit" &&
    @authorization.dispatch_authorization_matches(
      permit,
      account,
      tuple,
      @authorization.Activation,
      @publication_host.prepared_client_identity(prepared).program_definition_cid,
      selection.context,
    ) else {
    return Err(MetadataPreparation(ForeignOriginal))
  }
  owner.phase = Selecting
  // Retire this exact receipt even on an unwinding constructor. A failed
  // constructor leaves the original reservation with normal Request cleanup.
  let active : Ref[@resources.PreparationPhaseWork64?] = Ref(None)
  preparation_module_call(
    () => {
      match
        @resources.check_working_preparation_capacity_current(capacity, input) {
        Err(issue) => return Err(MetadataPreparation(Capacity(issue)))
        Ok(_) => ()
      }
      let work = match
        @resources.begin_preparation_phase_work64(
          capacity,
          input,
          @resources.PublicationProof,
          writer_work,
        ) {
        Err(issue) => return Err(MetadataPreparation(Work(issue)))
        Ok(value) => value
      }
      active.val = Some(work)
      let body_work = Some((units : Int) => {
        @resources.spend_preparation_phase_work64(work, units.to_int64())
        is Ok(_)
      })
      let issued = @publication_host.issue_client_task_compiled_run(
        prepared,
        artifact,
        selection.context,
        selection.policy,
        selection.valid_until,
        body_work~,
      ).bind(compiled => {
        @publication_host.issue_client_compiled_run_definition(
          compiled,
          selection.scope_id,
          selection.run_id,
          selection.created_at,
          selection.valid_until,
          body_work~,
        ).map(definition => (compiled, definition))
      })
      let spent = match @resources.finish_preparation_phase_work64(work) {
        Err(issue) => return Err(MetadataPreparation(Work(issue)))
        Ok(value) => value
      }
      active.val = None
      let (compiled, definition) = match issued {
        Err(issue) => return Err(MetadataIssuance(issue))
        Ok(value) => value
      }
      let issued : PortableModelRunOriginal = {
        request: selection.request,
        compiled,
        definition,
        body_work: spent,
        materials_attempted: false,
        materials: None,
        submission: None,
      }
      if issued.body_work != writer_work {
        return Err(MetadataPreparation(Work(InvalidWork)))
      }
      // The Definition was just bound on this exact compiled owner. Recheck
      // that original binding before making it the Request's issued state.
      guard @publication_host.client_compiled_run_matches_tasks(
          issued.compiled,
          prepared,
          artifact,
        ) &&
        @publication_host.check_client_compiled_run_definition(
          issued.compiled,
          issued.definition,
        )
        is Ok(_) else {
        return Err(MetadataPreparation(ForeignOriginal))
      }
      match
        @resources.check_working_preparation_capacity_current(capacity, input) {
        Err(issue) => return Err(MetadataPreparation(Capacity(issue)))
        Ok(_) => ()
      }
      owner.phase = PortableModelMetadataIssued(issued)
      Ok(())
    },
    () => {
      if active.val is Some(work) {
        ignore(@resources.finish_preparation_phase_work64(work))
      }
      if owner.phase == Selecting {
        owner.phase = ProgramBodyFailed
      }
    },
  )
}

///|
/// Retain the exact warm materials on the same original Portable Request.
/// This uses the original compiler's source, parameters and Environment
/// with the existing funded serializer. No recheck, recompile, Store write
/// or second material owner is introduced here.
pub fn[I] prepare_request_portable_model_run_materials(
  owner : ClientRequestPreparation[I],
  input : I,
  result_policy : (String, String),
) -> Result[Unit, ClientRequestProgramPlanIssue] {
  guard owner.phase is PortableModelMetadataIssued(original) &&
    owner.input is Some(selected) &&
    physical_equal(selected, input) else {
    return Err(Preparation(ForeignOriginal))
  }
  if original.materials is Some(_) || original.materials_attempted {
    return Err(Preparation(WrongPhase))
  }
  // A partial encoder may already have grown the original reservation.
  // Keep it for ordinary cleanup rather than restart material construction.
  original.materials_attempted = true
  let intent = owner.submitted_intent
  let (authored_units, authored_scratch) = match intent {
    None => (0L, 0L)
    Some(intent) => {
      let wire = @publication_host.client_submitted_intent_wire(intent)
      guard request_retained_intent_limits(wire) is Some(limits) &&
        request_intent_construction_bytes(
          owner.snapshot_units,
          owner.snapshot_values,
          limits,
          captured=false,
        )
        is Some(scratch) else {
        return Err(Preparation(Policy))
      }
      (wire.length().to_int64(), scratch)
    }
  }
  // The policy-bound compiled record overlaps the previous nine-reference
  // record and its new Some wrapper. The callback and its compound return
  // also hold the adopted policy pair, compiled record and material wire.
  guard @execution.preparation_representation_cost({
      record_headers: 5L + (if intent is Some(_) { 12L } else { 0L }),
      reference_slots: 17L + (if intent is Some(_) { 29L } else { 0L }),
      scalar_words: 0L,
      owned_utf16_units: authored_units,
      owned_wire_bytes: 0L,
    })
    is Some(controls) else {
    return Err(Preparation(Policy))
  }
  match
    construct_request_model_run_materials_on_request(
      owner,
      input,
      original.compiled,
      retained_aliases=0L,
      extra_control_bytes=controls,
      extra_scratch_bytes=authored_scratch,
      fund => {
        guard owner.compiled_program is Some(prepared) else {
          return Err(Preparation(ForeignOriginal))
        }
        let compiled = if @publication_host.prepared_client_acquisition_count(
            prepared,
          ) ==
          0 {
          let (cid, wire) = result_policy
          // Fund the existing policy admission before parsing its closed object.
          if !fund("source_free_policy_read", wire.length(), 16, 4) {
            return Err(Preparation(Policy))
          }
          guard @publication_host.with_client_infer_result_policy(
              original.compiled,
              cid,
              wire,
              65536,
              8192,
              64,
            )
            is Ok(compiled) &&
            @publication_host.client_compiled_run_source_free_result_policy_body(
              compiled,
            )
            is Some(_) else {
            return Err(Preparation(Policy))
          }
          compiled
        } else {
          // A Source-backed compilation retains its checked contributing policy.
          guard @publication_host.client_compiled_run_infer_observation_policy(
              original.compiled,
            )
            is Some(_) else {
            return Err(Preparation(Policy))
          }
          original.compiled
        }
        let program_out = if intent is Some(_) { Some(Ref(None)) } else { None }
        let materials = match
          @publication_host.issue_original_client_infer_run_materials(
            compiled,
            original.definition,
            owner.native_parameters,
            fund,
            program_out~,
          ) {
          Ok(value) => value
          Err(issue) => return Err(InferMaterials(issue))
        }
        let submission = match intent {
          None => None
          Some(intent) => {
            guard program_out is Some(document) &&
              document.val is Some(document) else {
              return Err(Preparation(ForeignOriginal))
            }
            match
              @local_preparation.project_local_submitted_preparation(
                intent, prepared, document,
              ) {
              Ok(value) => Some(value)
              Err(_) => return Err(Preparation(Policy))
            }
          }
        }
        Ok((compiled, materials, submission))
      },
    ) {
    Err(issue) => Err(issue)
    Ok((compiled, materials, submission)) => {
      original.compiled = compiled
      original.materials = Some(materials)
      original.submission = submission
      Ok(())
    }
  }
}

///|
/// Forward the completed evidence on this same still-held Request. The
/// caller must retain the Request until all Run and Store children retire.
pub fn[I] request_portable_model_run_original(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  (
    @local_preparation.LocalSubmittedPreparation,
    @publication_host.ClientTaskCompilation,
    @publication_host.ClientCompiledRun,
    @publication.PublicationContract,
    String,
  ),
  ClientRequestPreparationIssue,
] {
  guard owner.phase is PortableModelMetadataIssued(original) &&
    physical_equal(original.request, request) &&
    owner.input is Some(selected) &&
    physical_equal(selected, input) &&
    owner.program_capacity is Some(capacity) &&
    owner.program_compilation is Some(@publication_host.Tasks(compilation)) &&
    owner.compiled_program is Some(prepared) &&
    original.materials is Some(materials) &&
    original.submission is Some(submission) &&
    @publication_host.client_compiled_run_matches_tasks(
      original.compiled,
      prepared,
      compilation,
    ) else {
    return Err(ForeignOriginal)
  }
  @resources.check_working_preparation_capacity_current(capacity, input)
  .map(_ => {
    (submission, compilation, original.compiled, original.definition, materials)
  })
  .map_err(issue => Capacity(issue))
}
