/- One complete provider-candidate construction, under pinned ABI and source
   capture/count premises. This is neither callback execution nor a whole-parent
   bound. Sharing can only reduce this component's identity-union charge. -/
namespace ProviderConstruction

structure Footprint where
  records : Nat
  callbacks : Nat
  candidates : Nat
  defaultFamily : Nat

def Footprint.bytes (s : Footprint) : Nat :=
  s.records + s.callbacks + s.candidates + s.defaultFamily

theorem candidate_component (s : Footprint)
    (records : s.records ≤ 11 * 40) (callbacks : s.callbacks ≤ 44 * 40)
    (candidates : s.candidates ≤ 120) (family : s.defaultFamily ≤ 24) :
    s.bytes ≤ 2344 := by
  unfold Footprint.bytes
  omega

-- A conditional composition with the retained core, allowing shared identity
-- to reduce the union. Selected-input/edge/child/poll objects remain separate.
theorem retained_core_union (count : Nat) (registry : RelationCapacity.Registry)
    (coreLive selectionLive : Nat → Bool)
    (core : NativeParentCore.Footprint) (selection : Footprint)
    (coreBound : core.bytes ≤ NativeParentCore.envelope count)
    (selectionBound : selection.bytes ≤ 2344)
    (coreCoverage : RelationCapacity.charge registry.ids registry.size coreLive ≤ core.bytes)
    (selectionCoverage : RelationCapacity.charge registry.ids registry.size selectionLive ≤ selection.bytes) :
    RelationCapacity.charge registry.ids registry.size
      (fun id => coreLive id || selectionLive id) ≤
        NativeParentCore.envelope count + 2344 := by
  have unionBound := RelationCapacity.charge_union registry.ids registry.size coreLive selectionLive
  omega

end ProviderConstruction
