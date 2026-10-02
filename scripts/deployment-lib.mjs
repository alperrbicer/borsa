import { spawnSync } from 'node:child_process'
import { closeSync, existsSync, mkdirSync, openSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { randomUUID } from 'node:crypto'
import { parseArgs } from 'node:util'

export const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
export const outputRoot = join(root, 'build/deploy')

const commandOptions = {
  doctor: [], devices: [], check: [], prepare: [],
  install: ['device', 'build', 'version', 'allow-provisioning-updates'],
  simulator: ['device', 'build', 'version'],
  archive: ['build', 'version', 'allow-provisioning-updates'],
  export: ['archive', 'allow-provisioning-updates'],
  upload: ['archive', 'build', 'version', 'allow-provisioning-updates'],
  testflight: ['archive', 'build', 'version', 'allow-provisioning-updates'],
}

export function argumentsFor(argv) {
  const args = argv.filter(value => value !== '--')
  const command = args.length && !args[0].startsWith('-') ? args.shift() : 'help'
  if (command !== 'help' && !Object.hasOwn(commandOptions, command)) throw new Error(`Unknown command: ${command}. Use --help.`)
  const { values, positionals } = parseArgs({ args, strict: true, allowPositionals: true, options: {
    help: { type: 'boolean', short: 'h' }, 'dry-run': { type: 'boolean' },
    device: { type: 'string' }, archive: { type: 'string' }, version: { type: 'string' }, build: { type: 'string' },
    'allow-provisioning-updates': { type: 'boolean' },
  } })
  if (positionals.length) {
    if (!['install', 'simulator'].includes(command) || positionals.length !== 1 || values.device) throw new Error('Pass a single device name/ID with install or simulator, or use --device.')
    values.device = positionals[0]
  }
  for (const [name, value] of Object.entries(values)) {
    if (!['help', 'dry-run'].includes(name) && !commandOptions[command]?.includes(name)) throw new Error(`--${name} does not apply to ${command}.`)
    if (typeof value === 'string' && !value.trim()) throw new Error(`--${name} requires a value.`)
  }
  if (values.version && !/^\d+(?:\.\d+){0,2}$/.test(values.version)) throw new Error('--version must look like 1.0 or 1.2.3.')
  if (values.build && !/^[1-9]\d{0,8}$/.test(values.build)) throw new Error('--build must be a positive integer with at most 9 digits.')
  if (values.archive && (values.version || values.build)) throw new Error('An existing --archive cannot change --version or --build.')
  return { command, ...values }
}

export function loadEnvironment() {
  const path = join(root, '.env.deploy')
  if (existsSync(path)) process.loadEnvFile(path)
  // Keep Swift's compilation caches with this native project.
  process.env.CLANG_MODULE_CACHE_PATH ||= join(root, 'build/ModuleCache/Clang')
  process.env.SWIFTPM_MODULECACHE_OVERRIDE ||= join(root, 'build/ModuleCache/Swift')
}

export function filePath(value) { return value.startsWith('~/') ? join(homedir(), value.slice(2)) : resolve(root, value) }
export function requireFile(path) { if (!existsSync(path)) throw new Error(`Required file not found: ${path}`); return path }
export function requireMac() { if (process.platform !== 'darwin') throw new Error('Borsa native commands require macOS and Xcode 27.'); }

export function run(command, args, { capture = false, input, dryRun = false, timeout, quiet = false, reportError = true } = {}) {
  if (!quiet) console.log(`> ${[command, ...args].map(value => JSON.stringify(String(value))).join(' ')}`)
  if (dryRun) return ''
  const result = spawnSync(command, args, { cwd: root, env: process.env, encoding: 'utf8', input,
    stdio: capture ? 'pipe' : 'inherit', maxBuffer: 32 * 1024 * 1024, timeout })
  if (result.error || result.status !== 0) {
    if (capture && reportError && result.stderr) process.stderr.write(result.stderr)
    throw new Error(`${command} failed (${result.error?.message || result.status || result.signal}). No subsequent step was started.`)
  }
  return result.stdout || ''
}

export function readPlist(path) {
  return JSON.parse(run('plutil', ['-convert', 'json', '-o', '-', requireFile(path)], { capture: true, quiet: true }))
}

export function parsePlist(xml) {
  return JSON.parse(run('plutil', ['-convert', 'json', '-o', '-', '--', '-'], { input: xml, capture: true, quiet: true }))
}

export function parseProfile(xml) {
  // Profiles contain dates and certificate data, which plutil cannot convert to JSON.
  // Extract only the fields needed to validate signing.
  const profile = {}
  for (const key of ['Entitlements', 'TeamIdentifier', 'ApplicationIdentifierPrefix', 'ExpirationDate', 'ProvisionedDevices', 'ProvisionsAllDevices']) {
    if (!xml.includes(`<key>${key}</key>`)) continue
    const format = key === 'ExpirationDate' ? 'raw' : 'json'
    const value = run('plutil', ['-extract', key, format, '-o', '-', '--', '-'], { input: xml, capture: true, quiet: true })
    profile[key] = format === 'json' ? JSON.parse(value) : value.trim()
  }
  return profile
}

export function configurationFromSettings(rows) {
  const app = rows.find(row => row.target === 'Borsa')
  if (app?.error) throw new Error(`Xcode could not resolve build settings: ${app.error}`)
  const settings = app?.buildSettings || {}
  for (const key of ['PRODUCT_BUNDLE_IDENTIFIER', 'MARKETING_VERSION', 'CURRENT_PROJECT_VERSION']) {
    if (!settings[key] || settings[key].includes('$(')) throw new Error(`Xcode did not resolve ${key}. Check Config/Base.xcconfig and Config/Local.xcconfig.`)
  }
  return { bundleId: settings.PRODUCT_BUNDLE_IDENTIFIER, team: settings.DEVELOPMENT_TEAM || '',
    version: settings.MARKETING_VERSION, build: settings.CURRENT_PROJECT_VERSION }
}

export function physicalPhones(inventory) {
  return (inventory.result?.devices || []).flatMap(device => {
    const hardware = device.hardwareProperties || device.properties?.hardware || {}
    const connection = device.connectionProperties || device.properties?.connection || {}
    const state = device.deviceProperties || device.properties?.state || {}
    if (hardware.reality !== 'physical' || connection.pairingState !== 'paired' || !/iphone/i.test(`${hardware.productType} ${hardware.deviceType}`)) return []
    return [{ id: device.identifier, udid: hardware.udid, name: state.name || 'iPhone' }]
  })
}

export function selectDevice(devices, requested) {
  const matches = requested ? devices.filter(device => [device.id, device.udid, device.name].some(value => value?.toLowerCase() === requested.toLowerCase())) : devices
  if (matches.length !== 1) throw new Error(`${matches.length ? 'Multiple devices match; specify a UDID.' : 'No matching device. Pair/unlock an iPhone or create a simulator in Xcode.'}\n${devices.map(device => `- ${device.name} | ${device.udid || device.id}`).join('\n')}`)
  if (!matches[0].id || !matches[0].udid) throw new Error('The selected device has no usable identifier.')
  return matches[0]
}

export function validateProfile(entitlements, profile, { bundleId, team, device, distribution = false, now = Date.now() }) {
  const granted = profile.Entitlements || {}
  const prefixes = profile.ApplicationIdentifierPrefix || profile.TeamIdentifier || []
  const actual = entitlements['application-identifier']
  if (!prefixes.map(prefix => `${prefix}.${bundleId}`).includes(actual)) throw new Error(`${bundleId}: application identifier mismatch in signature.`)
  const allowed = granted['application-identifier']
  const matches = typeof allowed === 'string' && (allowed === actual || (allowed.endsWith('.*') && actual.startsWith(allowed.slice(0, -1))))
  if (!matches) throw new Error(`${bundleId}: provisioning profile does not authorize the signed application identifier.`)
  if (entitlements['com.apple.developer.team-identifier'] !== team ||
      (granted['com.apple.developer.team-identifier'] && granted['com.apple.developer.team-identifier'] !== team)) {
    throw new Error(`${bundleId}: team mismatch in signature or provisioning profile.`)
  }
  if (!profile.TeamIdentifier?.includes(team) || !(Date.parse(profile.ExpirationDate) > now)) throw new Error(`${bundleId}: provisioning profile is expired or belongs to another team.`)
  if (device && !profile.ProvisionsAllDevices && !profile.ProvisionedDevices?.some(id => id.toLowerCase() === device.toLowerCase())) throw new Error(`${bundleId}: the provisioning profile does not include the selected iPhone.`)
  if (distribution && (granted['get-task-allow'] === true || entitlements['get-task-allow'] === true || profile.ProvisionedDevices || profile.ProvisionsAllDevices)) throw new Error(`${bundleId}: expected an App Store distribution profile.`)
}

export function writeJson(path, data) {
  mkdirSync(dirname(path), { recursive: true })
  const temporary = `${path}.${randomUUID()}.tmp`
  writeFileSync(temporary, `${JSON.stringify(data, null, 2)}\n`, { mode: 0o600 })
  renameSync(temporary, path)
}

export function runDirectory(label, dryRun) {
  if (dryRun) return join(outputRoot, `<${label}>`)
  const directory = join(outputRoot, `${new Date().toISOString().replace(/[:.]/g, '-')}-${label}-${randomUUID().slice(0, 6)}`)
  mkdirSync(directory, { recursive: true })
  return directory
}

export function reserveBuild(current, requested, directory = outputRoot) {
  if (!/^[1-9]\d{0,8}$/.test(String(current))) throw new Error('CURRENT_PROJECT_VERSION must be a positive integer for automatic build numbering.')
  mkdirSync(directory, { recursive: true })
  const counter = join(directory, 'last-build.json')
  const lock = join(directory, '.build-number.lock')
  let descriptor
  try { descriptor = openSync(lock, 'wx', 0o600) }
  catch (error) {
    if (error.code === 'EEXIST') throw new Error(`Another archive is reserving a number. If it stopped, remove ${lock} and retry.`)
    throw error
  }
  try {
    const previous = existsSync(counter) ? JSON.parse(readFileSync(counter, 'utf8')).build : 0
    if (!Number.isSafeInteger(previous) || previous < 0) throw new Error('Invalid local build counter; choose a build number after checking App Store Connect.')
    const build = requested ? Number(requested) : Math.max(Number(current), previous) + 1
    if (!Number.isSafeInteger(build) || build < 1 || build > 999999999) throw new Error('Invalid build number.')
    writeJson(counter, { build: Math.max(previous, build) })
    return String(build)
  } finally { closeSync(descriptor); rmSync(lock) }
}

export function exportPlist(team, destination) {
  if (!/^[A-Z0-9]{10}$/.test(team)) throw new Error('A valid DEVELOPMENT_TEAM is required. Set Config/Local.xcconfig or BORSA_TEAM_ID in .env.deploy.')
  if (!['export', 'upload'].includes(destination)) throw new Error('Invalid export destination.')
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>${destination}</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>${team}</string>
<key>manageAppVersionAndBuildNumber</key><false/>
<key>uploadSymbols</key><true/>
</dict></plist>\n`
}
