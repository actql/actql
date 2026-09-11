///|
struct CheckedUnion {
  source : @decode.Cursor
  left : @carrier.Carrier
  rights : Array[@carrier.Carrier]
  folds : Array[CheckedStructural]
  output : @carrier.Carrier
  usage : Usage
}

///|
/// Admit scalar or nonempty-list references and retain every ordered binary
/// fold. Carrier operands must correspond to reference occurrences in order.
pub fn check_union(
  source : @decode.Cursor,
  left : @carrier.Carrier,
  rights : Array[@carrier.Carrier],
  limits : Limits,
) -> Result[CheckedUnion, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    scan(b, source)
    let root = decoded(@decode.closed_object(source, ["with", "merge"]))
    let at = decoded(@decode.required(root, "with"))
    let count = match @decode.array_length(at) {
      Some(n) if n > 0 => n
      Some(_) => fail(at, InvalidBody)
      None => {
        let _ = decoded(@decode.text(at))
        1
      }
    }
    if count != rights.length() {
      fail(at, InvalidBody)
    }
    spend(b, at, count)
    let folds = []
    let retained = []
    let mut output = left
    for i in 0..<count {
      let reference = @decode.element_at(at, i).unwrap_or(at)
      let c = match
        check_structural_impl(
          Union,
          source,
          output,
          rights[i],
          {
            max_work: b.work,
            max_nodes: b.nodes,
            max_text_bytes: b.text,
            max_depth: limits.max_depth,
          },
          reference=Some(reference),
          source_scanned=true,
        ) {
        Ok(c) => c
        Err(e) => raise Stop(e)
      }
      b.work -= c.usage.work
      b.nodes -= c.usage.nodes
      b.text -= c.usage.text_bytes
      output = c.output
      folds.push(c)
      retained.push(rights[i])
    }
    Ok({
      source,
      left,
      rights: retained,
      folds,
      output,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn union_source(c : CheckedUnion) -> @decode.Cursor {
  c.source
}

///|
pub fn union_input(c : CheckedUnion) -> @carrier.Carrier {
  c.left
}

///|
pub fn union_count(c : CheckedUnion) -> Int {
  c.folds.length()
}

///|
pub fn union_operand_at(c : CheckedUnion, index : Int) -> @carrier.Carrier? {
  c.rights.get(index)
}

///|
pub fn union_fold_at(c : CheckedUnion, index : Int) -> CheckedStructural? {
  c.folds.get(index)
}

///|
pub fn union_output(c : CheckedUnion) -> @carrier.Carrier {
  c.output
}

///|
pub fn union_usage(c : CheckedUnion) -> Usage {
  c.usage
}
