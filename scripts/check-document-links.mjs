import { readFileSync } from 'node:fs';
import { walk, validateLocalLinks } from './document-validation.mjs';

let links = 0, json = 0;
const anchorCache = new Map();
for (const file of ['README.md', 'AGENTS.md', 'CLAUDE.md', ...walk('.agents/skills'),
  ...walk('docs'), ...walk('spec'), ...walk('portability')]) {
  if (file.endsWith('.json')) { JSON.parse(readFileSync(file, 'utf8')); json++; }
  if (file.endsWith('.md')) links += validateLocalLinks(file, readFileSync(file, 'utf8'), anchorCache);
}
console.log(JSON.stringify({ local_links: links, json_files: json, runtime_conformance: false }));
