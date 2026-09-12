///|
priv enum SourceViewRule {
  SVObject(Array[(String, Bool, SourceViewRule)])
  SVArray(Int, Bool, SourceViewRule)
  SVText(Int, Array[String], Bool)
  SVBoolean(Bool?)
  SVPositiveInteger
}

///|
pub(all) struct SourceViewShapeLimits {
  max_work : Int
  max_views : Int
}

///|
pub(all) enum SourceViewShapeIssueKind {
  InvalidLimits
  WorkLimit
  ViewLimit
  InvalidShape
  MissingField(String)
  UnknownField(String)
  DuplicateItem(String)
} derive(Eq, Debug)

///|
pub(all) struct SourceViewShapeIssue {
  kind : SourceViewShapeIssueKind
  source : @decode.Cursor?
}

///|
struct SourceViewShapes {
  values : ProtocolValueContracts
  views : Array[Member]
  work : Int
}

///|
priv suberror ViewShapeStop {
  ViewShapeStop(SourceViewShapeIssue)
}

///|
priv struct ViewShapeBudget {
  mut left : Int
}

///|
fn[T] sv_fail(
  kind : SourceViewShapeIssueKind,
  source : @decode.Cursor,
) -> T raise ViewShapeStop {
  raise ViewShapeStop({ kind, source: Some(source), })
}

///|
fn sv_charge(
  b : ViewShapeBudget,
  n : Int,
  c : @decode.Cursor,
) -> Unit raise ViewShapeStop {
  if n > b.left {
    sv_fail(WorkLimit, c)
  }
  b.left -= n
}

///|
priv enum ViewShapeFrame {
  SVVisit(@decode.Cursor, SourceViewRule)
  SVNext(@decode.Cursor, Int, Int, SourceViewRule, Map[String, Bool]?)
}

///|
fn validate_view_shape(
  root : @decode.Cursor,
  rule : SourceViewRule,
  budget : ViewShapeBudget,
) -> Unit raise ViewShapeStop {
  let stack = [SVVisit(root, rule)]
  while stack.pop() is Some(frame) {
    match frame {
      SVNext(c, i, count, child, seen) =>
        if i < count {
          sv_charge(budget, 1, c)
          let item = @decode.element_at(c, i).unwrap()
          if seen is Some(names) {
            let text = match @decode.text(item) {
              Ok(v) => v
              Err(_) => sv_fail(InvalidShape, item)
            }
            sv_charge(budget, text.length(), item)
            if names.contains(text) {
              sv_fail(DuplicateItem(text), item)
            }
            names[text] = true
          }
          stack.push(SVNext(c, i + 1, count, child, seen))
          stack.push(SVVisit(item, child))
        }
      SVVisit(c, node) => {
        sv_charge(budget, 1, c)
        match node {
          SVText(minimum, choices, is_cid) => {
            let text = match @decode.text(c) {
              Ok(v) => v
              Err(_) => sv_fail(InvalidShape, c)
            }
            sv_charge(budget, text.length(), c)
            if text.length() < minimum ||
              (!choices.is_empty() && !choices.contains(text)) {
              sv_fail(InvalidShape, c)
            }
            if is_cid {
              if text.length() != 71 || !text.has_prefix("sha256:") {
                sv_fail(InvalidShape, c)
              }
              for i in 7..<71 {
                let u = text.code_unit_at(i).to_int()
                if !((u >= 48 && u <= 57) || (u >= 97 && u <= 102)) {
                  sv_fail(InvalidShape, c)
                }
              }
            }
          }
          SVBoolean(expected) => {
            let value = match @decode.boolean(c) {
              Ok(v) => v
              Err(_) => sv_fail(InvalidShape, c)
            }
            if expected is Some(wanted) && value != wanted {
              sv_fail(InvalidShape, c)
            }
          }
          SVPositiveInteger => {
            let value = match @decode.finite_number(c) {
              Ok(v) => v
              Err(_) => sv_fail(InvalidShape, c)
            }
            if value < 1.0 || value % 1.0 != 0.0 {
              sv_fail(InvalidShape, c)
            }
          }
          SVArray(minimum, unique, child) => {
            let count = match @decode.array_length(c) {
              Some(v) => v
              None => sv_fail(InvalidShape, c)
            }
            if count < minimum {
              sv_fail(InvalidShape, c)
            }
            if count > budget.left {
              sv_fail(WorkLimit, c)
            }
            let seen = if unique { Some(Map([])) } else { None }
            stack.push(SVNext(c, 0, count, child, seen))
          }
          SVObject(fields) => {
            let count = match @decode.object_length(c) {
              Some(v) => v
              None => sv_fail(InvalidShape, c)
            }
            sv_charge(budget, count, c)
            let seen : Map[String, Bool] = Map([])
            for i in 0..<count {
              let (name, value) = @decode.field_at(c, i).unwrap()
              sv_charge(budget, name.length(), c)
              let mut child = None
              for (key, _, rule) in fields {
                if name == key {
                  child = Some(rule)
                  break
                }
              }
              match child {
                Some(rule) => {
                  seen[name] = true
                  stack.push(SVVisit(value, rule))
                }
                None => sv_fail(UnknownField(name), value)
              }
            }
            for (name, required, _) in fields {
              if required && !seen.contains(name) {
                sv_fail(MissingField(name), c)
              }
            }
          }
        }
      }
    }
  }
}

///|
/// Shape only: role contracts are retained, but mode coherence, correlation,
/// output Carrier compatibility and publisher authority remain separate.
pub fn check_source_view_shapes(
  values : ProtocolValueContracts,
  limits : SourceViewShapeLimits,
) -> Result[SourceViewShapes, SourceViewShapeIssue] {
  if limits.max_work < 0 || limits.max_views < 0 {
    return Err({ kind: InvalidLimits, source: None, })
  }
  let views = []
  let budget = { left: limits.max_work, }
  let rule = source_view_shape_rule()
  try {
    for catalog in values.policies.references.contents.entries {
      sv_charge(budget, 1, member_body(catalog.item))
      for item in catalog.views {
        if views.length() >= limits.max_views {
          sv_fail(ViewLimit, member_body(item))
        }
        validate_view_shape(member_body(item), rule, budget)
        views.push(item)
      }
    }
    Ok({ values, views, work: limits.max_work - budget.left, })
  } catch {
    ViewShapeStop(e) => Err(e)
  }
}

///|
pub fn source_view_shape_values(v : SourceViewShapes) -> ProtocolValueContracts {
  v.values
}

///|
pub fn source_view_shape_at(v : SourceViewShapes, i : Int) -> Member? {
  v.views.get(i)
}

///|
pub fn source_view_shape_usage(v : SourceViewShapes) -> (Int, Int) {
  (v.work, v.views.length())
}
