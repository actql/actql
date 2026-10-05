///|
fn path_at(
  tree : Array[OwnedNode],
  parent : Int,
  edge : Edge,
) -> Array[PathSegment] {
  let reversed : Array[PathSegment] = []
  let mut current = parent
  let mut step = edge
  while true {
    match step {
      Root => ()
      Element(index) => reversed.push(@source.Index(index))
      Field(key, _) => reversed.push(@source.Key(key))
    }
    if current < 0 {
      break
    }
    step = tree[current].edge
    current = tree[current].parent
  }
  for left = 0; left < reversed.length() / 2; left = left + 1 {
    let right = reversed.length() - 1 - left
    let saved = reversed[left]
    reversed[left] = reversed[right]
    reversed[right] = saved
  }
  reversed
}

///|
fn at(
  tree : Array[OwnedNode],
  parent : Int,
  edge : Edge,
  span : @span.Span,
  kind : IssueKind,
) -> Issue {
  { kind, path: path_at(tree, parent, edge), span, }
}

///|
fn text_charge(
  text : String,
  limits : Limits,
  remaining : Int,
) -> Result[Int, IssueKind] {
  // Use the tighter allowance before scanning; no unbounded Unicode preflight.
  let allowance = if remaining < limits.max_string_bytes {
    remaining
  } else {
    limits.max_string_bytes
  }
  match @scalar.admit_utf8_length(text, allowance) {
    Ok(size) => Ok(size)
    Err(@scalar.MalformedUtf16(_)) => Err(InvalidUnicode)
    Err(_) => Err(BudgetExceeded)
  }
}

///|
/// Copy a bounded raw Node tree. No normalization or numeric/domain validation
/// is performed. Concurrent mutation of the input during admission is unsupported.
pub fn admit(root : @source.Node, limits : Limits) -> Result[Cursor, Issue] {
  let admission = match start_admission(root, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  while true {
    match advance_admission(admission, 64) {
      Ok(AdmissionContinue(..)) => ()
      Ok(AdmissionComplete(cursor, ..)) => return Ok(cursor)
      Ok(AdmissionFailed(issue, ..)) => return Err(issue)
      Err(_) => abort("invalid synchronous admission state")
    }
  } nobreak {
    abort("unreachable admission state")
  }
}

///|
struct Admission {
  limits : Limits
  mut tree : Array[OwnedNode]
  work : Array[Work]
  mut remaining_text : Int
  mut deepest : Int
  mut largest_string : Int
  mut terminal : Bool
}

///|
pub(all) enum AdmissionControlIssue {
  InvalidQuantum
  Terminal
} derive(Eq, Debug)

///|
pub enum AdmissionPoll {
  AdmissionContinue(work~ : Int)
  AdmissionComplete(Cursor, work~ : Int)
  AdmissionFailed(Issue, work~ : Int)
}

///|
pub fn start_admission(
  root : @source.Node,
  limits : Limits,
) -> Result[Admission, Issue] {
  if limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_string_bytes < 0 ||
    limits.max_total_string_bytes < 0 {
    return Err({ kind: InvalidLimits, path: [], span: root.span, })
  }
  Ok({
    limits,
    tree: [],
    work: [Visit(root, -1, Root, 0)],
    remaining_text: limits.max_total_string_bytes,
    deepest: 0,
    largest_string: 0,
    terminal: false,
  })
}

///|
fn Admission::step(admission : Admission) -> Result[Unit, Issue] {
  let tree = admission.tree
  let work = admission.work
  let limits = admission.limits
  if work.pop() is Some(task) {
    match task {
      Visit(node, parent, edge, parent_depth) => {
        if tree.length() >= limits.max_nodes {
          return Err(at(tree, parent, edge, node.span, BudgetExceeded))
        }
        let is_container = match node.value {
          @source.Array(_) | @source.Object(_) => true
          _ => false
        }
        // Test before adding one so even an Int::MAX allowance cannot overflow.
        if is_container && parent_depth >= limits.max_depth {
          return Err(at(tree, parent, edge, node.span, BudgetExceeded))
        }
        let depth = parent_depth + (if is_container { 1 } else { 0 })
        admission.deepest = Int::max(admission.deepest, depth)
        let remaining_nodes = limits.max_nodes - tree.length() - 1
        let value : OwnedValue = match node.value {
          @source.Null => Null
          @source.Bool(value) => Bool(value)
          @source.Number(value) => Number(value)
          @source.String(value) => {
            match text_charge(value, limits, admission.remaining_text) {
              Ok(size) => {
                admission.remaining_text -= size
                admission.largest_string = Int::max(
                  admission.largest_string,
                  size,
                )
              }
              Err(kind) => return Err(at(tree, parent, edge, node.span, kind))
            }
            Text(value)
          }
          @source.Array(items) => {
            if items.length() > remaining_nodes {
              return Err(at(tree, parent, edge, node.span, BudgetExceeded))
            }
            ArrayValue([])
          }
          @source.Object(fields) => {
            if fields.length() > remaining_nodes {
              return Err(at(tree, parent, edge, node.span, BudgetExceeded))
            }
            ObjectValue([])
          }
        }
        let index = tree.length()
        tree.push({ value, span: node.span, parent, edge, })
        if parent >= 0 {
          match (tree[parent].value, edge) {
            (ArrayValue(items), Element(_)) => items.push(index)
            (ObjectValue(fields), Field(key, span)) =>
              fields.push({ key, span, index, })
            _ => abort("invalid admission continuation")
          }
        }
        match node.value {
          @source.Array(items) => work.push(ArrayNext(items, index, 0, depth))
          @source.Object(fields) =>
            work.push(
              ObjectNext(fields, index, 0, depth, @shape.key_admission()),
            )
          _ => ()
        }
      }
      ArrayNext(items, parent, next, depth) =>
        if next < items.length() {
          work.push(ArrayNext(items, parent, next + 1, depth))
          work.push(Visit(items[next], parent, Element(next), depth))
        }
      ObjectNext(fields, parent, next, depth, seen) =>
        if next < fields.length() {
          let field = fields[next]
          let edge = Field(field.key, field.key_span)
          match text_charge(field.key, limits, admission.remaining_text) {
            Ok(size) => {
              admission.remaining_text -= size
              admission.largest_string = Int::max(
                admission.largest_string,
                size,
              )
            }
            Err(kind) =>
              return Err(at(tree, parent, edge, field.key_span, kind))
          }
          if !@shape.admit_key(seen, field.key) {
            return Err(at(tree, parent, edge, field.key_span, DuplicateField))
          }
          work.push(ObjectNext(fields, parent, next + 1, depth, seen))
          work.push(Visit(field.value, parent, edge, depth))
        }
    }
  }
  Ok(())
}

///|
/// One existing copy/admission continuation per work unit. Partial trees never
/// escape; immutable cursor ownership transfers only at successful completion.
pub fn advance_admission(
  admission : Admission,
  quantum : Int,
) -> Result[AdmissionPoll, AdmissionControlIssue] {
  if quantum < 1 {
    return Err(InvalidQuantum)
  }
  if admission.terminal {
    return Err(Terminal)
  }
  let mut used = 0
  while used < quantum {
    used += 1
    if admission.step() is Err(issue) {
      cancel_admission(admission)
      return Ok(AdmissionFailed(issue, work=used))
    }
    if admission.work.is_empty() {
      let tree = admission.tree
      // Transfer the owned index without a synchronous whole-tree copy. The
      // continuation must not clear it during a later duplicate cancellation.
      admission.tree = []
      let cursor : Cursor = {
        tree,
        index: 0,
        usage: {
          nodes: tree.length(),
          depth: admission.deepest,
          largest_string_bytes: admission.largest_string,
          total_string_bytes: admission.limits.max_total_string_bytes -
          admission.remaining_text,
        },
      }
      admission.terminal = true
      return Ok(AdmissionComplete(cursor, work=used))
    }
  }
  Ok(AdmissionContinue(work=used))
}

///|
pub fn cancel_admission(admission : Admission) -> Unit {
  admission.work.clear()
  admission.tree.clear()
  admission.terminal = true
}
