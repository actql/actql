import {DuckDBTransportError} from './configuration.mjs';

// The existing physical capture retains this original typed evidence through
// preparation and one synchronous transfer. This is payload custody only;
// current authorization and issuance remain with that capture's original issuer.
export function sourceEvidenceOriginalAccess<Options, Evidence>(
  current: () => void, issue: (options: Options) => Evidence,
) {
  let evidence: Awaited<Evidence> | undefined, preparing = false;
  return Object.freeze({
    async prepare(options: Options) {
      current();
      if (preparing || evidence !== undefined) {
        throw new DuckDBTransportError('SourceEvidencePending');
      }
      preparing = true;
      try {
        const original = await issue(options);
        current();
        if (original === undefined) throw new DuckDBTransportError('SourceEvidenceUnavailable');
        evidence = original;
      } finally {preparing = false;}
    },
    take() {
      current();
      if (evidence === undefined) throw new DuckDBTransportError('SourceEvidenceUnavailable');
      const original = evidence;
      evidence = undefined;
      return original;
    },
    pending: () => preparing,
    retire() {
      if (preparing) throw new DuckDBTransportError('SourceEvidencePending');
      evidence = undefined;
    },
  });
}
