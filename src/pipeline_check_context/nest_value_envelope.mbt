///|
pub(all) enum NestValueIssue {
  InvalidLimits
  BudgetExceeded
  ForeignOwner
  MissingCeiling
  DepthExceeded
} derive(Eq, Debug)

///|
priv enum NestTypeFrame {
  Read(@contract.Contract, Int)
  Fields(@contract.Fields, Int, Int)
}

///|
/// Static payload depth and future byte-measurement scopes. Not a measured
/// byte count or a proof of total parent-count times child-array expansion.
pub struct NestValueEnvelope {
  items : NestItemLimit
  byte_ceiling : @policy.Ceiling
  depth_ceiling : @policy.Ceiling
  payload_type : @contract.Contract
  type_depth : Int
  priv attachment_fields : Array[Int]
  work : Int
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
  let stages = items.owner.requirements.expressions.identity.sources.operations.preparation.profiles.context.selected.context.wired.stages
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
  Ok({
    items,
    byte_ceiling,
    depth_ceiling,
    payload_type,
    type_depth,
    attachment_fields,
    work,
  })
}
