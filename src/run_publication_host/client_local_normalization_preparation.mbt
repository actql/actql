///|
/// Immutable codec/work policy selected by the original compiler caller.
/// These bounds grant no Resource, currentness, Run or publication authority.
pub(all) struct ClientLocalNormalizationLimits {
  max_work : Int
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
} derive(Eq, Debug)

///|
/// One completed original audit, retained before journal construction. Only
/// the original checked program can supply its entries and requirement closure.
struct ClientLocalNormalizationPreparation {
  owner : PreparedClientProgram
  inventory : @checked.LocalCommonNormalizationInventory
  limits : ClientLocalNormalizationLimits
}

///|
pub(all) struct ClientLocalNormalizationConstruction {
  body : @encode.EncodingConstructionGeometry
  complete : @encode.EncodingConstructionGeometry
}

///|
pub fn prepared_client_local_normalization_original(
  owner : PreparedClientProgram,
) -> ClientLocalNormalization? {
  owner.local_normalization
}

///|
/// Restore a saved journal against the SAME bounded original occurrence audit.
/// This reader never issues a replacement journal or normalizes the Program.
/// The caller funds the audit, saved evidence admission and comparison Writer
/// before entering; matching DATA does not grant execution or current authority.
pub fn admit_prepared_client_local_normalization(
  original : ClientLocalNormalizationPreparation,
  wire : String,
) -> Result[ClientLocalNormalization, ClientLocalNormalizationIssue] {
  let construction = match
    measure_client_local_normalization_construction(original) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  admit_measured_prepared_client_local_normalization(
    original, wire, construction,
  )
}

///|
/// The fixed funded reader supplies its SAME measured constructor dimensions.
/// These are allocation/refusal bounds, never journal evidence or admission.
/// All semantic correspondence still comes from the original audit below.
pub fn admit_measured_prepared_client_local_normalization(
  original : ClientLocalNormalizationPreparation,
  wire : String,
  construction : ClientLocalNormalizationConstruction,
) -> Result[ClientLocalNormalization, ClientLocalNormalizationIssue] {
  let owner = original.owner
  if !@checked.local_common_normalization_inventory_matches(
      original.inventory,
      @strategy.graph_program(owner.graph),
    ) {
    return Err(ForeignPreparation)
  }
  if owner.local_normalization is Some(cached) {
    return restore_prepared_client_local_normalization(
      owner,
      cached,
      wire,
      local_normalization_catalog_cid(cached.audit),
    ).map(_ => cached)
  }
  let limits = original.limits
  let shape = construction.complete
  if shape.bytes > limits.max_wire_bytes ||
    shape.nodes > limits.max_nodes ||
    shape.depth > limits.max_depth {
    return Err(Evidence(@publication.RunEvidenceInvalidLimits))
  }
  let evidence = match
    @publication.admit_run_evidence_value(
      "normalization_journal",
      wire,
      shape.bytes,
      shape.nodes,
      shape.depth,
    ) {
    Err(issue) => return Err(Evidence(issue))
    Ok(value) => value
  }
  // The saved identity is checked by its existing evidence Owner. Re-emitting
  // only the audited fields with that identity compares the complete saved
  // catalogue, paths, rules and authored/canonical pairs. No CID is reissued.
  let expected = try {
    let writer = @encode.writer(shape.bytes, shape.nodes, shape.depth)
    match
      emit_local_common_normalization_journal(
        original.inventory,
        writer,
        identity=Some(@publication.run_evidence_value_identity(evidence)),
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    @encode.finish(writer)
  } catch {
    _ => return Err(Evidence(@publication.RunEvidenceEncoding))
  }
  if expected != wire {
    return Err(SubstitutedJournal)
  }
  let restored : ClientLocalNormalization = {
    preparation: owner,
    audit: Common(original.inventory),
    evidence,
  }
  owner.local_normalization = Some(restored)
  Ok(restored)
}

///|
/// The same Common audit, once, with a known charged failure prefix. The
/// caller must fund its original constructor before entering this function.
pub fn observe_prepare_client_local_normalization(
  owner : PreparedClientProgram,
  limits : ClientLocalNormalizationLimits,
) -> (
  Result[ClientLocalNormalizationPreparation, ClientLocalNormalizationIssue],
  Int,
) {
  if limits.max_work < 0 ||
    limits.max_wire_bytes < 1 ||
    limits.max_nodes < 2 ||
    limits.max_depth < 1 {
    return (Err(CommonInventory(InvalidLimits)), 0)
  }
  let (result, work) = @checked.observe_local_program_common_normalization_inventory(
    @strategy.graph_program(owner.graph),
    limits.max_work,
  )
  (
    result
    .map(inventory => { owner, inventory, limits, })
    .map_err(issue => CommonInventory(issue)),
    work,
  )
}

///|
pub fn client_local_normalization_preparation_work(
  original : ClientLocalNormalizationPreparation,
) -> Int {
  @checked.local_common_normalization_inventory_work(original.inventory)
}

///|
/// Size the unchanged journal emitter from its SAME original retained strings.
/// The fixed registered CID's spelling sizes the appended field only; it is
/// never issued, retained as an identity, or supplied to the real sealer.
pub fn measure_client_local_normalization_construction(
  original : ClientLocalNormalizationPreparation,
) -> Result[ClientLocalNormalizationConstruction, ClientLocalNormalizationIssue] {
  if !@checked.local_common_normalization_inventory_matches(
      original.inventory,
      @strategy.graph_program(original.owner.graph),
    ) {
    return Err(ForeignPreparation)
  }
  let limits = original.limits
  try {
    let body = @encode.construction_measuring_writer(
      limits.max_wire_bytes,
      limits.max_nodes,
      Int::min(4, limits.max_depth),
    )
    match emit_local_common_normalization_journal(original.inventory, body) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let body = @encode.finish_construction_measurement(body)
    let complete = @encode.construction_measuring_writer(
      limits.max_wire_bytes,
      limits.max_nodes,
      Int::min(4, limits.max_depth),
    )
    match
      emit_local_common_normalization_journal(
        original.inventory,
        complete,
        identity=Some("sha256:" + "a".repeat(64)),
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let complete = @encode.finish_construction_measurement(complete)
    Ok({ body, complete, })
  } catch {
    _ => Err(Evidence(@publication.RunEvidenceEncoding))
  }
}

///|
/// Finish the SAME original audit using the existing body/preimage/sealer.
/// No fresh checker, normalization admission, rewritten tag or alternate CID
/// algorithm occurs. A cached original is returned only with its exact owner.
pub fn finish_prepared_client_local_normalization(
  original : ClientLocalNormalizationPreparation,
) -> Result[ClientLocalNormalization, ClientLocalNormalizationIssue] {
  let owner = original.owner
  if owner.local_normalization is Some(issued) {
    return match prepared_client_local_normalization_evidence(owner, issued) {
      Err(issue) => Err(issue)
      Ok(_) => Ok(issued)
    }
  }
  if !@checked.local_common_normalization_inventory_matches(
      original.inventory,
      @strategy.graph_program(owner.graph),
    ) {
    return Err(ForeignPreparation)
  }
  let limits = original.limits
  let remaining = (
      limits.max_work - client_local_normalization_preparation_work(original)
    ) /
    4
  let bytes = Int::min(limits.max_wire_bytes, remaining)
  let wire = local_common_normalization_journal_body(
    original.inventory,
    bytes,
    max_nodes=limits.max_nodes,
    max_depth=limits.max_depth,
    selected_wire_ceiling=limits.max_wire_bytes,
  )
  let wire = match wire {
    Err(issue) => return Err(issue)
    Ok(wire) => wire
  }
  if @utf8.encode(wire).length() > remaining {
    return Err(CommonInventory(BudgetExceeded))
  }
  let evidence = match
    @publication.seal_run_evidence_value(
      "normalization_journal",
      wire,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Err(issue) => return Err(Evidence(issue))
    Ok(value) => value
  }
  let issued : ClientLocalNormalization = {
    preparation: owner,
    audit: Common(original.inventory),
    evidence,
  }
  owner.local_normalization = Some(issued)
  Ok(issued)
}

///|
/// Original retained audit quantities, not a capacity grant or physical ACK.
pub fn client_local_normalization_retained_extent(
  original : ClientLocalNormalizationPreparation,
) -> (@shape.CollectionConstructionExtent, Int64, Int64)? {
  @checked.local_common_normalization_retained_extent(original.inventory)
}

///|
/// Cached original Source inventory length; no resolution, allocation or
/// permission is performed while selecting its construction allowance.
pub fn prepared_client_normalization_source_count(
  owner : PreparedClientProgram,
) -> Int64 {
  @checked.source_execution_count(@strategy.graph_program(owner.graph)).to_int64()
}

///|
/// Already retained compiler/source dimensions for the original audit's caller.
/// No checking, lowering, rule selection, wire projection or capacity is here.
pub fn prepared_client_normalization_audit_data(
  owner : PreparedClientProgram,
) -> (@lower.SequencePreparationDemand, Int64, Int) {
  let source = @decode.admission_preparation_data(
    @syntax.program_body(owner.source),
  )
  let original_nodes = @syntax.program_usage(owner.source).tree.nodes
  let structure = @syntax.program_preparation_data(owner.source)
  let nodes = if !structure.may_contain_expression_syntax &&
    structure.external_inputs == 0 &&
    structure.effect_members == 0 &&
    prepared_client_normalization_source_count(owner) == 0L {
    // The original syntax constructor already classified every step as Values.
    // The Common audit borrows their checked cells and retains no relation,
    // Source or expression entry. Its control/empty-slot frames are bounded by
    // these original structural occurrences, not by the number of literal rows.
    // Keep full source/text/Values retention at their existing Request owners;
    // this bound neither skips the real audit nor issues an empty journal.
    let controls = structure.operations.to_int64() +
      structure.results.to_int64() +
      1L
    Int64::min(controls, original_nodes.to_int64()).to_int()
  } else {
    original_nodes
  }
  (owner.sequence_preparation_demand, source.total_utf16, nodes)
}
