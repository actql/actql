const normative = /\b(?:MUST(?: NOT)?|SHALL(?: NOT)?|REQUIRED)\b/u;
export function normalizedParagraphs(source) {
  const lines = source.split(/\r?\n/u);
  const paragraphs = [];
  let section = '0';
  let heading = 'Preamble';
  let buffer = [];
  let inFence = false;
  let table = [];
  let informativeTable = false;
  let anchor = 'preamble';
  let normativeFence;
  let fenceLines = [];
  const flushTable = () => {
    if (table.length && !informativeTable) {
      paragraphs.push({ section, heading, text: table.join('\n'), keyword: 'NORMATIVE_TABLE', keyword_index: 0 });
    }
    table = [];
    informativeTable = false;
  };
  const flush = () => {
    const text = buffer.join(' ').replace(/\s+/gu, ' ').trim();
    if (text && normative.test(text)) {
      const sentences = text.split(/(?<=[.;!?])\s+(?=[A-Z`*])/u);
      for (const sentence of sentences) {
        const matches = [...sentence.matchAll(/\b(?:MUST(?: NOT)?|SHALL(?: NOT)?|REQUIRED)\b/gu)];
        for (const [index, match] of matches.entries()) {
          paragraphs.push({ section, heading, text: sentence, keyword: match[0], keyword_index: index });
        }
      }
    }
    buffer = [];
  };
  for (const line of lines) {
    if (inFence) {
      if (line.startsWith('```')) {
        inFence = false;
        if (normativeFence) paragraphs.push({ section: anchor, heading, text: fenceLines.join('\n'), keyword: normativeFence, keyword_index: 0 });
        normativeFence = undefined; fenceLines = [];
      } else fenceLines.push(line);
      continue;
    }
    if (table.length && !line.trimStart().startsWith('|')) flushTable();
    const anchorMatch = /^<a id="([^"]+)"><\/a>$/u.exec(line);
    if (anchorMatch) { flush(); anchor = anchorMatch[1]; continue; }
    const codeMatch = /^<!-- normative-code: (grammar|envelope|law) -->$/u.exec(line);
    if (codeMatch) { flush(); normativeFence = `NORMATIVE_${codeMatch[1].toUpperCase()}`; continue; }
    if (/^<!-- informative-table: [a-z0-9-]+ -->$/u.test(line)) {
      flush(); informativeTable = true; continue;
    }
    if (/^<!--/u.test(line)) { flush(); continue; }
    if (informativeTable && line.trim() && !line.trimStart().startsWith('|')) {
      throw new Error('informative-table annotation must immediately precede its table');
    }
    if (line.startsWith('```')) { flush(); inFence = true; continue; }
    const headingMatch = /^(#{2,4})\s+(?:Appendix\s+)?((?:\d+|[A-Z])(?:\.\d+)*)\.?(?:\s+)(.*)$/u.exec(line);
    if (headingMatch) {
      flush();
      section = headingMatch[2];
      heading = headingMatch[3];
      continue;
    }
    const localHeading = /^#{1,6}\s+(.*)$/u.exec(line);
    if (localHeading) { flush(); section = anchor; heading = localHeading[1]; continue; }
    if (!line.trim()) { flush(); continue; }
    if (line.trimStart().startsWith('|')) {
      flush();
      // One semantic table is one requirement. Include its content, not only
      // an introductory MUST, so a changed cell invalidates old evidence.
      if (!/^\s*\|(?:\s*:?-+:?\s*\|)+\s*$/u.test(line)) {
        table.push(line.trim().replace(/\s+/gu, ' '));
      }
      continue;
    }
    buffer.push(line.trim());
  }
  if (table.length) flushTable();
  if (normativeFence) throw new Error('normative-code annotation requires a complete fenced block');
  if (informativeTable) throw new Error('informative-table annotation has no table');
  flush();
  return paragraphs;
}
