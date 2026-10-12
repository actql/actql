///|
/// The selected checked keyed occurrence's finite physical row envelope.
/// This is preflight only: it grants neither read authority nor completion.
struct RowKeyedCapacity {
  owner : @lower.BoundPrepared
  facts : @sourcequery.KeyedSourceFacts
  limits : RowKeyedLimits
  max_rows : Int
}

///|
fn valid_keyed_row_limits(limits : RowKeyedLimits) -> Bool {
  limits.page.max_bytes > 0 &&
  limits.page.max_rows > 0 &&
  limits.page.max_nodes > 0 &&
  limits.page.max_depth > 0 &&
  limits.wire.max_bytes >= 0 &&
  limits.wire.max_nodes >= 1 &&
  limits.wire.max_columns >= 0 &&
  limits.wire.max_order_work >= 0 &&
  limits.wire.max_depth >= 0 &&
  limits.retention.max_nodes >= 0 &&
  limits.retention.max_depth >= 0 &&
  limits.retention.max_text_bytes >= 0 &&
  limits.retention.max_work >= 0 &&
  limits.request.max_work >= 0 &&
  limits.request.max_pairs >= 0 &&
  limits.request.values.max_nodes >= 0 &&
  limits.request.values.max_depth >= 0 &&
  limits.request.values.max_text_bytes >= 0
}

///|
fn selected_keyed_row_capacity(
  owner : @lower.BoundPrepared,
  facts : @sourcequery.KeyedSourceFacts,
  declaration : RowDeclaration,
  limits : RowKeyedLimits,
) -> Result[RowKeyedCapacity, RowHostIssue] {
  guard @planning.keyed_source_evidence_facts(facts) is Some(source) &&
    row_declaration_view(declaration, source.source_ref) is Some(view) else {
    return Err(Source(UndeclaredSource))
  }
  let join = @sourcequery.keyed_source_join(facts)
  let input = @sourcequery.keyed_request_input(
    @sourcequery.parameterized_keyed_request(
      @sourcequery.keyed_join_request(join),
    ),
  )
  let selected = @sourcequery.declaration(input)
  if selected.connector != declaration.connector_id ||
    selected.resource != view.resource ||
    view.view_cid != source.source_contract_cid ||
    view.carrier_schema_cid != source.carrier_schema_contract_cid ||
    view.data_policy_cid != source.source_data_policy_cid {
    return Err(Source(UndeclaredSource))
  }
  let capacity = @sourcequery.keyed_source_capacity(facts)
  let rows = @environment.lookup_capacity_rows_per_key(capacity)
  if @environment.lookup_capacity_completeness(capacity) !=
    @environment.CompletePerRequestedKey {
    return Err(Source(KeyedIncomplete))
  }
  if rows <= 0L ||
    rows > 2147483647L ||
    limits.page.max_bytes.to_int64() >
    @environment.lookup_capacity_response_bytes_per_page(capacity) {
    return Err(Source(KeyedLimit("catalog_capacity")))
  }
  Ok({ owner, facts, limits, max_rows: rows.to_int(), })
}

///|
pub fn prepare_keyed_row_capacity(
  owner : @lower.BoundPrepared,
  facts : @sourcequery.KeyedSourceFacts,
  declaration : RowDeclaration,
  limits : RowKeyedLimits,
) -> Result[RowKeyedCapacity, RowHostIssue] {
  if !valid_keyed_row_limits(limits) {
    return Err(InvalidSpecification)
  }
  selected_keyed_row_capacity(owner, facts, declaration, limits)
}

///|
pub fn keyed_row_capacity_matches(
  capacity : RowKeyedCapacity,
  owner : @lower.BoundPrepared,
  facts : @sourcequery.KeyedSourceFacts,
) -> Bool {
  physical_equal(capacity.owner, owner) && physical_equal(capacity.facts, facts)
}

///|
/// Reused by actual RowRun reservation and preflight. Canonical wire budgets,
/// not an allocator/RSS claim; encoding and page workspaces may overlap.
fn keyed_row_reservation_capacity(limits : RowKeyedLimits) -> (Int64, Int64) {
  let retained = limits.wire.max_bytes.to_int64()
  (
    retained,
    retained +
    limits.page.max_bytes.to_int64() +
    limits.retention.max_text_bytes.to_int64() +
    limits.request.values.max_text_bytes.to_int64(),
  )
}

///|
pub fn keyed_row_capacity_bytes(capacity : RowKeyedCapacity) -> (Int64, Int64) {
  keyed_row_reservation_capacity(capacity.limits)
}

///|
pub fn keyed_row_capacity_target(
  capacity : RowKeyedCapacity,
  declaration : RowDeclaration,
) -> Result[(String, Array[String]), RowHostIssue] {
  guard @planning.keyed_source_evidence_facts(capacity.facts) is Some(source) &&
    row_declaration_view(declaration, source.source_ref) is Some(view) else {
    return Err(Source(UndeclaredSource))
  }
  let schema = match
    @query.keyed_response_port_schema(
      capacity.owner,
      @sourcequery.keyed_source_join(capacity.facts),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Source(KeyedOwner(issue)))
  }
  Ok(
    (
      view.resource,
      Array::makei(@schema.field_count(schema), i => {
        @schema.field_reference_name(@schema.field_at(schema, i).unwrap())
      }),
    ),
  )
}
