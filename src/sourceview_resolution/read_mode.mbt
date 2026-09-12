///|
pub(all) enum ModeIssueKind {
  InvalidLimits
  WorkLimit
  UndeclaredMode(@environment.SourceReadModeKind)
  UnsupportedWatch
} derive(Eq, Debug)

///|
pub(all) struct ModeIssue {
  kind : ModeIssueKind
  source : @decode.Cursor
}

///|
pub(all) enum ModeOrigin {
  AuthoredMode
  ContractDefault
} derive(Eq, Debug)

///|
pub(all) enum ModeObligation {
  RuntimeModeSupport
  BoundedChangesRange
  SourceStateRequirement
} derive(Eq, Debug)

///|
struct DirectMode {
  input : ResolvedInput
  mode : @environment.SourceReadMode
  origin : ModeOrigin
  source : @decode.Cursor
  work : Int
}

///|
priv suberror ModeStop {
  ModeStop(ModeIssue)
}

///|
fn mode_charge(
  b : Budget,
  n : Int,
  source : @decode.Cursor,
) -> Unit raise ModeStop {
  if n > b.work {
    raise ModeStop({ kind: WorkLimit, source, })
  }
  b.work -= n
}

///|
/// Selects the mode for a direct read, not a keyed-join access path. The result
/// retains residual range/state/runtime obligations; it is not execution permission.
/// max_work bounds this pass only; the owning resolution keeps its own usage.
pub fn select_direct_mode(
  input : ResolvedInput,
  max_work : Int,
) -> Result[DirectMode, ModeIssue] {
  let source = input.declaration.source
  if max_work < 0 {
    return Err({ kind: InvalidLimits, source, })
  }
  let b = { work: max_work, }
  let modes = @environment.carrier_schema_modes(
    @environment.source_request_carriers(input.owner.catalog),
  )
  let view = @environment.read_mode_for(
    modes,
    @environment.source_request_member(input.selected.contract),
  ).unwrap()
  try {
    mode_charge(b, 1, source)
    let (selected, origin, location) = match input.declaration.scan {
      None => {
        let selected = @environment.default_read_mode(view)
        (selected, ContractDefault, @environment.read_mode_source(selected))
      }
      Some(authored) => {
        mode_charge(b, @decode.object_length(source).unwrap(), source)
        let scan = @decode.required(
          @decode.open_object(source).unwrap(),
          "scan",
        ).unwrap()
        mode_charge(b, 1, scan)
        let location = @decode.required(
          @decode.open_object(scan).unwrap(),
          "mode",
        ).unwrap()
        let requested = match authored {
          @inputs.Snapshot => @environment.SnapshotMode
          @inputs.Changes => @environment.ChangesMode
        }
        let mut selected = None
        for i in 0..<@environment.read_mode_count(view) {
          mode_charge(b, 1, location)
          let candidate = @environment.read_mode_at(view, i).unwrap()
          if @environment.read_mode_kind(candidate) == requested {
            selected = Some(candidate)
            break
          }
        }
        let candidate = match selected {
          Some(v) => v
          None =>
            raise ModeStop({
              kind: UndeclaredMode(requested),
              source: location,
            })
        }
        (candidate, AuthoredMode, location)
      }
    }
    if @environment.read_mode_kind(selected) == @environment.WatchMode {
      return Err({ kind: UnsupportedWatch, source: location, })
    }
    Ok({
      input,
      mode: selected,
      origin,
      source: location,
      work: max_work - b.work,
    })
  } catch {
    ModeStop(e) => Err(e)
  }
}

///|
pub fn mode_input(v : DirectMode) -> ResolvedInput {
  v.input
}

///|
pub fn mode_contract(v : DirectMode) -> @environment.SourceReadMode {
  v.mode
}

///|
pub fn mode_origin(v : DirectMode) -> ModeOrigin {
  v.origin
}

///|
pub fn mode_source(v : DirectMode) -> @decode.Cursor {
  v.source
}

///|
pub fn mode_work(v : DirectMode) -> Int {
  v.work
}

///|
pub fn mode_obligations(v : DirectMode) -> Array[ModeObligation] {
  match @environment.read_mode_kind(v.mode) {
    @environment.ChangesMode =>
      [RuntimeModeSupport, BoundedChangesRange, SourceStateRequirement]
    _ => [RuntimeModeSupport]
  }
}
