///|
/// The original declaration source/limits after its actual full preflight.
/// This is a retained semantic continuation, not another resource owner,
/// permission or caller-supplied proof. Inputs remain immutable-by-ownership.
struct DeclarationReadInput {
  root : @decode.Cursor?
  limits : DeclarationLimits
  usage : (Int, Int)
  mut state : DeclarationReadState
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
    Ok(_) => Ok({ root, limits, usage: (nodes, text), state: AwaitingHeader, })
  }
  (result, nodes, text)
}

///|
// Sole original preflight and first-refusal usage implementation. The ordinary
// reader and the split Resource caller share it; only the latter exposes a
// DeclarationReadInput. No global cache or cross-request result is installed.
fn preflight_declaration_read(
  root : @decode.Cursor?,
  limits : DeclarationLimits,
) -> (Result[Unit, Issue], Int, Int) {
  if declaration_limits_invalid(limits) {
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
  for state = original.state {
    match state {
      ReadCompleted(completed) => break completed
      _ => {
        advance_declaration_read(original)
        continue original.state
      }
    }
  }
}

///|
// Sole original fixed-limits rule. Constructor metadata shares this predicate;
// no input, semantic verdict, resource supplier or authority is constructed.
fn declaration_limits_invalid(limits : DeclarationLimits) -> Bool {
  limits.max_parameters < 0 ||
  limits.max_nodes < 0 ||
  limits.max_depth < 0 ||
  limits.max_text_bytes < 0
}
