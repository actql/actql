/- Conditional native Map object extents. The ABI profile, compiler field
   layout and object identity are implementation correspondence obligations.
   Allocator arenas, borrowed referents and collector buffers are not included. -/
namespace NativeMapExtent

def extent (slots entries : Nat) : Nat := 48 + 8 + 8 * slots + 48 * entries
def admitted (maximum : Nat) : Nat := extent 8 maximum

theorem table_bound (slots entries maximum : Nat)
    (table : slots = 8) (keys : entries ≤ maximum) :
    extent slots entries ≤ admitted maximum := by
  simp only [admitted, extent]
  omega

theorem empty_extent : admitted 0 = 120 := rfl

theorem current_distinct (width : Nat) :
    2 * admitted width + admitted 0 = 360 + 96 * width := by
  unfold admitted extent
  omega

end NativeMapExtent
