// Checks an immich-config.json the user dropped into the app's config folder
// and writes it back compact, so it can be stored as Immich's settings.
// Usage: node check-settings.mjs <input> <output>
// Exits 0 when the file is usable, 65 with a message when it is not.

import { readFileSync, statSync, writeFileSync } from 'node:fs';

const [input, output] = process.argv.slice(2);
const fail = (message) => {
  console.error(message);
  process.exit(65);
};

if (statSync(input).size > 1024 * 1024) {
  fail('it is larger than 1 MB, which is far more than Immich settings need');
}
let settings;
try {
  settings = JSON.parse(readFileSync(input, 'utf8'));
} catch (error) {
  fail(`it is not valid JSON (${error.message})`);
}
if (settings === null || typeof settings !== 'object' || Array.isArray(settings)) {
  fail('it must be a JSON object, like the file Immich exports from Administration > Settings');
}
const known = ['backup', 'ffmpeg', 'image', 'job', 'library', 'logging', 'machineLearning', 'map', 'metadata',
  'newVersionCheck', 'nightlyTasks', 'notifications', 'oauth', 'passkey', 'passwordLogin', 'reverseGeocoding',
  'server', 'storageTemplate', 'templates', 'theme', 'trash', 'user', 'integrityChecks'];
if (!Object.keys(settings).some((key) => known.includes(key))) {
  fail('none of its sections look like Immich settings (expected keys such as "job", "image", "machineLearning")');
}
writeFileSync(output, JSON.stringify(settings), { mode: 0o600 });
