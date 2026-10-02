///|
pub(all) struct Limits {
  max_work : Int
  max_inputs : Int
  max_views : Int
}

///|
pub(all) enum IssueKind {
  InvalidLimits
  WorkLimit
  InputLimit
  ViewLimit
  InvalidSourceReference
  DuplicateSelector(String)
  Unresolved
  Ambiguous(Array[String])
} derive(Eq, Debug)

///|
pub(all) struct Issue {
  kind : IssueKind
  source : @decode.Cursor?
}

///|
pub(all) enum Selection {
  Explicit
  SoleView
} derive(Eq, Debug)

///|
priv struct Owner {
  inputs : @inputs.Inputs
  catalog : @environment.SourceRequestContracts
}

///|
priv struct View {
  name : String
  cid : String
  contract : @environment.SourceViewRequestContract
}

///|
struct ResolvedInput {
  owner : Owner
  declaration : @inputs.Declaration
  selected : View
  selection : Selection
}

///|
struct Resolved {
  owner : Owner
  entries : Array[ResolvedInput]
  work : Int
}

///|
priv struct Budget {
  mut work : Int
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn resource_address(
  reference : String,
  connector : String,
  view : String,
  at : @decode.Cursor?,
) -> String raise Stop {
  let prefix = "connector://" + connector + "/"
  let suffix = "#" + view
  if reference.length() <= prefix.length() + suffix.length() {
    fail(InvalidSourceReference, at)
  }
  let start = prefix.length()
  let end = reference.length() - suffix.length()
  if reference[0:start].to_owned() != prefix ||
    reference[end:reference.length()].to_owned() != suffix {
    fail(InvalidSourceReference, at)
  }
  reference[start:end].to_owned()
}

///|
fn[T] fail(kind : IssueKind, source : @decode.Cursor?) -> T raise Stop {
  raise Stop({ kind, source, })
}

///|
fn charge(b : Budget, n : Int, source : @decode.Cursor?) -> Unit raise Stop {
  if n > b.work {
    fail(WorkLimit, source)
  }
  b.work -= n
}

///|
fn text(
  obj : @decode.ObjectView,
  key : String,
  b : Budget,
) -> String raise Stop {
  let c = @decode.required(obj, key).unwrap()
  let name = @decode.text(c).unwrap()
  charge(b, name.length(), Some(c))
  match @unicode.normalize_nfc_lf(name) {
    Ok(name) => name
    Err(_) => fail(InvalidSourceReference, Some(c))
  }
}

///|
fn candidate_names(
  candidates : Array[View],
  b : Budget,
  at : @decode.Cursor?,
) -> Array[String] raise Stop {
  let n = candidates.length()
  charge(b, n, at)
  charge(b, n, at)
  let mut names = candidates.map(v => v.name)
  let mut buffer = names.copy()
  let mut width = 1
  while width < n {
    let mut start = 0
    while start < n {
      let mid = start + (if width < n - start { width } else { n - start })
      let end = mid + (if width < n - mid { width } else { n - mid })
      let mut left = start
      let mut right = mid
      for out in start..<end {
        charge(b, 1, at)
        let take_left = if right == end {
          true
        } else if left == mid {
          false
        } else {
          charge(b, names[left].length(), at)
          charge(b, names[right].length(), at)
          @unicode.compare_utf16(names[left], names[right]) <= 0
        }
        if take_left {
          buffer[out] = names[left]
          left += 1
        } else {
          buffer[out] = names[right]
          right += 1
        }
      }
      start = end
    }
    let prior = names
    names = buffer
    buffer = prior
    if width > n / 2 {
      break
    }
    width *= 2
  }
  names
}

///|
/// Resolves all authored SourceView inputs against the complete supplied typed
/// Catalog view set. This does not select permissions, read modes or requests.
/// Work includes the preceding sourceview_input collection, plus this pass.
pub fn resolve(
  inputs : @inputs.Inputs,
  catalog : @environment.SourceRequestContracts,
  limits : Limits,
) -> Result[Resolved, Issue] {
  if limits.max_work < 0 || limits.max_inputs < 0 || limits.max_views < 0 {
    return Err({ kind: InvalidLimits, source: None, })
  }
  let count = @inputs.count(inputs)
  if count > limits.max_inputs {
    return Err({ kind: InputLimit, source: None, })
  }
  let view_count = @environment.source_request_usage(catalog).2
  if view_count > limits.max_views {
    return Err({ kind: ViewLimit, source: None, })
  }
  let b = { work: limits.max_work, }
  let owner = { inputs, catalog, }
  let entries = []
  let groups : Map[(String, String), Array[View]] = Map([])
  let exact : Map[(String, String, String), View] = Map([])
  let policies = @environment.value_contract_policies(
    @environment.source_view_shape_values(
      @environment.read_mode_shapes(
        @environment.carrier_schema_modes(
          @environment.source_request_carriers(catalog),
        ),
      ),
    ),
  )
  try {
    charge(b, @inputs.work(inputs), None)
    for i in 0..<view_count {
      let contract = @environment.source_request_at(catalog, i).unwrap()
      let root = @environment.member_body(
        @environment.source_request_member(contract),
      )
      charge(b, @decode.object_length(root).unwrap() + 1, Some(root))
      let obj = @decode.open_object(root).unwrap()
      let connector = text(obj, "connector_id", b)
      let name = text(obj, "view_id", b)
      let cid = text(obj, "contract_cid", b)
      let policy = @environment.source_view_data_policy(
        @environment.source_view_policy(
          policies,
          @environment.source_request_member(contract),
        ).unwrap(),
      )
      let reference = @environment.data_policy_source(policy)
      charge(b, reference.length(), Some(root))
      let resource = resource_address(reference, connector, name, Some(root))
      let view = { name, cid, contract, }
      if exact.contains((connector, resource, name)) {
        fail(DuplicateSelector(name), Some(root))
      }
      exact[(connector, resource, name)] = view
      match groups.get((connector, resource)) {
        Some(group) => group.push(view)
        None => groups[(connector, resource)] = [view]
      }
    }
    // No permission, request-shape, read-mode or downstream-type filtering.
    for i in 0..<count {
      let declaration = @inputs.at(inputs, i).unwrap()
      let at = Some(declaration.source)
      charge(b, 1, at)
      for name in [declaration.connector, declaration.resource] {
        charge(b, name.length(), at)
      }
      let (selected, selection) = match declaration.view {
        Some(name) => {
          charge(b, name.length(), at)
          match exact.get((declaration.connector, declaration.resource, name)) {
            Some(view) => (view, Explicit)
            None => {
              // Failure-only object indexing retains the explicit selector span.
              charge(b, @decode.object_length(declaration.source).unwrap(), at)
              let obj = @decode.open_object(declaration.source).unwrap()
              fail(Unresolved, @decode.lookup(obj, "view"))
            }
          }
        }
        None => {
          let candidates = match
            groups.get((declaration.connector, declaration.resource)) {
            Some(v) => v
            None => fail(Unresolved, at)
          }
          if candidates.length() != 1 {
            fail(Ambiguous(candidate_names(candidates, b, at)), at)
          }
          (candidates[0], SoleView)
        }
      }
      entries.push({ owner, declaration, selected, selection, })
    }
    Ok({ owner, entries, work: limits.max_work - b.work, })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn inputs(v : Resolved) -> @inputs.Inputs {
  v.owner.inputs
}

///|
pub fn catalog(v : Resolved) -> @environment.SourceRequestContracts {
  v.owner.catalog
}

///|
pub fn work(v : Resolved) -> Int {
  v.work
}

///|
pub fn count(v : Resolved) -> Int {
  v.entries.length()
}

///|
pub fn at(v : Resolved, i : Int) -> ResolvedInput? {
  v.entries.get(i)
}

///|
pub fn declaration(v : ResolvedInput) -> @inputs.Declaration {
  v.declaration
}

///|
pub fn input_owner(v : ResolvedInput) -> @inputs.Inputs {
  v.owner.inputs
}

///|
pub fn catalog_owner(v : ResolvedInput) -> @environment.SourceRequestContracts {
  v.owner.catalog
}

///|
pub fn selected_contract(
  v : ResolvedInput,
) -> @environment.SourceViewRequestContract {
  v.selected.contract
}

///|
pub fn selected_name(v : ResolvedInput) -> String {
  v.selected.name
}

///|
pub fn selected_cid(v : ResolvedInput) -> String {
  v.selected.cid
}

///|
pub fn selection(v : ResolvedInput) -> Selection {
  v.selection
}

///|
pub fn completion_rule(v : ResolvedInput) -> String? {
  match v.selection {
    Explicit => None
    SoleView => Some("actql.source.sole-view-completion")
  }
}
