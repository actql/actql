///|
pub(all) enum InstalledRelationSampleAdoptionIssue {
  SampleAdoptionOriginalUnavailable
  SampleAdoptionAuthorityLost
  SampleAdoptionLimits
  SampleAdoptionCapacity(@resources.LedgerIssue)
  SampleAdoptionReturn(@resources.LedgerIssue)
  SampleAdoptionWork(@resources.LedgerIssue)
  SampleAdoptionEncoding(@encode.EncodeFailure)
  SampleAdoptionEvidence(@publication.RunEvidenceValueIssue)
  SampleAdoptionVisitorRefused
}

///|
/// These originals and the resident Relation remain borrowed through the
/// synchronous Journal admission callback. Only the Journal can issue a
/// receipt or decide that adoption has committed.
pub struct InstalledRelationSampleAdoptionInput {
  source_generation : @publication.RunEvidenceValue
  capture : @publication.RunEvidenceValue
  emission : @publication.RunEvidenceValue
  reference : @publication.RunEvidenceValue
  relation : @encode.EncodedDocument
}

///|
fn installed_sample_adoption_construction(
  record_bytes : Int,
  prefix_nodes : Int,
  prefix_depth : Int,
) -> Int64? {
  guard @publication.run_evidence_admission_construction_inventory(
      record_bytes, 32, 4,
    )
    is Some(evidence) &&
    @encode.text_writer_construction_inventory(record_bytes, 32, 4)
    is Some(body) &&
    @encode.hash_writer_construction_inventory(prefix_nodes, prefix_depth)
    is Some(hash) else {
    return None
  }
  @execution.preparation_representation_cost({
    // Co-held bodies, four sealers (including their retained canonical
    // trees), the verbatim prefix hash, and the synchronous admission
    // frame, return latch, decimal strings and constructor results.
    record_headers: 4L * (evidence.record_headers + body.record_headers) +
    hash.record_headers +
    80L,
    reference_slots: 4L * (evidence.reference_slots + body.reference_slots) +
    hash.reference_slots +
    120L,
    scalar_words: 4L * (evidence.scalar_words + body.scalar_words) +
    hash.scalar_words +
    96L,
    owned_utf16_units: 4L *
    (evidence.owned_utf16_units + body.owned_utf16_units) +
    hash.owned_utf16_units +
    1024L,
    owned_wire_bytes: 4L * evidence.owned_wire_bytes + hash.owned_wire_bytes,
  })
}

///|
fn write_installed_sample_field(
  writer : @encode.Writer,
  name : String,
  value : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.key(writer, name)
  @encode.string_value(writer, value)
}

///|
fn write_installed_sample_run_ref(
  writer : @encode.Writer,
  profile : ClientCheckedRelationSampleProfile,
  namespace_id : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.key(writer, "run_ref")
  @encode.begin_object(writer)
  write_installed_sample_field(writer, "namespaceId", namespace_id)
  write_installed_sample_field(
    writer,
    "authorityScopeCid",
    @publication_host.client_request_authority_scope_cid(profile.request),
  )
  write_installed_sample_field(
    writer,
    "runDefinitionCid",
    @publication.publication_contract_identity(profile.definition),
  )
  @encode.end_object(writer)
}

///|
fn seal_installed_sample_evidence(
  name : String,
  version : String,
  bytes : Int,
  emit : (@encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Result[@publication.RunEvidenceValue, InstalledRelationSampleAdoptionIssue] {
  let wire = try {
    let writer = @encode.writer(bytes, 31, 4)
    @encode.begin_object(writer)
    write_installed_sample_field(writer, "version", version)
    emit(writer)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    issue => return Err(SampleAdoptionEncoding(issue))
  }
  @publication.seal_run_evidence_value(name, wire, bytes, 32, 4).map_err(issue => {
    SampleAdoptionEvidence(issue)
  })
}

///|
fn settle_installed_sample_adoption(
  ledger : @resources.Ledger,
  prefix : InstalledRelationSamplePrefix,
) -> Result[Unit, @resources.LedgerIssue] {
  guard prefix.adoption_reservation is Some(reservation) else { return Ok(()) }
  match @resources.settle_capacity(ledger, reservation) {
    Err(issue) => Err(issue)
    Ok(_) => {
      prefix.adoption_reservation = None
      Ok(())
    }
  }
}

///|
/// The visitor borrows the four records and the resident prefix only here.
/// Any durable or uncertain adoption must hold its own charged copy in the
/// Journal's custody. This boundary returns no evidence or visitor value.
pub fn with_installed_relation_sample_adoption(
  owner : ClientInstalledManagedRun,
  prefix : InstalledRelationSamplePrefix,
  require_capture_current : () -> Bool,
  adopt : (InstalledRelationSampleAdoptionInput, () -> Bool) -> Result[
    Unit,
    InstalledRelationSampleAdoptionIssue,
  ],
) -> Result[Unit, InstalledRelationSampleAdoptionIssue] {
  guard !prefix.adopting &&
    prefix.adoption_reservation is None &&
    prefix.original is Some(original) &&
    installed_relation_sample_profile_current(owner, original.profile) else {
    return Err(SampleAdoptionOriginalUnavailable)
  }
  // Prevent the same prefix from being recursively submitted by any of the
  // synchronous authority, reservation, or adoption callbacks.
  prefix.adopting = true
  defer {
    prefix.adopting = false
  }
  if !require_capture_current() {
    return Err(SampleAdoptionAuthorityLost)
  }
  let profile = original.profile
  guard installed_relation_sample_prefix_original(owner, prefix)
    is Some((_, _, _, _, document, _, _, _, _, _)) &&
    @publication.run_definition_namespace(profile.definition)
    is Some(namespace_id) else {
    return Err(SampleAdoptionOriginalUnavailable)
  }
  // One possibly escaped namespace_id and bounded CID/decimal fields per seal.
  // Count the full namespace_id independently of whether it needs escaping.
  let record_bound = 1024L + 6L * namespace_id.length().to_int64()
  let (prefix_bytes, prefix_nodes, prefix_depth) = @encode.document_usage(
    document,
  )
  guard record_bound <= 131072L &&
    installed_sample_adoption_construction(
      record_bound.to_int(),
      prefix_nodes,
      prefix_depth,
    )
    is Some(charge) else {
    return Err(SampleAdoptionLimits)
  }
  let ledger = @strategy.captured_dag_ledger(profile.captured)
  match @resources.reserve_capacity(ledger, charge, charge) {
    Err(issue) => return Err(SampleAdoptionCapacity(issue))
    Ok(reservation) => prefix.adoption_reservation = Some(reservation)
  }
  let result = visit_installed_relation_sample_adoption(
    owner,
    prefix,
    profile,
    record_bound.to_int(),
    namespace_id,
    prefix_bytes,
    require_capture_current,
    adopt,
  )
  // The visitor frame has unwound. If returning the capacity needs retry,
  // retain the actual reservation on this same prefix without replacing a
  // primary refusal or reporting any Journal acknowledgement.
  let returned = settle_installed_sample_adoption(ledger, prefix)
  match result {
    Err(issue) => Err(issue)
    Ok(_) => returned.map_err(issue => SampleAdoptionReturn(issue))
  }
}

///|
fn visit_installed_relation_sample_adoption(
  owner : ClientInstalledManagedRun,
  prefix : InstalledRelationSamplePrefix,
  profile : ClientCheckedRelationSampleProfile,
  bytes : Int,
  namespace_id : String,
  prefix_bytes : Int,
  require_capture_current : () -> Bool,
  adopt : (InstalledRelationSampleAdoptionInput, () -> Bool) -> Result[
    Unit,
    InstalledRelationSampleAdoptionIssue,
  ],
) -> Result[Unit, InstalledRelationSampleAdoptionIssue] {
  let ledger = @strategy.captured_dag_ledger(profile.captured)
  // Admission/check work is monotonic. A refusal before materialization
  // consumes no work for the four encoders or the prefix hash.
  match @resources.charge_planning(ledger, 1) {
    Err(issue) => return Err(SampleAdoptionWork(issue))
    Ok(_) => ()
  }
  if !require_capture_current() {
    return Err(SampleAdoptionAuthorityLost)
  }
  guard installed_relation_sample_prefix_original(owner, prefix)
    is Some(
      (
        retention,
        step_id,
        port_id,
        contract,
        document,
        items,
        total,
        generation,
        attempt,
        revision,
      )
    ) else {
    return Err(SampleAdoptionOriginalUnavailable)
  }
  let (_, prefix_nodes, prefix_depth) = @encode.document_usage(document)
  // For each closed record count text output, lexical/UTF-8 input and
  // canonical processing (including key comparisons, hash and final wire),
  // plus both generated schema walks at 8 visits/node. Hash the original
  // canonical Relation once. Cap the four actual record writers separately.
  let escaped_namespace = 6 * namespace_id.length()
  let reference_bytes = 640 + escaped_namespace
  let work = 8L * (bytes + 640 + 800 + reference_bytes).to_int64() +
    4L * 2L * 8L * 32L +
    prefix_bytes.to_int64()
  if work > 2147483647L {
    return Err(SampleAdoptionLimits)
  }
  match @resources.charge_planning(ledger, work.to_int()) {
    Err(issue) => return Err(SampleAdoptionWork(issue))
    Ok(_) => ()
  }
  guard installed_relation_sample_prefix_original(owner, prefix)
    is Some((_, _, _, _, current, _, _, _, _, _)) &&
    physical_equal(current, document) else {
    return Err(SampleAdoptionOriginalUnavailable)
  }
  let source_generation = match
    seal_installed_sample_evidence(
      "sample_source_generation",
      "actql-sample-source-generation/0.1",
      bytes,
      writer => {
        write_installed_sample_run_ref(writer, profile, namespace_id)
        let plan = @publication_host.client_compiled_run_plan(profile.compiled)
        write_installed_sample_field(
          writer,
          "compiled_plan_cid",
          @publication.publication_contract_identity(plan),
        )
        write_installed_sample_field(
          writer,
          "logical_map_cid",
          profile.logical_map_cid,
        )
        write_installed_sample_field(writer, "step_id", step_id)
        write_installed_sample_field(writer, "output_port_id", port_id)
        write_installed_sample_field(writer, "carrier", "relation")
        write_installed_sample_field(writer, "carrier_contract_cid", contract)
        @encode.key(writer, "producer_occurrence")
        @encode.begin_object(writer)
        write_installed_sample_field(writer, "kind", "first_physical_start")
        write_installed_sample_field(
          writer,
          "start_revision",
          revision.to_string(),
        )
        write_installed_sample_field(
          writer,
          "attempt_sequence",
          attempt.to_string(),
        )
        @encode.end_object(writer)
        write_installed_sample_field(
          writer,
          "committed_generation",
          generation.to_string(),
        )
      },
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let generation_cid = @publication.run_evidence_value_identity(
    source_generation,
  )
  let limits = retention.limits
  let capture = match
    seal_installed_sample_evidence(
      "sample_original_capture",
      "actql-sample-original-capture/0.1",
      640,
      writer => {
        write_installed_sample_field(
          writer, "source_generation_cid", generation_cid,
        )
        write_installed_sample_field(
          writer,
          "control_admission_cid",
          retention.control_admission_cid,
        )
        write_installed_sample_field(
          writer,
          "resolved_profile_cid",
          retention.resolved_profile_cid,
        )
        write_installed_sample_field(writer, "strategy", "execution_prefix")
        @encode.key(writer, "max_items")
        @encode.number_value(writer, limits.max_items.to_double())
        write_installed_sample_field(
          writer,
          "max_bytes",
          limits.max_bytes.to_string(),
        )
        @encode.key(writer, "max_artifacts")
        @encode.number_value(writer, limits.max_artifacts.to_double())
        @encode.key(writer, "ttl_seconds")
        @encode.number_value(writer, limits.ttl_seconds.to_double())
        @encode.key(writer, "required")
        @encode.bool_value(writer, limits.required)
      },
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let capture_cid = @publication.run_evidence_value_identity(capture)
  // The typed prefix emitter already emits canonical JSON, including every
  // admitted cell value. Hash those bytes without converting it to a row tree.
  let relation_cid = try {
    let hash = @encode.hashing_writer(prefix_bytes, prefix_nodes, prefix_depth)
    @encode.emit_document(hash, document)
    "sha256:" + @encode.finish_hash(hash)
  } catch {
    issue => return Err(SampleAdoptionEncoding(issue))
  }
  let emission = match
    seal_installed_sample_evidence(
      "sample_emission_provenance",
      "actql-sample-emission-provenance/0.1",
      800,
      writer => {
        write_installed_sample_field(
          writer, "original_capture_cid", capture_cid,
        )
        write_installed_sample_field(
          writer, "source_generation_cid", generation_cid,
        )
        write_installed_sample_field(
          writer, "relation_prefix_cid", relation_cid,
        )
        @encode.key(writer, "ordering_evidence_cid")
        @encode.null_value(writer)
        write_installed_sample_field(writer, "sampled_items", items.to_string())
        @encode.key(writer, "total")
        @encode.begin_object(writer)
        write_installed_sample_field(writer, "kind", "exact")
        write_installed_sample_field(writer, "value", total.to_string())
        write_installed_sample_field(writer, "unit", "rows")
        write_installed_sample_field(writer, "scope_cid", port_id)
        write_installed_sample_field(writer, "basis_cid", generation_cid)
        @encode.end_object(writer)
        write_installed_sample_field(
          writer,
          "completeness",
          if items == total {
            "complete"
          } else {
            "partial"
          },
        )
        write_installed_sample_field(
          writer,
          "truncation",
          if items == total {
            "not_truncated"
          } else {
            "confirmed"
          },
        )
      },
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let reference = match
    seal_installed_sample_evidence(
      "sample_reference",
      "actql-sample-reference/0.1",
      reference_bytes,
      writer => {
        write_installed_sample_run_ref(writer, profile, namespace_id)
        write_installed_sample_field(writer, "output_port_id", port_id)
        write_installed_sample_field(
          writer, "original_capture_cid", capture_cid,
        )
        write_installed_sample_field(
          writer,
          "emission_provenance_cid",
          @publication.run_evidence_value_identity(emission),
        )
      },
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  if !require_capture_current() {
    return Err(SampleAdoptionAuthorityLost)
  }
  if installed_relation_sample_prefix_original(owner, prefix) is None {
    return Err(SampleAdoptionOriginalUnavailable)
  }
  // Revocation clears the original references from this callable even if a
  // synchronous visitor retains it. It holds no sealed evidence or document.
  let current : Ref[(() -> Bool)?] = Ref(
    Some(() => {
      require_capture_current() &&
      installed_relation_sample_prefix_original(owner, prefix) is Some(_)
    }),
  )
  defer {
    current.val = None
  }
  adopt(
    { source_generation, capture, emission, reference, relation: document, },
    () => current.val is Some(require_current) && require_current(),
  )
}
