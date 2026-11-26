// Reads the Home Assistant app options and writes:
//   - a shell file of settings for the supervisor script
//   - the Immich config file (when "manage_settings" is on)
// Runs with the Node.js that ships in the Immich image, so the image needs
// no extra JSON tooling.

import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';

const optionsPath = process.env.AFTERIMAGE_OPTIONS || '/data/options.json';
const shareRoot = process.env.AFTERIMAGE_SHARE_ROOT || '/share';
const dataDir = process.env.AFTERIMAGE_DATA_DIR || '/data';
const envOut = process.argv[2] || '/run/afterimage/env';
const configOut = join(dataDir, 'immich-config.json');

// Immich's media location. It holds only links to the folders on the share,
// is rebuilt at every start, and must never change once a database uses it.
const mediaRoot = '/afterimage/media';

// Immich's six media folders, the option that says where each one lives on
// the share, and the default (the layout of the owner's NAS).
const folders = [
  { name: 'library', option: 'folder_library', fallback: 'library/library' },
  { name: 'upload', option: 'folder_upload', fallback: 'library/upload' },
  { name: 'thumbs', option: 'folder_thumbs', fallback: 'thumbs' },
  { name: 'encoded-video', option: 'folder_encoded_video', fallback: 'encoded-video' },
  { name: 'profile', option: 'folder_profile', fallback: 'profile' },
  { name: 'backups', option: 'folder_backups', fallback: 'backups' },
];

function fail(message) {
  console.error(`afterimage: configuration error: ${message}`);
  process.exit(64);
}

if (!existsSync(optionsPath)) {
  fail(`${optionsPath} not found. Home Assistant writes it when the app starts.`);
}

let options;
try {
  options = JSON.parse(readFileSync(optionsPath, 'utf8'));
} catch (error) {
  fail(`${optionsPath} is not valid JSON: ${error.message}`);
}

// A folder name, never a path: nothing typed into an option may point the
// storage somewhere else on the device.
function folderName(key, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    fail(`"${key}" is empty. Set it on the app's Configuration tab.`);
  }
  const name = value.trim();
  if (name === '.' || name === '..' || /[\/\\\0]/.test(name) || name.startsWith('.')) {
    fail(`"${key}" must be a plain folder name, not a path.`);
  }
  return name;
}

// A path inside the share, such as "library/upload". No "..", no absolute
// paths, no hidden folders, so it cannot leave the share.
function relativeFolder(key, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    fail(`"${key}" is empty. Set it on the app's Configuration tab.`);
  }
  const parts = value.trim().replace(/\/+$/, '').split('/');
  for (const part of parts) {
    if (part === '' || part === '.' || part === '..' || part.startsWith('.') || /[\\\0]/.test(part)) {
      fail(`"${key}" must be a folder path inside the share, like "library/upload".`);
    }
  }
  return parts.join('/');
}

const storageName = folderName('storage_name', options.storage_name);
const storageMount = join(shareRoot, storageName);

const targets = folders.map(({ name, option, fallback }) => ({
  name,
  target: join(storageMount, relativeFolder(option, options[option] ?? fallback)),
}));
const seen = new Set();
for (const { target } of targets) {
  if (seen.has(target)) {
    fail(`two Immich folders point at the same place: ${target}`);
  }
  seen.add(target);
}

const requireMount = options.require_mount !== false;
const manageSettings = options.manage_settings === true;
const logLevel = ['verbose', 'debug', 'log', 'warn', 'error'].includes(options.log_level)
  ? options.log_level
  : 'log';
const transcode = ['disabled', 'required'].includes(options.video_transcoding)
  ? options.video_transcoding
  : 'disabled';
const template =
  typeof options.storage_template === 'string' && options.storage_template.trim() !== ''
    ? options.storage_template.trim()
    : '{{y}}/{{MM}}/{{filename}}';
const dumpsKept = Number.isInteger(options.database_dumps_kept)
  ? Math.min(90, Math.max(1, options.database_dumps_kept))
  : 14;
const externalUrl = typeof options.external_url === 'string' ? options.external_url.trim() : '';
const timezone = typeof options.timezone === 'string' ? options.timezone.trim() : '';
if (timezone !== '' && !/^[A-Za-z0-9_+\-\/]+$/.test(timezone)) {
  fail('"timezone" must be a TZ identifier such as Europe/London.');
}

if (manageSettings) {
  // Every key here is taken from Immich's documented default config file.
  // Keys left out keep Immich's defaults.
  const config = {
    machineLearning: { enabled: false },
    ffmpeg: { transcode },
    job: {
      backgroundTask: { concurrency: 2 },
      library: { concurrency: 2 },
      metadataExtraction: { concurrency: 2 },
      migration: { concurrency: 2 },
      search: { concurrency: 2 },
      sidecar: { concurrency: 2 },
      thumbnailGeneration: { concurrency: 2 },
      videoConversion: { concurrency: 1 },
    },
    backup: {
      database: { enabled: true, cronExpression: '0 02 * * *', keepLastAmount: dumpsKept },
    },
    storageTemplate: { enabled: true, hashVerificationEnabled: true, template },
    newVersionCheck: { enabled: false },
    nightlyTasks: { clusterNewFaces: false },
    server: { externalDomain: externalUrl },
  };
  writeFileSync(configOut, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o644 });
}

const quote = (value) => `'${String(value).replace(/'/g, `'\\''`)}'`;
const lines = [
  `STORAGE_MOUNT=${quote(storageMount)}`,
  `MEDIA_ROOT=${quote(mediaRoot)}`,
  `FOLDER_NAMES=(${targets.map(({ name }) => quote(name)).join(' ')})`,
  `FOLDER_TARGETS=(${targets.map(({ target }) => quote(target)).join(' ')})`,
  `REQUIRE_MOUNT=${requireMount ? 'true' : 'false'}`,
  `MANAGE_SETTINGS=${manageSettings ? 'true' : 'false'}`,
  `IMMICH_CONFIG_PATH=${quote(manageSettings ? configOut : '')}`,
  `LOG_LEVEL=${quote(logLevel)}`,
  `TIMEZONE=${quote(timezone)}`,
];
mkdirSync(dirname(envOut), { recursive: true });
writeFileSync(envOut, `${lines.join('\n')}\n`, { mode: 0o600 });
