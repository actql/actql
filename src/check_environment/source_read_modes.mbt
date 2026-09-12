///|
pub(all) enum SourceReadModeKind {
  SnapshotMode
  ChangesMode
  WatchMode
} derive(Eq, Debug)

///|
pub(all) enum SourceReadModeIssueKind {
  InvalidLimits
  WorkLimit
  DuplicateMode(SourceReadModeKind)
  UndeclaredDefault
  InvalidBoundedness(SourceReadModeKind)
  MissingCheckpoint(SourceReadModeKind)
} derive(Eq, Debug)

///|
pub(all) struct SourceReadModeIssue {
  kind : SourceReadModeIssueKind
  source : @decode.Cursor?
}

///|
struct SourceReadMode {
  source : @decode.Cursor
  kind : SourceReadModeKind
  bounded : Bool
}

///|
struct SourceViewModes {
  item : Member
  modes : Array[SourceReadMode]
  default_mode : SourceReadMode
}

///|
struct SourceReadModes {
  shapes : SourceViewShapes
  views : Array[SourceViewModes]
  work : Int
}

///|
priv suberror ReadModeStop {
  ReadModeStop(SourceReadModeIssue)
}

///|
priv struct ReadModeBudget {
  mut remaining : Int
}

///|
fn[T] mode_fail(
  kind : SourceReadModeIssueKind,
  source : @decode.Cursor,
) -> T raise ReadModeStop {
  raise ReadModeStop({ kind, source: Some(source), })
}

///|
fn mode_charge(
  b : ReadModeBudget,
  n : Int,
  c : @decode.Cursor,
) -> Unit raise ReadModeStop {
  if n > b.remaining {
    mode_fail(WorkLimit, c)
  }
  b.remaining -= n
}

///|
fn mode_kind(text : String) -> SourceReadModeKind {
  match text {
    "snapshot" => SnapshotMode
    "changes" => ChangesMode
    _ => WatchMode
  }
}

///|
// The enclosing opaque shape proof guarantees closed objects, enum spellings,
// booleans and correctly shaped checkpoint references before this pass.
fn check_read_mode_body(
  c : @decode.Cursor,
  budget : ReadModeBudget,
) -> (Array[SourceReadMode], SourceReadMode) raise ReadModeStop {
  mode_charge(budget, @decode.object_length(c).unwrap() + 1, c)
  let acquisition = @decode.open_object(c).unwrap()
  let default_cursor = @decode.required(acquisition, "default_mode").unwrap()
  let default_kind = mode_kind(@decode.text(default_cursor).unwrap())
  let list = @decode.required(acquisition, "modes").unwrap()
  let count = @decode.array_length(list).unwrap()
  let modes = []
  let seen : Map[String, Bool] = Map([])
  let mut selected = None
  for i in 0..<count {
    let source = @decode.element_at(list, i).unwrap()
    mode_charge(budget, @decode.object_length(source).unwrap() + 1, source)
    let object = @decode.open_object(source).unwrap()
    let name = @decode.required(object, "mode").unwrap()
    let text = @decode.text(name).unwrap()
    let kind = mode_kind(text)
    if seen.contains(text) {
      mode_fail(DuplicateMode(kind), name)
    }
    seen[text] = true
    let bounded_cursor = @decode.required(object, "bounded").unwrap()
    let bounded = @decode.boolean(bounded_cursor).unwrap()
    if (kind == SnapshotMode && !bounded) || (kind == WatchMode && bounded) {
      mode_fail(InvalidBoundedness(kind), bounded_cursor)
    }
    if kind != SnapshotMode && @decode.lookup(object, "checkpoint") is None {
      mode_fail(MissingCheckpoint(kind), source)
    }
    let value = { source, kind, bounded, }
    modes.push(value)
    if kind == default_kind {
      selected = Some(value)
    }
  }
  match selected {
    Some(v) => (modes, v)
    None => mode_fail(UndeclaredDefault, default_cursor)
  }
}

///|
/// Validates advertised modes, not a Program's selected acquisition. Watch and
/// unbounded changes may be advertised without being executable in this profile.
pub fn check_source_read_modes(
  shapes : SourceViewShapes,
  max_work : Int,
) -> Result[SourceReadModes, SourceReadModeIssue] {
  if max_work < 0 {
    return Err({ kind: InvalidLimits, source: None, })
  }
  let budget = { remaining: max_work, }
  let views = []
  try {
    for item in shapes.views {
      let root = member_body(item)
      mode_charge(budget, @decode.object_length(root).unwrap() + 1, root)
      let obj = @decode.open_object(root).unwrap()
      let (modes, default_mode) = check_read_mode_body(
        @decode.required(obj, "acquisition").unwrap(),
        budget,
      )
      views.push({ item, modes, default_mode, })
    }
    Ok({ shapes, views, work: max_work - budget.remaining, })
  } catch {
    ReadModeStop(e) => Err(e)
  }
}

///|
pub fn read_mode_shapes(v : SourceReadModes) -> SourceViewShapes {
  v.shapes
}

///|
pub fn read_mode_usage(v : SourceReadModes) -> (Int, Int) {
  (v.work, v.views.length())
}

///|
pub fn read_mode_view_at(v : SourceReadModes, i : Int) -> SourceViewModes? {
  v.views.get(i)
}

///|
pub fn read_mode_member(v : SourceViewModes) -> Member {
  v.item
}

///|
pub fn read_mode_at(v : SourceViewModes, i : Int) -> SourceReadMode? {
  v.modes.get(i)
}

///|
pub fn read_mode_count(v : SourceViewModes) -> Int {
  v.modes.length()
}

///|
pub fn default_read_mode(v : SourceViewModes) -> SourceReadMode {
  v.default_mode
}

///|
pub fn read_mode_kind(v : SourceReadMode) -> SourceReadModeKind {
  v.kind
}

///|
pub fn read_mode_bounded(v : SourceReadMode) -> Bool {
  v.bounded
}

///|
pub fn read_mode_source(v : SourceReadMode) -> @decode.Cursor {
  v.source
}
