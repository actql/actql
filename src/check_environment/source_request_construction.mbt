///|
/// Counts for the SAME original Source request interpreter. This observes
/// quantities only: no schema/profile admission, response rows or authority.
/// Schema/Contract/String/tree backing remains with its original owners.
pub(all) struct SourceRequestConstructionGeometry {
  views : Int
  request_references : Int
  correlated_views : Int
  pairs : Int64
  identity_roles : Int64
  batching_views : Int
  listing_views : Int
  listing_limits : Int64
  content_views : Int
  max_view_map_fields : Int64
  distinct_facts : Int
  diagnostic_path_segments : Int
  inspection_work : Int64
} derive(Eq, Debug)

///|
priv struct RequestFactsConstructionGeometry {
  fields : Int
  listing : Int
  listing_fields : Int
  listing_limits : Int
  listing_capability_fields : Int
  content : Int
  content_fields : Int
  content_capability_fields : Int
}

///|
priv struct RequestQuantityScan {
  mut work : Int64
}

///|
// Read direct indexed fields without allocating an ObjectView/lookup Map or
// descending into arbitrary extension data. The original reader stays final.
fn request_quantity_child(
  root : @decode.Cursor,
  name : String,
  scan : RequestQuantityScan,
) -> @decode.Cursor? {
  scan.work += 1L
  if @decode.object_length(root) is Some(count) {
    for i in 0..<count {
      scan.work += 2L
      let (key, value) = @decode.field_at(root, i).unwrap()
      if key == name {
        return Some(value)
      }
    }
  }
  None
}

///|
fn request_quantity_fields(source : @decode.Cursor?) -> Int {
  source.map(value => @decode.object_length(value).unwrap_or(0)).unwrap_or(0)
}

///|
fn request_fact_quantities(
  root : @decode.Cursor,
  scan : RequestQuantityScan,
) -> RequestFactsConstructionGeometry {
  let listing = request_quantity_child(root, "file_listing", scan)
  let content = request_quantity_child(root, "file_content", scan)
  let mut limit_fields = 0
  let mut listing_capability = 0
  let mut content_capability = 0
  if listing is Some(profile) {
    // The same original list owns allowed field meaning. Unknown keys cannot
    // increase retained limit tuples: the actual reader refuses them first.
    let allowed = file_listing_allowed_fields()
    for i in 0..<@decode.object_length(profile).unwrap_or(0) {
      scan.work += 2L
      let (name, _) = @decode.field_at(profile, i).unwrap()
      if allowed.contains(name) &&
        (name.has_prefix("max_") || name == "maximum_path_length") {
        limit_fields += 1
      }
    }
    let fields = request_quantity_fields(
      request_quantity_child(profile, "version_capability", scan),
    )
    if fields == file_version_capability_fields() {
      listing_capability = fields
    }
  }
  let mut content_fields = 0
  if content is Some(profile) &&
    @decode.object_length(profile) == Some(file_content_profile_fields()) {
    content_fields = file_content_profile_fields()
    let fields = request_quantity_fields(
      request_quantity_child(profile, "version_capability", scan),
    )
    if fields == file_version_capability_fields() {
      content_capability = fields
    }
  }
  {
    fields: @decode.object_length(root).unwrap_or(0),
    listing: if listing is Some(_) {
      1
    } else {
      0
    },
    listing_fields: request_quantity_fields(listing),
    listing_limits: limit_fields,
    listing_capability_fields: listing_capability,
    content: if content is Some(_) {
      1
    } else {
      0
    },
    content_fields,
    content_capability_fields: content_capability,
  }
}

///|
/// Fund the metadata frame and bounded per-original facts Map BEFORE entry.
/// Repeated views share one facts-quantity observation by the same registry's
/// immutable CID; the Map returns with this frame, not a persistent cache or
/// a transferable proof. Actual interpretation still runs on each view.
pub fn observe_source_request_construction_geometry(
  carriers : CarrierSchemas,
) -> SourceRequestConstructionGeometry {
  let refs = carriers.modes.shapes.values.policies.references
  let scan : RequestQuantityScan = { work: 1L, }
  let facts : Map[String, RequestFactsConstructionGeometry] = Map([])
  let mut request_references = 0
  let mut correlated = 0
  let mut pairs = 0L
  let mut identity = 0L
  let mut batching = 0
  let mut listing = 0
  let mut limits = 0L
  let mut content = 0
  let mut maps = 0L
  for reference in refs.references {
    scan.work += 1L
    if reference.contract.kind == "request_schema" {
      request_references += 1
    }
  }
  for view in carriers.modes.views {
    scan.work += 1L
    let root = member_body(view.item)
    let acquisition = request_quantity_child(root, "acquisition", scan).unwrap()
    let correlation_source = request_quantity_child(
      acquisition, "correlation", scan,
    )
    if correlation_source is Some(correlation) {
      correlated += 1
      if request_quantity_child(correlation, "request_fields", scan)
        is Some(roles) {
        pairs += @decode.array_length(roles).unwrap_or(0).to_int64()
      }
      if request_quantity_child(correlation, "identity", scan) is Some(roles) {
        identity += @decode.array_length(roles).unwrap_or(0).to_int64()
      }
    }
    let batching_source = request_quantity_child(acquisition, "batching", scan)
    if batching_source is Some(_) {
      batching += 1
    }
    let output = request_quantity_child(root, "output", scan).unwrap()
    let slot = request_quantity_child(output, "facts", scan).unwrap()
    let envelope = catalog_reference_for_cursor(refs, slot).unwrap().contract
    let geometry = match facts.get(envelope.cid) {
      Some(original) => original
      None => {
        let original = request_fact_quantities(envelope.body, scan)
        facts[envelope.cid] = original
        original
      }
    }
    listing += geometry.listing
    limits += geometry.listing_limits.to_int64()
    content += geometry.content
    let schema = request_quantity_child(output, "schema", scan).unwrap()
    // The same outer root/acquisition survive each sequential helper. Facts
    // extensions contribute their actual shallow Map fields, never their
    // arbitrary nested bodies. A malformed closed Content/capability record
    // refuses before constructing its own Map; the original reader's sizes
    // above select that same construction path without changing acceptance.
    let outer = @decode.object_length(root).unwrap_or(0).to_int64() +
      @decode.object_length(acquisition).unwrap_or(0).to_int64()
    let common = @decode.object_length(root).unwrap_or(0).to_int64() +
      @decode.object_length(output).unwrap_or(0).to_int64() +
      @decode.object_length(slot).unwrap_or(0).to_int64() +
      geometry.fields.to_int64()
    let listing_fields = common +
      geometry.listing_fields.to_int64() +
      geometry.listing_capability_fields.to_int64() +
      (if geometry.listing == 1 {
        @decode.object_length(schema).unwrap_or(0).to_int64()
      } else {
        0L
      })
    let content_fields = common +
      geometry.content_fields.to_int64() +
      geometry.content_capability_fields.to_int64() +
      (if geometry.content_fields != 0 {
        @decode.object_length(schema).unwrap_or(0).to_int64() +
        @decode.object_length(acquisition).unwrap_or(0).to_int64()
      } else {
        0L
      })
    let correlation_fields = request_quantity_fields(correlation_source).to_int64()
    let batching_fields = request_quantity_fields(batching_source).to_int64()
    let fields = outer +
      Int64::max(
        Int64::max(listing_fields, content_fields),
        Int64::max(correlation_fields, batching_fields),
      )
    maps = Int64::max(maps, fields)
  }
  {
    views: carriers.modes.views.length(),
    request_references,
    correlated_views: correlated,
    pairs,
    identity_roles: identity,
    batching_views: batching,
    listing_views: listing,
    listing_limits: limits,
    content_views: content,
    max_view_map_fields: maps,
    distinct_facts: facts.length(),
    diagnostic_path_segments: @decode.admission_usage(
      refs.contents.registry.environment.root,
    ).depth,
    inspection_work: scan.work,
  }
}

///|
// Representation bounds of the original indexed tree/arrays, not a policy
// limit or an accepted request. The observer's own counts satisfy these before
// arithmetic; supplied quantity DATA cannot wrap into a smaller quotation.
fn source_request_geometry_fits(g : SourceRequestConstructionGeometry) -> Bool {
  g.views >= 0 &&
  g.request_references >= 0 &&
  g.correlated_views >= 0 &&
  g.correlated_views <= g.views &&
  g.batching_views >= 0 &&
  g.batching_views <= g.views &&
  g.listing_views >= 0 &&
  g.listing_views <= g.views &&
  g.content_views >= 0 &&
  g.content_views <= g.views &&
  g.distinct_facts >= 0 &&
  g.distinct_facts <= g.views &&
  g.pairs >= 0L &&
  g.pairs <= 2147483647L &&
  g.identity_roles >= 0L &&
  g.identity_roles <= 2147483647L &&
  g.listing_limits >= 0L &&
  g.listing_limits <= 7L * g.listing_views.to_int64() &&
  g.max_view_map_fields >= 0L &&
  g.max_view_map_fields <= 10L * 2147483647L &&
  g.diagnostic_path_segments >= 0
}

///|
/// All original request views coexist. Each view owns its new Schema wrapper,
/// correlation/optional-profile records and role arrays, while borrowing every
/// original Contract, name, CID and indexed tree. by_view aliases the SAME view.
pub fn source_request_retained_construction_extent(
  g : SourceRequestConstructionGeometry,
) -> RegistryConstructionExtent? {
  if !source_request_geometry_fits(g) {
    return None
  }
  let v = g.views.to_int64()
  let c = g.correlated_views.to_int64()
  let p = g.pairs
  let i = g.identity_roles
  let roles = 2L * p + i
  let b = g.batching_views.to_int64()
  let l = g.listing_views.to_int64()
  let k = g.listing_limits
  let t = g.content_views.to_int64()
  let optional = c + b + l + t
  // SourceRequestContracts/Ok2H4R3W; view1H3R and its four optional
  // positions; Correlation/Some/source-Cursor3H6R3W, pair1H2R,
  // role+source-Cursor2H5R1W; batching3H6R3W plus two borrowed arrays;
  // listing3H6R5W +limit tuples1H1R1W; Content3H7R2W.
  guard @shape.collection_construction_extent({
      records: 2L + v + 3L * c + p + 2L * roles + 3L * b + 3L * l + k + 3L * t,
      record_references: 4L +
      3L * v +
      optional +
      6L * c +
      2L * p +
      5L * roles +
      6L * b +
      6L * l +
      k +
      7L * t,
      record_words: 3L +
      4L * v -
      optional +
      3L * c +
      roles +
      3L * b +
      5L * l +
      k +
      2L * t,
      reference_arrays: 1L + 2L * c + 2L * b + l,
      reference_items: v + p + i + 6L * b + k,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: v,
    })
    is Some(views) &&
    @row.from_object_construction_extent(g.views) is Some(schemas) &&
    @shape.add_collection_construction_extents(views, schemas) is Some(held) else {
    return None
  }
  Some(carrier_units(held))
}

///|
/// The same interpreter's transient request-reference Map, ten simultaneous
/// ObjectViews and current indexed/lookup/error carriers return before the next
/// phase. Per-view scratch reuses one frame, not all historical view peaks.
pub fn source_request_construction_extent(
  g : SourceRequestConstructionGeometry,
) -> RegistryConstructionExtent? {
  guard source_request_retained_construction_extent(g) is Some(held) else {
    return None
  }
  let child = @decode.indexed_child_construction_extent()
  let field = @decode.indexed_field_construction_extent()
  let active = if g.views == 0 { 0L } else { 1L }
  // At most twelve current child/control results and four field results;
  // fixed8H8R12W owns Budget/Limits/typed alternatives/observer tuple.
  // ObjectViews10H20R accompany their original Maps. The listing allow/role
  // arrays have15+2+7 slots; two Map([]) input arrays are empty. Correlation's
  // three role-count scalars occur sequentially, conservatively co-counted.
  // No view means none of those readers or decoder diagnostics can execute.
  guard @shape.collection_construction_extent({
      records: 8L +
      active * (10L + 12L * child.record_headers + 4L * field.record_headers),
      record_references: 8L +
      active * (20L + 12L * child.reference_slots + 4L * field.reference_slots),
      record_words: 12L +
      active * (12L * child.scalar_words + 4L * field.scalar_words),
      reference_arrays: 2L + 3L * active,
      reference_items: 24L * active,
      scalar_arrays: active,
      scalar_items: 3L * active,
      maps: 1L + 10L * active,
      map_entries: g.request_references.to_int64() + g.max_view_map_fields,
    })
    is Some(frame) else {
    return None
  }
  let issue : @shape.CollectionConstructionExtent = if g.views == 0 {
    { record_headers: 0L, reference_slots: 0L, scalar_words: 0L, }
  } else {
    @decode.issue_construction_extent(g.diagnostic_path_segments).unwrap()
  }
  let lookup : @shape.CollectionConstructionExtent = if g.content_views == 0 {
    { record_headers: 0L, reference_slots: 0L, scalar_words: 0L, }
  } else {
    // Content's existing nested lookup reader returns before the next view.
    // Its original scalar options/budget/result coexist with the outer frame.
    lookup_capacity_body_construction_extent()
  }
  guard @shape.add_collection_construction_extents(frame, issue) is Some(errors) &&
    @shape.add_collection_construction_extents(errors, lookup) is Some(scratch) else {
    return None
  }
  Some(carrier_add_units(held, carrier_units(scratch)))
}

///|
/// Original cached list lengths bound the facts-quantity Map before its first
/// constructor. Only views can request an entry. Empty/unrelated Catalogs do
/// not reserve their policy maxima or every unused facts body here.
pub fn source_request_construction_inspection_extent(
  carriers : CarrierSchemas,
) -> RegistryConstructionExtent {
  let refs = carriers.modes.shapes.values.policies.references
  let v = carriers.modes.views.length()
  let n = Int::min(v, refs.contents.registry.entries.length()).to_int64()
  let active = if v == 0 { 0L } else { 1L }
  // Scan+returned scalar geometry2H14W; one cached facts record1H8W per
  // entry; at most ten live child/Some pairs2H3R2W and one field result.
  // Three local Option/scalar-result groups each3H1R5W, one Map result and
  // one original-reference lookup3H2R4W cover those typed returns. The
  // original listing field array is the only nonempty observation array.
  let field = @decode.indexed_field_construction_extent()
  carrier_units(
    @shape.collection_construction_extent({
      records: 2L + n + active * (20L + field.record_headers + 9L + 3L),
      record_references: active * (30L + field.reference_slots + 3L + 2L),
      record_words: 14L +
      8L * n +
      active * (20L + field.scalar_words + 15L + 4L),
      reference_arrays: 1L + active,
      reference_items: 15L * active,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: n,
    }).unwrap(),
  )
}

///|
pub fn source_request_construction_inspection_bound(
  carriers : CarrierSchemas,
) -> Int64 {
  let refs = carriers.modes.shapes.values.policies.references
  // Direct child-name scans are fixed per view. Each original referenced
  // facts body is inspected once, without descending into opaque extensions.
  1L +
  160L * refs.contents.registry.environment.nodes.to_int64() +
  32L * refs.references.length().to_int64()
}
