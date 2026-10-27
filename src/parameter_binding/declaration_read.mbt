///|
/// The original declaration source/limits after its actual full preflight.
/// This is a retained semantic continuation, not another resource owner,
/// permission or caller-supplied proof. Inputs remain immutable-by-ownership.
struct DeclarationReadInput {
  root : @decode.Cursor?
  limits : DeclarationLimits
  usage : (Int, Int)
  mut outcome : Result[Declarations, Issue]?
}

///|
/// The actual caller funds this preflight and its fixed controls before entry.
/// Defaults and metadata remain in the same original source. No type/default
/// body constructor is run here. Original first-refusal usage is returned even
/// when no continuation can be issued; no failed work is refunded or invented.
pub fn prepare_declaration_read(
  root : @decode.Cursor?,
  limits : DeclarationLimits,
) -> (Result[DeclarationReadInput, Issue], Int, Int) {
  let (preflight, nodes, text) = preflight_declaration_read(root, limits)
  let result = match preflight {
    Err(issue) => Err(issue)
    Ok(_) => Ok({ root, limits, usage: (nodes, text), outcome: None, })
  }
  (result, nodes, text)
}

///|
// Sole original preflight and first-refusal usage implementation. The ordinary
// reader and the split Resource caller share it; only the latter retains a
// DeclarationReadInput. No global cache or cross-request result is installed.
fn preflight_declaration_read(
  root : @decode.Cursor?,
  limits : DeclarationLimits,
) -> (Result[Unit, Issue], Int, Int) {
  if limits.max_parameters < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_text_bytes < 0 {
    return (Err(InvalidLimits), 0, 0)
  }
  let budget : Budget = {
    nodes: limits.max_nodes,
    text: limits.max_text_bytes,
    depth: limits.max_depth,
  }
  let admitted : Result[Unit, Issue] = try {
    if root is Some(original) {
      preflight(original, budget)
    }
    Ok(())
  } catch {
    Abort(issue) => Err(issue)
  }
  let nodes = limits.max_nodes - budget.nodes
  let text = limits.max_text_bytes - budget.text
  (admitted, nodes, text)
}

///|
/// Call after reserving the original declaration/type/default constructor
/// coexistence. Same-input repeat forwards the completed outcome unchanged;
/// it never rechecks the original type/default or rebuilds its arrays. There
/// is no clock, Account, authorization, external callback or resource mutation
/// in this immutable semantic read. Current/cleanup duties remain outside it.
pub fn finish_declaration_read(
  original : DeclarationReadInput,
) -> Result[Declarations, Issue] {
  match original.outcome {
    Some(completed) => completed
    None => {
      let outcome = finish_declaration_read_owned(
        original.root,
        original.limits,
        original.usage,
      )
      original.outcome = Some(outcome)
      outcome
    }
  }
}
