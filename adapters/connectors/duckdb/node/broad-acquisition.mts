// One broad row receipt; filter/select are the acquisition's Local residual.
// The trusted MoonBit port owns catalog, value and retention validation.
import { withSourceAcquisition } from './source-acquisition.mjs';
import type {
  SourceAccounting, SourceChunk, SourceFields, SourceLimits, SourceParameters, SourceReceiptPort,
} from './source-acquisition.mjs';

export type BroadAcquisitionPort = SourceReceiptPort & Readonly<{
  scanSql(): string;
  beginReceipt(fields: SourceFields, readView: object): unknown;
  acceptChunk(chunk: SourceChunk, readView: object): unknown;
  finishReceipt(readView: object): unknown;
}>;

export async function runBroadAcquisition(grant: object, port: BroadAcquisitionPort, limits: SourceLimits,
  signal?: AbortSignal, accounting?: SourceAccounting) {
  return await withSourceAcquisition(grant, port, limits, signal, async (session, readView) => {
    const metadata = await session.command(port.metadataSql(), port.metadataParameters(),
      chunk => port.acceptMetadata(chunk, readView));
    await port.finishMetadata(metadata, readView);
    const before = session.usage();
    let begun = false;
    const begin = async (fields: SourceFields) => { await port.beginReceipt(fields, readView); begun = true; };
    const fields = await session.command(port.scanSql(), [], async chunk => {
      if (!begun) await begin(chunk.fields);
      await port.acceptChunk(chunk, readView);
    });
    if (!begun) await begin(fields);
    const accepted = await port.finishReceipt(readView);
    const after = session.usage();
    const transport = Object.freeze(Object.fromEntries(
      Object.keys(before).map(key => [key, after[key as keyof typeof after] - before[key as keyof typeof before]]),
    ));
    return Object.freeze({ readView, accepted, transport });
  }, accounting);
}
