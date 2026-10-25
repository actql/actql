///|
/// One semantic phase owner quote. Failure is an alternative peak, not a second
/// concurrent arena. All components use the SAME representation tariff/Ledger.
struct ClosedValuesContextPhaseLayout {
  retained : PreparationRepresentationUnits
  temporary : PreparationRepresentationUnits
  failure : PreparationRepresentationUnits
}

///|
fn closed_values_context_fixed_source(
  bytes : Int,
  nodes : Int,
  objects : Int,
  arrays : Int,
  fields : Int,
  quoted : Int,
  text : Int,
  longest : Int,
  depth : Int,
) -> PreparationRepresentationUnits? {
  let owner = closed_values_source_inventories({
    input_bytes: bytes,
    node_upper: nodes,
    objects,
    arrays,
    fields_upper: fields,
    quoted_tokens: quoted,
    quoted_utf16_units: text,
    longest_quoted_utf16: longest,
    longest_atom_utf16: 25,
    depth_upper: depth,
  })
  // Conservatively preserve the complete private parsed tree too; shared
  // String dependencies occur only in source_retained, not indexed_additional.
  closed_values_sum_layouts([
    owner.source_retained,
    owner.indexed_additional,
    owner.source_growth_peak,
    owner.key_admission_peak,
    owner.parser_ancestry_peak,
    owner.decoder_ancestry_peak,
    owner.parser_controls_peak,
    owner.decoder_controls_peak,
  ])
}

///|
/// Core Context families only. Unit publication/sourceview components are
/// composed by the outer aggregate once their owner inventories are supplied.
fn closed_values_context_core_layout(
  facts : ClosedValuesLexicalFacts,
) -> ClosedValuesContextPhaseLayout? {
  if facts.node_upper < 1 || facts.fields_upper < 0 || facts.depth_upper < 0 {
    return None
  }
  let scaffold = @context.closed_values_context_scaffold_layout()
  guard @checked.closed_values_local_owner_layout(facts.depth_upper)
    is Some(local) &&
    @environment.closed_values_policy_owner_layout(3) is Some(policy) &&
    closed_values_normalization_layout(facts.fields_upper)
    is Some(normalization) &&
    closed_values_policy_writer_layout() is Some(policy_writers) &&
    closed_values_context_fixed_source(1436, 28, 1, 0, 27, 28, 675, 33, 1)
    is Some(capacity_source) &&
    closed_values_context_fixed_source(279, 7, 1, 0, 6, 7, 127, 31, 1)
    is Some(text_source) else {
    return None
  }
  // Required catalog wrapper1H4R2W; eligibility projection1H3W. Interpreted
  // catalog and installed Environment remain exact borrowed Root originals.
  let originals : PreparationRepresentationUnits = {
    record_headers: 2L,
    reference_slots: 4L,
    scalar_words: 5L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard closed_values_sum_layouts([
      originals,
      normalization.retained,
      {
        record_headers: scaffold.record_headers,
        reference_slots: scaffold.reference_slots,
        scalar_words: scaffold.scalar_words,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      {
        record_headers: local.record_headers,
        reference_slots: local.reference_slots,
        scalar_words: local.scalar_words,
        owned_utf16_units: local.owned_utf16_units,
        owned_wire_bytes: local.owned_wire_bytes,
      },
      {
        record_headers: policy.record_headers,
        reference_slots: policy.reference_slots,
        scalar_words: policy.scalar_words,
        owned_utf16_units: policy.owned_utf16_units,
        owned_wire_bytes: policy.owned_wire_bytes,
      },
    ])
    is Some(retained) else {
    return None
  }
  // Conservative first implementation keeps scaffold construction versions,
  // policy parse trees and scratch live in retained until phase retirement.
  // Actual reconciliation may narrow, never retroactively finance construction.
  guard closed_values_sum_layouts([
      capacity_source,
      text_source,
      normalization.temporary,
      policy_writers,
    ])
    is Some(temporary) else {
    return None
  }
  Some({ retained, temporary, failure: temporary, })
}

///|
/// Closed Values semantic Context aggregate. The caller has already bound facts
/// and dimensions to the SAME original guarded parsed input. Catalog reuse is
/// mandatory: failure of any installed-owner eligibility guard refuses this
/// optimization proof, never freshly interpreting a foreign catalog on credit.
/// All catalog semantic checks and original four replay limits still apply.
fn closed_values_context_phase_layout(
  facts : ClosedValuesLexicalFacts,
  fields : Int,
  rows : Int,
  required_catalog : @checked.PreparedSourceCatalog,
  catalog_scan_work : Int,
) -> ClosedValuesContextPhaseLayout? {
  if !@checked.source_catalog_requires_reuse(required_catalog) ||
    @checked.source_catalog_closed_values_dependencies(
      required_catalog, catalog_scan_work,
    )
    is None {
    return None
  }
  closed_values_context_components_layout(facts, fields, rows)
}

///|
/// Internal arithmetic projection used after the original-owner guards above.
/// Fixed contract closure15/32/24/22/8 is a prerequisite of this first route.
fn closed_values_context_components_layout(
  facts : ClosedValuesLexicalFacts,
  fields : Int,
  rows : Int,
) -> ClosedValuesContextPhaseLayout? {
  if fields < 1 ||
    rows < 0 ||
    facts.node_upper < 1 ||
    facts.depth_upper < 0 ||
    facts.node_upper > 2147483639 ||
    facts.depth_upper == 2147483647 ||
    facts.longest_quoted_utf16 < 0 {
    return None
  }
  guard closed_values_context_core_layout(facts) is Some(core) &&
    closed_values_identity_layout(
      facts.node_upper,
      facts.fields_upper,
      facts.depth_upper,
    )
    is Some(identity) &&
    closed_values_topology_layout() is Some(topology) &&
    closed_values_contract_layout() is Some(contracts) &&
    closed_values_graph_control_layout() is Some(graph) &&
    closed_values_operation_capacity_layout(fields) is Some(capacity) &&
    closed_values_empty_sourceview_layout() is Some(sourceview) &&
    closed_values_unit_publication_layout(facts.longest_quoted_utf16)
    is Some(publication) &&
    closed_values_identity_writer_layout(facts.node_upper, facts.depth_upper)
    is Some(identity_writers) &&
    closed_values_writer_layout(35, 3, 2, 0, 0) is Some(unit_writers) &&
    closed_values_operation_writer_layout(fields, rows)
    is Some(capacity_writers) else {
    return None
  }
  // Named retained objects plus intentionally conservative per-family staging
  // owners. Borrowed installed catalog/schema and compiler Values/ResultPort
  // are NOT counted here. Unit-publication payload is its replacement Unit,
  // distinct from the initial Unit record owned by the compiler component.
  guard closed_values_sum_layouts([
      core.retained,
      identity.fixed,
      identity.cid_strings,
      topology.retained,
      contracts.retained,
      graph.retained,
      capacity.retained,
      sourceview,
      publication.payload,
      // WireWitness Parsed(Cursor) survives Unit construction. Keep the whole
      // small generated source dependency under R, including conservative
      // parser scratch slack, until this original preparation retires. E below
      // deliberately retains its existing peak; no early release by GC claim.
      publication.source_admission,
    ])
    is Some(retained) else {
    return None
  }
  guard closed_values_sum_layouts([
      core.temporary,
      identity.preparation,
      identity.emission,
      topology.temporary,
      contracts.temporary,
      graph.temporary,
      capacity.temporary,
      publication.source_admission,
      publication.writers,
      identity_writers,
      unit_writers,
      capacity_writers,
    ])
    is Some(temporary) else {
    return None
  }
  // Failure carriers and their original source reachability remain under this
  // same phase. Caller selects max(success,failure), not an independent pool.
  Some({ retained, temporary, failure: temporary, })
}
