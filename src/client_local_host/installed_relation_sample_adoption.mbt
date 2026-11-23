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
    // Co-held typed bodies, four sealers (including their retained canonical
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
fn installed_sample_run_ref(
  profile : ClientCheckedRelationSampleProfile,
  namespace_id : String,
) -> Json {
  {
    "namespaceId": namespace_id,
    "authorityScopeCid": @publication_host.client_request_authority_scope_cid(
      profile.request,
    ),
    "runDefinitionCid": @publication.publication_contract_identity(
      profile.definition,
    ),
  }
}

///|
// Complete canonical record geometry, including the 71-byte self CID.
// Decimal strings cover their signed machine-width upper bounds, and
// profile numbers are safe integers (at most 16 decimal digits).
// Generation and reference separately add the escaped original namespace.
let installed_sample_generation_bytes = 992

///|
let installed_sample_capture_bytes = 600

///|
let installed_sample_emission_bytes = 791

///|
let installed_sample_reference_bytes = 629

///|
let installed_sample_generation_nodes = 18

///|
let installed_sample_capture_nodes = 12

///|
let installed_sample_emission_nodes = 16

///|
let installed_sample_reference_nodes = 10

///|
fn seal_installed_sample_evidence(
  name : String,
  body : Json,
  bytes : Int,
  nodes : Int,
  ledger : @resources.Ledger,
) -> Result[@publication.RunEvidenceValue, InstalledRelationSampleAdoptionIssue] {
  // The DATA keys are static ASCII. The byte bound pays two UTF-16 visits
  // for canonical admission, including key hashing. The fixed node charge
  // covers construction, ordered field insertion and both checked shapes.
  match @resources.charge_planning(ledger, 2 * bytes + 64 * nodes) {
    Err(issue) => return Err(SampleAdoptionWork(issue))
    Ok(_) => ()
  }
  let original = @identity.from_json(body, nodes - 1, 4, bytes, data_keys=true) catch {
    _ => return Err(SampleAdoptionEvidence(@publication.RunEvidenceInvalidWire))
  }
  let failed : Ref[@resources.LedgerIssue?] = Ref(None)
  let evidence = @publication.seal_typed_run_evidence_value(
    name,
    original,
    bytes,
    nodes,
    4,
    units => {
      match @resources.charge_planning(ledger, units) {
        Ok(_) => true
        Err(issue) => {
          failed.val = Some(issue)
          false
        }
      }
    },
  )
  match failed.val {
    Some(issue) => Err(SampleAdoptionWork(issue))
    None => evidence.map_err(issue => SampleAdoptionEvidence(issue))
  }
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
  let record_bound = installed_sample_generation_bytes.to_int64() +
    6L * namespace_id.length().to_int64()
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
  // Fund all fixed receipts and the borrowed prefix hash frame before
  // constructing their DATA. Each sealer also debits its own canonical work.
  let work = 2L * prefix_bytes.to_int64() + 256L
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
  let run_ref = installed_sample_run_ref(profile, namespace_id)
  let plan = @publication_host.client_compiled_run_plan(profile.compiled)
  let source_generation = match
    seal_installed_sample_evidence(
      "sample_source_generation",
      {
        "version": "actql-sample-source-generation/0.1",
        "run_ref": run_ref,
        "compiled_plan_cid": @publication.publication_contract_identity(plan),
        "logical_map_cid": profile.logical_map_cid,
        "step_id": step_id,
        "output_port_id": port_id,
        "carrier": "relation",
        "carrier_contract_cid": contract,
        "producer_occurrence": {
          "kind": "first_physical_start",
          "start_revision": revision.to_string(),
          "attempt_sequence": attempt.to_string(),
        },
        "committed_generation": generation.to_string(),
      },
      bytes,
      installed_sample_generation_nodes,
      ledger,
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
      {
        "version": "actql-sample-original-capture/0.1",
        "source_generation_cid": generation_cid,
        "control_admission_cid": retention.control_admission_cid,
        "resolved_profile_cid": retention.resolved_profile_cid,
        "strategy": "execution_prefix",
        "max_items": limits.max_items.to_double(),
        "max_bytes": limits.max_bytes.to_string(),
        "max_artifacts": limits.max_artifacts.to_double(),
        "ttl_seconds": limits.ttl_seconds.to_double(),
        "required": limits.required,
      },
      installed_sample_capture_bytes,
      installed_sample_capture_nodes,
      ledger,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let capture_cid = @publication.run_evidence_value_identity(capture)
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
      {
        "version": "actql-sample-emission-provenance/0.1",
        "original_capture_cid": capture_cid,
        "source_generation_cid": generation_cid,
        "relation_prefix_cid": relation_cid,
        "ordering_evidence_cid": Json::null(),
        "sampled_items": items.to_string(),
        "total": {
          "kind": "exact",
          "value": total.to_string(),
          "unit": "rows",
          "scope_cid": port_id,
          "basis_cid": generation_cid,
        },
        "completeness": if items == total {
          "complete"
        } else {
          "partial"
        },
        "truncation": if items == total {
          "not_truncated"
        } else {
          "confirmed"
        },
      },
      installed_sample_emission_bytes,
      installed_sample_emission_nodes,
      ledger,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let reference = match
    seal_installed_sample_evidence(
      "sample_reference",
      {
        "version": "actql-sample-reference/0.1",
        "run_ref": run_ref,
        "output_port_id": port_id,
        "original_capture_cid": capture_cid,
        "emission_provenance_cid": @publication.run_evidence_value_identity(
          emission,
        ),
      },
      installed_sample_reference_bytes + 6 * namespace_id.length(),
      installed_sample_reference_nodes,
      ledger,
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
