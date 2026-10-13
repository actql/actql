import {releasePreparedResults} from '../host-common/completed-run-publication.mjs';

// Adapt the original capture's existing Result and input-release owners into
// the common prepared cleanup owner. Every sibling is attempted independently;
// an unsuccessful release remains pending in that owner's retained retry handle.
export async function releaseInstalledRowCapture({payloads = [], releaseResults,
  releaseInputs, control}, primary) {
  const retain = release => {
    let pending = typeof release === 'function';
    let flight;
    const drain = () => {
      if (!pending) return;
      if (flight === undefined) flight = (async () => {
        if (await release() !== false) pending = false;
      })().finally(() => { flight = undefined; });
      return flight;
    };
    return Object.freeze({prepared: Object.freeze({
      release: drain, retry: drain,
      status: () => Object.freeze({pending}),
    })});
  };
  // The common owner drains in reverse. Preserve the original source/Result/
  // input order while allowing a failed source to retain only its own custody.
  await releasePreparedResults([retain(releaseInputs), retain(releaseResults),
    ...payloads.slice().reverse()], primary, control);
}
