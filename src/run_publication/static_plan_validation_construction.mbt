///|
/// Constructor-owned validator DATA, not schema admission, capacity, or a
/// physical lifetime. Input canonical values and retained generated rules are
/// borrowed. Unique StringRule arrays compare borrowed scalar Strings after
/// the same finite escaping/validity check, without constructing item wires.
pub(all) struct StaticPlanValidationConstruction {
  owner : @shape.CollectionConstructionExtent
  owned_utf16_units : Int64
  owned_wire_bytes : Int64
  pending_reference_items : Int64
  unique_reference_items : Int64
  max_record_references : Int
  max_record_words : Int
  unique_item_bytes : Int
  unique_item_nodes : Int
  unique_item_depth : Int
} derive(Eq, Debug)

///|
// One continuation survives each child Visit. Array/object width does not
// grow this stack: Next/Result advances one original child at a time. The
// generated graph must be a backward DAG; a changed/unsupported graph fails
// closed rather than retaining an obsolete profile. This executes once with
// the module's original generated schema, not over each caller's document.
fn static_plan_validation_schema_profile(index : Int) -> (Int, Bool)? {
  let nodes = protocol_schema_nodes()
  if index < 0 || index >= nodes.length() {
    return None
  }
  let mut pending = 1
  let mut unique = false
  let child = (target : Int) => {
    if target < 0 || target >= index {
      return None
    }
    static_plan_validation_schema_profile(target)
  }
  match nodes[index] {
    AnyRule
    | NullRule
    | BoolRule(_)
    | NumberRule
    | IntegerRule(_, _)
    | StringCeilingRule(_)
    | ObjectCeilingRule(_) => ()
    StringRule(_, _, pattern, _) =>
      // CID and unsigned-decimal predicates use indexed scalar walks. Do not
      // silently include a future pattern that allocates a character array.
      if pattern != 0 && pattern != 1 && pattern != 8 {
        return None
      }
    ArrayRule(item, _, distinct, _) => {
      // Current unique families are the names/capability String arrays. A
      // new unique object/array family changes the issuer's shape obligation.
      if distinct &&
        (item < 0 || item >= index || !(nodes[item] is StringRule(_, _, _, _))) {
        return None
      }
      guard child(item) is Some((depth, nested)) else { return None }
      pending = depth + 1
      unique = distinct || nested
    }
    ContainsRule(item) | NotRule(item) => {
      guard child(item) is Some((depth, nested)) else { return None }
      pending = depth + 1
      unique = nested
    }
    TupleRule(items) | OneOfRule(items) | AnyOfRule(items) | AllOfRule(items) =>
      for item in items {
        guard child(item) is Some((depth, nested)) else { return None }
        pending = Int::max(pending, depth + 1)
        unique = unique || nested
      }
    ConditionalRule(condition, yes, no) =>
      for item in [condition, yes, no] {
        guard child(item) is Some((depth, nested)) else { return None }
        pending = Int::max(pending, depth + 1)
        unique = unique || nested
      }
    ObjectRule(properties, _, additional, _, _, pattern) => {
      if pattern != 0 && pattern != 1 && pattern != 8 {
        return None
      }
      for (_, item) in properties {
        guard child(item) is Some((depth, nested)) else { return None }
        pending = Int::max(pending, depth + 1)
        unique = unique || nested
      }
      if additional >= 0 {
        guard child(additional) is Some((depth, nested)) else { return None }
        pending = Int::max(pending, depth + 1)
        unique = unique || nested
      }
    }
  }
  Some((pending, unique))
}

///|
fn static_plan_validation_profile(
  name : String,
  complete : Bool,
) -> (Int, Bool)? {
  generated_protocol_schema_root(name, complete).bind(
    static_plan_validation_schema_profile,
  )
}

///|
// Generated rule tables are already module-retained. These seven small
// profiles likewise precede Native request scopes and contain no user data.
let static_plan_validation_profiles : Array[(String, Bool, (Int, Bool)?)] = [
  (
    "logical_step_key",
    false,
    static_plan_validation_profile("logical_step_key", false),
  ),
  (
    "logical_step_key",
    true,
    static_plan_validation_profile("logical_step_key", true),
  ),
  (
    "logical_port_key",
    false,
    static_plan_validation_profile("logical_port_key", false),
  ),
  (
    "logical_port_key",
    true,
    static_plan_validation_profile("logical_port_key", true),
  ),
  ("logical_map", false, static_plan_validation_profile("logical_map", false)),
  ("logical_map", true, static_plan_validation_profile("logical_map", true)),
  ("plan_view", true, static_plan_validation_profile("plan_view", true)),
]

///|
fn static_plan_validation_selected_profile(
  name : String,
  complete : Bool,
) -> (Int, Bool)? {
  for (selected, full, profile) in static_plan_validation_profiles {
    if selected == name && full == complete {
      return profile
    }
  }
  None
}

///|
fn static_plan_validation_construction(
  name : String,
  complete : Bool,
  unique_items : Int,
  unique_wire_bytes : Int64,
  item_bytes : Int,
  item_nodes : Int,
  item_depth : Int,
) -> StaticPlanValidationConstruction? {
  guard static_plan_validation_selected_profile(name, complete)
    is Some((pending, unique)) else {
    return None
  }
  if unique_items < 0 ||
    unique_wire_bytes < 0L ||
    item_bytes < 0 ||
    item_nodes < 0 ||
    item_depth < 0 ||
    (
      unique_items > 0 &&
      (
        item_bytes == 0 ||
        item_nodes == 0 ||
        item_bytes.to_int64() > unique_wire_bytes
      )
    ) {
    return None
  }
  let items = if unique { unique_items.to_int64() } else { 0L }
  // Cursor:4R2W (nodes,budget,pending,historical root,result,closed).
  // Budget:4W. Every pending variant fits2R3W (Alternatives/Result is
  // largest). Keep the popped frame and its Option beside all pending frames.
  // Fixed transition controls: pop Option1R, array_at Option1R, property/
  // safe-integer Option1W, two captured scalar predicate closures1R each,
  // their two optional Bool results1W each, and advance's (done,used)
  // pair2W. Predicate captures can instead be
  // scalar1W each, so include both layouts. Their bodies/keys remain borrowed.
  let frames = pending.to_int64() + 1L
  guard @shape.collection_construction_extent({
      records: 2L + frames + 8L,
      record_references: 4L + 2L * frames + 4L,
      record_words: 6L + 3L * frames + 7L,
      reference_arrays: 1L + (if unique { 2L } else { 0L }),
      reference_items: pending.to_int64() + 2L * items,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(controls) else {
    return None
  }
  // Both the detached input array and seen array own only references. The
  // original String bodies stay borrowed even for cold/malformed documents.
  // Quoted extent returns one optional pair, with no writer or owned text.
  guard @shape.add_collection_construction_extents(controls, {
      record_headers: 2L,
      reference_slots: 1L,
      scalar_words: 2L,
    })
    is Some(owner) else {
    return None
  }
  Some({
    owner,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
    pending_reference_items: pending.to_int64(),
    unique_reference_items: items,
    max_record_references: 4,
    max_record_words: 4,
    unique_item_bytes: 0,
    unique_item_nodes: 0,
    unique_item_depth: 0,
  })
}

///|
/// Only the original static-plan issuer may select this shape: logical names
/// contain at most one binding String; capability arrays are empty. This is
/// not a valid shortcut for cold/untrusted JSON, even if it later validates.
pub fn fresh_static_plan_validation_construction(
  name : String,
  complete : Bool,
  max_quoted_name_bytes : Int,
) -> StaticPlanValidationConstruction? {
  if max_quoted_name_bytes < 0 || max_quoted_name_bytes == 1 {
    return None
  }
  static_plan_validation_construction(
    name,
    complete,
    if max_quoted_name_bytes == 0 {
      0
    } else {
      1
    },
    max_quoted_name_bytes.to_int64(),
    max_quoted_name_bytes,
    if max_quoted_name_bytes == 0 {
      0
    } else {
      1
    },
    0,
  )
}

///|
/// Cold/general preparse envelope. Caller-proved upper bounds must include
/// malformed canonical items. The pinned schema requires StringRule items:
/// other types refuse before serialization, and strings borrow original text.
/// Existing extent arguments remain checked sizing data, not codec limits.
pub fn cold_static_plan_validation_construction(
  name : String,
  complete : Bool,
  max_unique_items : Int,
  max_unique_wire_bytes : Int64,
  max_item_bytes : Int,
  max_item_nodes : Int,
  max_item_depth : Int,
) -> StaticPlanValidationConstruction? {
  static_plan_validation_construction(
    name, complete, max_unique_items, max_unique_wire_bytes, max_item_bytes, max_item_nodes,
    max_item_depth,
  )
}
