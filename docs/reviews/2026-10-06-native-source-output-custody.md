# Native Source producer output custody

## Connection

The resident acquisition task previously retained its `CapturedInputSource`
and replayed `PublicationOutputExport` from that process-local capture. The
sealed-file restoration primitive alone did not cover this actual producer.

The acquired-task owner now carries a trusted output-storage factory. The
existing Native executor invokes it after binding admission, exclusive start,
Source acquisition and Source observation preparation. The factory uses the
operator's existing `retained-input-root` and the original dispatch CID. No
Program or dispatch materials can supply the storage path. A two-task Source
configuration without this physical root is refused before acquisition.

The common export traversal writes its exact canonical batches and tail to
`NativeRetainedTaskFile`, and seals with the CID and byte count already
computed by that export. It retains the same schema, ordering, physical
manifest, measurement and runtime material-generation derivation. A configured
file failure returns a physical failure; it does not fall back to replay.

Both general output reading and manifest reading use that file. Manifest
reading preserves the original chunk boundaries and verifies complete extent
and stream CID before finish. Runtime still owns reader pins and release
eligibility. File cleanup must confirm before the original Run cleanup can
complete; a replaced file is preserved and the same owner remains retryable.
The file adapter creates no reservation or second execution authority.

## Remaining boundary

This is producer physical custody, not completed holder reconstruction or
public Cloud acceptance. The exact sealed generation, content CID, output
facts and original dispatch/binding still need atomic custody in the existing
Site journal. Reconstruction must recheck current Site generation and authority,
restore the original reservation without double counting, and re-admit the
original completion through the existing owner. A missing or replaced file
must not trigger Source acquisition again.

Sender holding, independent Transfer destination holding, consumer borrow and
Named Result retention remain separate responsibilities. No Cloud adoption,
Preview deployment, old-Run resolution or normal-release acceptance is implied
by this preparation change.
