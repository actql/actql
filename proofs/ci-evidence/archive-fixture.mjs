// Independent ZIP fixtures, not archive writers used by CI.
import {deflateRawSync} from 'node:zlib';

export const storedArchive = members => archive(members, false);
export const deflatedArchive = members => archive(members, true);

function archive(members, deflated) {
  const entries = [...members];
  let offset = 0; const local = [], central = [];
  for (const [path, bytes] of entries) {
    const name = Buffer.from(path), data = Buffer.from(bytes); let crc = 0xffffffff;
    const payload = deflated ? deflateRawSync(data) : data;
    for (const byte of data) { crc ^= byte; for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0); }
    crc = (crc ^ 0xffffffff) >>> 0;
    const l = Buffer.alloc(30), c = Buffer.alloc(46);
    l.writeUInt32LE(0x04034b50); l.writeUInt16LE(20, 4); l.writeUInt16LE(0x800, 6);
    l.writeUInt16LE(deflated ? 8 : 0, 8);
    l.writeUInt32LE(crc, 14); l.writeUInt32LE(payload.length, 18); l.writeUInt32LE(data.length, 22); l.writeUInt16LE(name.length, 26);
    c.writeUInt32LE(0x02014b50); c.writeUInt16LE(0x0314, 4); c.writeUInt16LE(20, 6); c.writeUInt16LE(0x800, 8);
    c.writeUInt16LE(deflated ? 8 : 0, 10);
    c.writeUInt32LE(crc, 16); c.writeUInt32LE(payload.length, 20); c.writeUInt32LE(data.length, 24); c.writeUInt16LE(name.length, 28);
    c.writeUInt32LE((0o100644 << 16) >>> 0, 38); c.writeUInt32LE(offset, 42);
    local.push(l, name, payload); central.push(c, name); offset += l.length + name.length + payload.length;
  }
  const end = Buffer.alloc(22); end.writeUInt32LE(0x06054b50); end.writeUInt16LE(entries.length, 8); end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(Buffer.concat(central).length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([...local, ...central, end]);
}
