///|
pub(all) enum NestValueIssue {
  InvalidLimits
  BudgetExceeded
  ForeignOwner
  MissingCeiling
  DepthExceeded
} derive(Eq, Debug)

///|
pub(all) enum NestValueRule {
  MeasureGroupedChildArrays
  MeasureAttachedRecursiveFields
  CheckLogicalExpansionArithmetic
} derive(Eq, Debug)

///|
pub fn nest_value_rule_count(_v : NestValueEnvelope) -> Int {
  3
}

///|
pub fn nest_value_rule_at(
  _v : NestValueEnvelope,
  index : Int,
) -> NestValueRule? {
  match index {
    0 => Some(MeasureGroupedChildArrays)
    1 => Some(MeasureAttachedRecursiveFields)
    2 => Some(CheckLogicalExpansionArithmetic)
    _ => None
  }
}

///|
/// Retain selected ceilings and static depth before binding runtime measurement.
/// A per-parent item bound is not a bound on total repeated child payload.
pub fn link_program_nest_value_envelopes(
  index : ProgramOperationResolutionIndex,
  max_work : Int,
  max_links : Int,
  max_depth : Int,
) -> Result[ProgramOperationResolutionIndex, NestValueIssue] {
  if max_work < 0 || max_links < 0 || max_depth < 0 {
    return Err(InvalidLimits)
  }
  let count = index.states.length()
  if index.work > max_work || count > (max_work - index.work) / 2 {
    return Err(BudgetExceeded)
  }
  let mut work = index.work + count * 2
  let states = index.states.copy()
  let mut links = 0
  for i in 0..<count {
    let site = index.requirements.entries[i]
    guard site.requirement is @pipeline.NestRequirement(ResolveNestedEnvelope) else {
      continue
    }
    if links == max_links {
      return Err(BudgetExceeded)
    }
    guard states[i] is Unresolved && i >= site.index else {
      return Err(ForeignOwner)
    }
    let base = i - site.index
    let n = @pipeline.operation_obligations_count(site.obligations)
    if n > count - base || n > max_work - work {
      return Err(BudgetExceeded)
    }
    work += n
    let mut selected = None
    for j in 0..<n {
      guard states[base + j] is Execution(NestItems(items)) else { continue }
      if selected is Some(_) ||
        items.requirement != base + j ||
        items.site.stage != site.stage ||
        items.site.producer_visit != site.producer_visit ||
        items.site.step != site.step ||
        items.site.group != site.group ||
        !physical_equal(items.site.pipeline, site.pipeline) ||
        !physical_equal(items.owner.requirements, index.requirements) {
        return Err(ForeignOwner)
      }
      selected = Some(items)
    }
    guard selected is Some(items) else { return Err(ForeignOwner) }
    let envelope = match
      prepare_nest_value_envelope(
        items,
        items.work + (max_work - work),
        max_depth,
      ) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    work += envelope.work - items.work
    states[i] = Execution(NestValues({ site, envelope, }))
    links += 1
  }
  Ok({ ..index, states, unresolved: index.unresolved - links, work, })
}

///|
/// Future measurement/checked arithmetic, not observed byte or element counts.
pub struct NestValuesCheck {
  site : OperationRequirementSite
  envelope : NestValueEnvelope
}

///|
priv enum NestTypeFrame {
  Read(@contract.Contract, Int)
  Fields(@contract.Fields, Int, Int)
}

///|
/// Conditional bounds and future byte-measurement scopes. Counts derived from
/// output enforcement cannot authorize an upstream read or preflight by themselves.
pub struct NestValueEnvelope {
  items : NestItemLimit
  byte_ceiling : @policy.Ceiling
  depth_ceiling : @policy.Ceiling
  payload_type : @contract.Contract
  type_depth : Int
  successful_parent_ceiling : Int64
  expanded_elements_ceiling : Int64
  priv parent_candidates : Array[@capacity.TargetMembership]
  priv attachment_fields : Array[Int]
  work : Int
}

///|
pub fn nest_parent_candidate_count(v : NestValueEnvelope) -> Int {
  v.parent_candidates.length()
}

///|
pub fn nest_parent_candidate_at(
  v : NestValueEnvelope,
  i : Int,
) -> @capacity.TargetMembership? {
  v.parent_candidates.get(i)
}

///|
// Exact min(cap, a*b) for nonnegative admitted counts. Do not materialize an
// overflowing product, round it, or serialize a saturated multiplication proof.
fn nest_min_product(cap : Int64, a : Int64, b : Int64) -> Int64 {
  if a == 0L || b == 0L {
    return 0L
  }
  if a > cap / b {
    cap
  } else {
    a * b
  }
}

///|
pub fn nest_attachment_field_count(v : NestValueEnvelope) -> Int {
  v.attachment_fields.length()
}

///|
/// Retained output-schema coordinates, not an allocation of serialized names.
pub fn nest_attachment_field_at(
  v : NestValueEnvelope,
  i : Int,
) -> @schema.Field? {
  v.attachment_fields
  .get(i)
  .bind(index => @schema.field_at(@nest.output_schema(v.items.operation), index))
}

///|
pub fn prepare_nest_value_envelope(
  items : NestItemLimit,
  max_work : Int,
  max_depth : Int,
) -> Result[NestValueEnvelope, NestValueIssue] {
  if max_work < 0 || max_depth < 0 {
    return Err(InvalidLimits)
  }
  let site = items.site
  let stages = items.owner.requirements.stages
  let policy = @capacity.application_closure_policy(
    stages.contexts[site.stage].context.capacity,
  )
  guard @policy.ceiling(policy, "max_nested_value_bytes") is Some(byte_ceiling) &&
    @policy.ceiling(policy, "max_nested_value_depth") is Some(depth_ceiling) else {
    return Err(MissingCeiling)
  }
  let schema = @nest.output_schema(items.operation)
  let name = @nest.into(items.operation)
  if items.work >= max_work || name.length() > max_work - items.work - 1 {
    return Err(BudgetExceeded)
  }
  let mut work = items.work + name.length() + 1
  guard @schema.lookup(schema, @schema.Unqualified(name)) is Some(payload_type) &&
    payload_type.shape is @contract.Array(_, ..) else {
    return Err(ForeignOwner)
  }
  let mut type_depth = 0
  let pending : Array[NestTypeFrame] = [Read(payload_type, 0)]
  while pending.pop() is Some(frame) {
    if work >= max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    match frame {
      Read(contract, depth) => {
        let container = match contract.shape {
          Array(_, ..) | Object(_) => true
          _ => false
        }
        let next = if container {
          if depth >= max_depth {
            return Err(BudgetExceeded)
          }
          depth + 1
        } else {
          depth
        }
        type_depth = type_depth.max(next)
        if next.to_int64() > @policy.ceiling_value(depth_ceiling) {
          return Err(DepthExceeded)
        }
        match contract.shape {
          Array(item, ..) => pending.push(Read(item, next))
          Object(fields) => pending.push(Fields(fields, 0, next))
          Json | ResourceRef(..) | ArtifactRef(..) => return Err(ForeignOwner)
          Text(_)
          | Number
          | Boolean
          | Timestamp
          | Date
          | Decimal(..)
          | Vector(..) => ()
        }
      }
      Fields(fields, index, depth) =>
        if @contract.field_at(fields, index) is Some(field) {
          pending.push(Fields(fields, index + 1, depth))
          pending.push(Read(field.contract, depth))
        }
    }
  }
  let attachment_fields : Array[Int] = []
  let width = @schema.field_count(schema)
  if width > (max_work - work) / 2 {
    return Err(BudgetExceeded)
  }
  // Reserve both the field visits and worst-case index allocation before copying.
  work += width * 2
  for i in 0..<width {
    let field = @schema.field_at(schema, i).unwrap()
    match field.contract.shape {
      Array(_, ..) | Object(_) => attachment_fields.push(i)
      _ => ()
    }
  }
  let closure = stages.contexts[site.stage].context.capacity
  let (parent_candidates, used) = match
    collect_target_row_candidates(
      closure,
      site.pipeline,
      items.parent,
      Some(site.producer_visit),
      max_work - work,
      max_work - work,
    ) {
    Ok(v) => v
    Err(CandidateBudget) => return Err(BudgetExceeded)
    Err(_) => return Err(ForeignOwner)
  }
  work += used
  // Each preserved parent emits at least [] and each child element is a
  // non-null object, costing at least {}. These are distinct conditional bounds
  // from the same attachment-byte enforcement, not independent bytes to add.
  let byte_count_cap = @policy.ceiling_value(byte_ceiling) / 2L
  let mut successful_parent_ceiling = byte_count_cap
  for candidate in parent_candidates {
    if work >= max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    successful_parent_ceiling = Int64::min(
      successful_parent_ceiling,
      @step_bounds.target_rows_value(
        @capacity.target_membership_rows(candidate),
      ),
    )
  }
  if work >= max_work {
    return Err(BudgetExceeded)
  }
  work += 1
  let expanded_elements_ceiling = nest_min_product(
    byte_count_cap,
    successful_parent_ceiling,
    items.maximum,
  )
  Ok({
    items,
    byte_ceiling,
    depth_ceiling,
    payload_type,
    type_depth,
    successful_parent_ceiling,
    expanded_elements_ceiling,
    parent_candidates,
    attachment_fields,
    work,
  })
}
