///|
/// Normalization preserves the exact typed Graph contract. It neither fills
/// absent property definitions nor upgrades an opaque input to a typed graph.
struct CheckedNormalize {
  source : @decode.Cursor
  graph : @carrier.Carrier
  usage : Usage
}

///|
pub(all) enum NormalizeObligation {
  AdmitNormalizeGraph
  ResolveNormalizeResources
} derive(Eq, Debug)

///|
pub fn check_normalize(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedNormalize, Issue] {
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
    if @decode.boolean(source) != Ok(true) {
      fail(source, InvalidBody)
    }
    match input {
      @carrier.GraphValue(_) => ()
      @carrier.Opaque(@carrier.GraphKind) => fail(source, IncompleteGraph)
      _ => fail(source, WrongCarrier(@carrier.kind(input)))
    }
    Ok({
      source,
      graph: input,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    Stop(issue) => Err(issue)
  }
}

///|
pub fn normalize_source(value : CheckedNormalize) -> @decode.Cursor {
  value.source
}

///|
pub fn normalize_output(value : CheckedNormalize) -> @carrier.Carrier {
  value.graph
}

///|
pub fn normalize_usage(value : CheckedNormalize) -> Usage {
  value.usage
}

///|
pub fn normalize_pending_count(_ : CheckedNormalize) -> Int {
  2
}

///|
pub fn normalize_pending_at(
  _ : CheckedNormalize,
  index : Int,
) -> NormalizeObligation? {
  match index {
    0 => Some(AdmitNormalizeGraph)
    1 => Some(ResolveNormalizeResources)
    _ => None
  }
}
