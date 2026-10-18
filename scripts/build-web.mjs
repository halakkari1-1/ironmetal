// Copies the game files into www/ for the Android build (tools, brand sources and docs stay out).
import { cpSync, rmSync, mkdirSync } from 'node:fs';

const keep = ['index.html', 'src', 'vendor', 'assets'];
rmSync('www', { recursive: true, force: true });
mkdirSync('www');
for (const p of keep) cpSync(p, `www/${p}`, { recursive: true, filter: (src) => !src.endsWith('.glb') });
console.log('www ready:', keep.join(', '));
