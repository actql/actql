/- Retained native parent-core model only. ABI/layout and complete source
   coverage are correspondence premises. Selection, edge and returned objects
   remain separate obligations; this is not a replacement for count * 256. -/
namespace NativeParentCore

def slots (count : Nat) : Nat := ArrayBacking.ceiling 1 count
-- Completed storage has fixed count slots. Only its old/new Array owners
-- overlap on reset; the replacement backing is process-static and empty.
-- Output payloads remain shared child obligations, not another copy.
def envelope (count : Nat) : Nat := 664 + 16 * slots count + 8 * count

structure Footprint where
  references : Nat
  owner : Nat
  state : Nat
  callbacks : Nat
  environment : Nat
  reported : Nat
  arrayOwners : Nat
  backingHeaders : Nat
  backingSlots : Nat
  completedOwners : Nat
  completedHeaders : Nat
  completedSlots : Nat

def Footprint.bytes (s : Footprint) : Nat :=
  s.references + s.owner + s.state + s.callbacks + s.environment + s.reported +
  s.arrayOwners + s.backingHeaders + 8 * s.backingSlots +
  s.completedOwners + s.completedHeaders + 8 * s.completedSlots

theorem phase_bound (count : Nat) (s : Footprint)
    (references : s.references ≤ 80) (owner : s.owner ≤ 56) (state : s.state ≤ 56)
    (callbacks : s.callbacks ≤ 240) (environment : s.environment ≤ 80)
    (reported : s.reported ≤ 32) (owners : s.arrayOwners ≤ 48)
    (headers : s.backingHeaders ≤ 16) (backings : s.backingSlots ≤ 2 * slots count)
    (completedOwners : s.completedOwners ≤ 48) (completedHeaders : s.completedHeaders ≤ 8)
    (completedSlots : s.completedSlots ≤ count) :
    s.bytes ≤ envelope count := by
  have scaled := Nat.mul_le_mul_left 8 backings
  have completedScaled := Nat.mul_le_mul_left 8 completedSlots
  unfold Footprint.bytes envelope
  omega

-- Reuses the existing grow-at-full rule, including old/new overlap. This does
-- not pretend that a single current-buffer observation explores the overlap.
theorem growth_overlap (count old next : Nat)
    (a : old ≤ slots count) (b : next ≤ slots count) :
    8 * (old + next) ≤ 16 * slots count := by
  have sum := ArrayBacking.growth_overlap 1 count old next a b
  have scaled := Nat.mul_le_mul_left 8 sum
  omega

-- A model witness, not an implementation/GC assertion. Closed children do
-- not imply that the immutable parent callbacks and their held Refs vanished.
def retired : Footprint := ⟨64, 56, 56, 240, 80, 16, 24, 0, 0, 24, 0, 0⟩
theorem retired_owner_witness : retired.bytes = 560 := by rfl

end NativeParentCore
