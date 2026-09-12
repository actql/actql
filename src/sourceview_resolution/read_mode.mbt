///|
pub(all) enum ModeIssueKind {
  InvalidLimits
  WorkLimit
  UndeclaredMode(@environment.SourceReadModeKind)
  UnsupportedWatch
  AuthoredKeyedScan
  UnboundedKeyedMode
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
  checkpoint : ModeCheckpoint?
}

///|
/// A bounded default read mode, not proof of complete keyed acquisition.
struct KeyedMode {
  selected : DirectMode
}

///|
/// Checks the mode requirements of a keyed SourceView consumer. Correlation,
/// response completeness, request fields and left-side bounds are separate.
pub fn select_keyed_mode(
  input : ResolvedInput,
  max_work : Int,
) -> Result[KeyedMode, ModeIssue] {
  let source = input.declaration.source
  if max_work < 0 {
    return Err({ kind: InvalidLimits, source, })
  }
  if max_work == 0 {
    return Err({ kind: WorkLimit, source, })
  }
  if input.declaration.scan is Some(_) {
    let cost = @decode.object_length(source).unwrap()
    if cost > max_work - 1 {
      return Err({ kind: WorkLimit, source, })
    }
    let scan = @decode.required(@decode.open_object(source).unwrap(), "scan").unwrap()
    return Err({ kind: AuthoredKeyedScan, source: scan, })
  }
  let selected = match select_direct_mode(input, max_work - 1) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  if !@environment.read_mode_bounded(selected.mode) {
    return Err({ kind: UnboundedKeyedMode, source: selected.source, })
  }
  Ok({ selected, })
}

///|
pub fn keyed_mode_input(v : KeyedMode) -> ResolvedInput {
  v.selected.input
}

///|
pub fn keyed_mode_contract(v : KeyedMode) -> @environment.SourceReadMode {
  v.selected.mode
}

///|
pub fn keyed_mode_work(v : KeyedMode) -> Int {
  v.selected.work + 1
}

///|
pub fn keyed_mode_checkpoint(v : KeyedMode) -> ModeCheckpoint? {
  v.selected.checkpoint
}

///|
pub fn keyed_mode_obligations(v : KeyedMode) -> Array[ModeObligation] {
  mode_obligations(v.selected)
}

///|
struct ModeCheckpoint {
  reference : @environment.CatalogReference
  value : @environment.ProtocolValueContract
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
    let mode_source = @environment.read_mode_source(selected)
    mode_charge(b, @decode.object_length(mode_source).unwrap(), mode_source)
    let mode_object = @decode.open_object(mode_source).unwrap()
    let checkpoint = match @decode.lookup(mode_object, "checkpoint") {
      None => None
      Some(body) => {
        mode_charge(b, @decode.object_length(body).unwrap(), body)
        let slot = @decode.required(
          @decode.open_object(body).unwrap(),
          "value_schema",
        ).unwrap()
        let values = @environment.source_view_shape_values(
          @environment.read_mode_shapes(modes),
        )
        let references = @environment.data_policy_references(
          @environment.value_contract_policies(values),
        )
        let reference = @environment.catalog_reference_for_cursor(
          references, slot,
        ).unwrap()
        let value = @environment.protocol_value_for(
          values,
          @environment.reference_contract(reference),
        ).unwrap()
        Some({ reference, value, })
      }
    }
    Ok({
      input,
      mode: selected,
      origin,
      source: location,
      work: max_work - b.work,
      checkpoint,
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
pub fn mode_checkpoint(v : DirectMode) -> ModeCheckpoint? {
  v.checkpoint
}

///|
pub fn checkpoint_reference(
  v : ModeCheckpoint,
) -> @environment.CatalogReference {
  v.reference
}

///|
pub fn checkpoint_value_contract(
  v : ModeCheckpoint,
) -> @environment.ProtocolValueContract {
  v.value
}

///|
pub fn mode_obligations(v : DirectMode) -> Array[ModeObligation] {
  match @environment.read_mode_kind(v.mode) {
    @environment.ChangesMode =>
      [RuntimeModeSupport, BoundedChangesRange, SourceStateRequirement]
    _ => [RuntimeModeSupport]
  }
}
