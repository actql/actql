# Checked Effect binding

This pure downstream layer retains the opaque static candidates issued by
`program_check` and binds them to the existing Run publication admission,
Invocation and Preview owners. It does not issue execution or apply authority.

The Checker owns computation checks and the complete static Effect inventory.
This package uses its existing read-only projections; it neither reconstructs a
checked candidate from CIDs nor publishes constructors for bound handles. The
existing publication and Effect owners still perform identity and footprint
validation with the same limits and canonical contracts.

The Host facades keep their existing names. Their MoonBit consumers use this
package for concrete binding and `program_check` for static inspection.
