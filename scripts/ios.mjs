#!/usr/bin/env node
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join, resolve, sep } from 'node:path'
import {
  argumentsFor, configurationFromSettings, exportPlist, filePath, loadEnvironment,
  outputRoot, parsePlist, parseProfile, physicalPhones, readPlist, requireFile, requireMac,
  reserveBuild, root, run, runDirectory, selectDevice, validateProfile, writeJson,
} from './deployment-lib.mjs'

const project = ['-project', join(root, 'Borsa.xcodeproj'), '-scheme', 'Borsa']
let options
let dryRun

function execute(command, args, extra = {}) { return run(command, args, { ...extra, dryRun }) }

function help() {
  console.log(`Borsa — native iOS build and deployment

Run from this project: bun run <alias> [options]
Or from any directory: node ${join(root, 'scripts/ios.mjs')} <command> [options]

Command     Bun alias                 Action
doctor      mobile:doctor             Check Xcode, signing and local profiles
devices     mobile:devices            List paired iPhones and available simulators
check       check                     Script/Swift tests + unsigned simulator build
prepare     mobile:ios:prepare        Same as check; does not install
install     mobile:ios:install        Signed Debug build, install and launch on iPhone
simulator   mobile:ios:simulator      Build, install and launch in an iPhone simulator
archive     mobile:ios:archive        Test, assign build number and create .xcarchive
export      mobile:ios:export         Export last successful archive as App Store IPA
upload      mobile:ios:upload         Archive, export/verify and upload to Apple
testflight  mobile:ios:testflight     Alias for upload

--device NAME_OR_UDID       install/simulator; required if selection is ambiguous
--version 0.1.0            install/simulator/archive/upload/testflight
--build 4                  same commands; archive otherwise increments a local counter
--archive PATH             export/upload/testflight; reuse an existing archive
--allow-provisioning-updates  Allow Xcode to update signing profiles using Apple
--dry-run                  Print the plan without running commands or writing files

Setup and examples: ${join(root, 'docs/DEPLOYMENT.md')}
Signed deployment requires an Apple Development certificate and a profile for the selected iPhone.
Upload does not submit App Review or publish the app.`)
}

function teamArguments() {
  const team = process.env.BORSA_TEAM_ID
  if (!team) return []
  if (!/^[A-Z0-9]{10}$/.test(team)) throw new Error('BORSA_TEAM_ID must be your 10-character Apple team ID.')
  return [`DEVELOPMENT_TEAM=${team}`]
}

function settings(configuration = 'Release') {
  if (dryRun) {
    console.log('Dry run: signing/team/device placeholders are not a readiness check.')
    return { bundleId: '<resolved bundle ID>',
      team: process.env.BORSA_TEAM_ID || '<DEVELOPMENT_TEAM>', version: options.version || '<MARKETING_VERSION>', build: options.build || '<CURRENT_PROJECT_VERSION>' }
  }
  mkdirSync(outputRoot, { recursive: true })
  const rows = JSON.parse(run('xcodebuild', ['-showBuildSettings', '-json', ...project,
    '-configuration', configuration, '-destination', 'generic/platform=iOS',
    '-derivedDataPath', join(outputRoot, 'settings'), 'CODE_SIGNING_ALLOWED=NO', ...teamArguments()], { capture: true, quiet: true }))
  return configurationFromSettings(rows)
}

function requireTeam(config) {
  if (!dryRun && !/^[A-Z0-9]{10}$/.test(config.team)) throw new Error('Set DEVELOPMENT_TEAM in Config/Local.xcconfig or BORSA_TEAM_ID in .env.deploy.')
}

function authentication(required = false) {
  if (dryRun) return required ? ['-authenticationKeyPath', '<AuthKey.p8>', '-authenticationKeyID', '<KEY_ID>', '-authenticationKeyIssuerID', '<ISSUER_ID>'] : []
  const id = process.env.APP_STORE_CONNECT_KEY_ID
  const issuer = process.env.APP_STORE_CONNECT_ISSUER_ID
  const customPath = process.env.APP_STORE_CONNECT_PRIVATE_KEY_PATH
  if (!required && !id && !issuer && !customPath) return []
  if (!/^[A-Z0-9]{10}$/.test(id || '') || !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(issuer || '')) {
    throw new Error('Set APP_STORE_CONNECT_KEY_ID and APP_STORE_CONNECT_ISSUER_ID in .env.deploy. See .env.deploy.example.')
  }
  const path = filePath(customPath || join(homedir(), '.appstoreconnect/private_keys', `AuthKey_${id}.p8`))
  requireFile(path)
  if (!statSync(path).isFile()) throw new Error('APP_STORE_CONNECT_PRIVATE_KEY_PATH must point to a .p8 file.')
  return ['-authenticationKeyPath', path, '-authenticationKeyID', id, '-authenticationKeyIssuerID', issuer]
}

function provisioning() {
  return options['allow-provisioning-updates'] ? ['-allowProvisioningUpdates', ...authentication()] : []
}

function phones() {
  const directory = runDirectory('devices', false)
  const path = join(directory, 'devices.json')
  try {
    run('xcrun', ['devicectl', '--timeout', '30', 'list', 'devices', '--json-output', path], { capture: true, quiet: true, timeout: 40_000 })
    return physicalPhones(JSON.parse(readFileSync(path, 'utf8')))
  } finally { rmSync(directory, { recursive: true, force: true }) }
}

function simulators() {
  const inventory = JSON.parse(run('xcrun', ['simctl', 'list', 'devices', 'available', '--json'], { capture: true, quiet: true, timeout: 30_000 }))
  return Object.values(inventory.devices || {}).flat().filter(device => device.isAvailable && /iPhone/i.test(device.name))
    .map(device => ({ id: device.udid, udid: device.udid, name: device.name, state: device.state }))
}

function showDevices() {
  if (dryRun) {
    execute('xcrun', ['devicectl', 'list', 'devices', '--json-output', '<temporary devices.json>'])
    execute('xcrun', ['simctl', 'list', 'devices', 'available', '--json'])
    return
  }
  console.log('Paired iPhones:')
  const devices = phones()
  console.log(devices.map(device => `  ${device.name} | ${device.udid}`).join('\n') || '  None. Pair/unlock the iPhone in Xcode.')
  console.log('Available iPhone simulators:')
  console.log(simulators().map(device => `  ${device.name} | ${device.udid} | ${device.state}`).join('\n') || '  None. Install a simulator runtime in Xcode.')
}

function suites() {
  execute(process.execPath, ['--test', join(root, 'Tests/Scripts/deployment.test.mjs')])
  execute(process.execPath, [join(root, 'scripts/test-server.mjs')])
  execute('xcrun', ['swift', 'test', '--jobs', '2'])
}

function buildArguments(configuration, directory, destination, config, signing = 'device') {
  return ['-quiet', ...project, '-configuration', configuration, '-destination', destination,
    '-derivedDataPath', join(directory, 'DerivedData'), ...teamArguments(),
    ...(config ? [`CURRENT_PROJECT_VERSION=${config.build}`, `MARKETING_VERSION=${config.version}`] : []),
    ...(signing === 'device' ? provisioning() : signing === 'simulator'
      ? ['CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-'] : ['CODE_SIGNING_ALLOWED=NO'])]
}

function check() {
  suites()
  const directory = runDirectory('check', dryRun)
  execute('xcodebuild', [...buildArguments('Debug', directory, 'generic/platform=iOS Simulator', null, 'none'), 'build'])
  console.log(dryRun ? 'Check plan complete.' : 'Script tests, Swift tests and unsigned iOS Simulator build passed.')
}

function verifyBundle(app, config, { device, distribution = false } = {}) {
  if (dryRun) { console.log(`Verify signature, bundle ID/version and provisioning profile: ${app}`); return }
  run('codesign', ['--verify', '--deep', '--strict', requireFile(app)], { capture: true, quiet: true })
  const info = readPlist(join(app, 'Info.plist'))
  if (info.CFBundleIdentifier !== config.bundleId || String(info.CFBundleVersion) !== config.build || info.CFBundleShortVersionString !== config.version) {
    throw new Error(`Bundle ID/version mismatch in ${app}. Rebuild the application.`)
  }
  const xml = run('codesign', ['-d', '--entitlements', '-', '--xml', app], { capture: true, quiet: true })
  if (!xml.includes('<plist')) throw new Error(`No signed entitlements found in ${app}.`)
  const profile = parseProfile(run('security', ['cms', '-D', '-i', requireFile(join(app, 'embedded.mobileprovision'))], { capture: true, quiet: true }))
  validateProfile(parsePlist(xml), profile, { ...config, device, distribution })
}

function install(simulator = false) {
  const config = settings('Debug')
  config.version = options.version || config.version
  config.build = options.build || config.build
  if (!simulator) requireTeam(config)
  let device = { id: '<device identifier>', udid: options.device || '<device UDID>', name: '<iPhone>', state: 'Shutdown' }
  if (!dryRun) {
    const devices = simulator ? simulators() : phones()
    const booted = devices.filter(item => item.state === 'Booted')
    device = selectDevice(simulator && !options.device && booted.length === 1 ? booted : devices, options.device)
  }
  const directory = runDirectory(simulator ? 'simulator' : 'install', dryRun)
  execute('xcodebuild', [...buildArguments('Debug', directory, `platform=${simulator ? 'iOS Simulator' : 'iOS'},id=${device.udid}`, config, simulator ? 'simulator' : 'device'), 'build'])
  const app = join(directory, `DerivedData/Build/Products/Debug-${simulator ? 'iphonesimulator' : 'iphoneos'}/Borsa.app`)
  if (simulator) {
    if (device.state !== 'Booted') execute('xcrun', ['simctl', 'boot', device.udid], { timeout: 60_000 })
    execute('xcrun', ['simctl', 'bootstatus', device.udid, '-b'], { timeout: 90_000 })
    execute('xcrun', ['simctl', 'install', device.udid, app])
    execute('xcrun', ['simctl', 'launch', device.udid, config.bundleId])
    // Xcode 27 exposes Device Hub; older Xcode versions expose Simulator.
    // A missing GUI must not prevent the simctl installation/launch workflow.
    try { execute('open', ['-a', 'Device Hub']) }
    catch {
      try { execute('open', ['-a', 'Simulator']) }
      catch { console.warn('Simulator is running. Open its window from Xcode to inspect the UI.') }
    }
  } else {
    verifyBundle(app, config, { device: device.udid })
    execute('xcrun', ['devicectl', '--timeout', '120', 'device', 'install', 'app', '--device', device.id, app,
      '--json-output', join(directory, 'install.json')], { timeout: 130_000 })
    console.log(dryRun ? 'Planned: install succeeded -> launch.' : 'iPhone installation succeeded; launching the app.')
    execute('xcrun', ['devicectl', '--timeout', '60', 'device', 'process', 'launch', '--device', device.id, config.bundleId,
      '--json-output', join(directory, 'launch.json')], { timeout: 70_000 })
  }
  console.log(dryRun ? 'Installation plan complete; no device was changed.' : `Install and launch commands succeeded: ${device.name}. Verify the visible screen separately.`)
}

function archive() {
  const config = settings()
  requireTeam(config)
  // Validate optional API credentials before tests/build number reservation.
  provisioning()
  suites()
  config.version = options.version || config.version
  config.build = dryRun ? options.build || '<next local build number>' : reserveBuild(config.build, options.build)
  const directory = runDirectory('archive', dryRun)
  const path = join(directory, 'Borsa.xcarchive')
  execute('xcodebuild', [...buildArguments('Release', directory, 'generic/platform=iOS', config), '-archivePath', path, 'archive'])
  verifyBundle(join(path, 'Products/Applications/Borsa.app'), config)
  const record = { archive: path, ...config, createdAt: new Date().toISOString() }
  if (!dryRun) {
    writeJson(join(directory, 'archive.json'), record)
    writeJson(join(outputRoot, 'latest-archive.json'), record)
  }
  console.log(`Archive: ${path}\nVersion: ${config.version} (${config.build})`)
  return record
}

function existingArchive() {
  let path = options.archive ? filePath(options.archive) : join(outputRoot, '<last successful archive>')
  const config = settings()
  requireTeam(config)
  if (!dryRun) {
    if (!options.archive) path = JSON.parse(readFileSync(requireFile(join(outputRoot, 'latest-archive.json')), 'utf8')).archive
    path = resolve(path)
    const archiveInfo = readPlist(join(path, 'Info.plist')).ApplicationProperties
    if (archiveInfo?.CFBundleIdentifier !== config.bundleId || archiveInfo?.Team !== config.team) throw new Error('This archive belongs to another app/team. Check the path and current Xcode settings.')
    const app = resolve(path, 'Products', archiveInfo.ApplicationPath)
    if (!app.startsWith(`${path}${sep}Products${sep}`)) throw new Error('Invalid application path inside archive metadata.')
    const info = readPlist(join(app, 'Info.plist'))
    config.version = info.CFBundleShortVersionString
    config.build = String(info.CFBundleVersion)
    verifyBundle(app, config)
  }
  return { archive: path, ...config }
}

function exportArchive(record) {
  const directory = runDirectory('export', dryRun)
  const plist = join(directory, 'ExportOptions.plist')
  if (!dryRun) writeFileSync(plist, exportPlist(record.team, 'export'))
  execute('xcodebuild', ['-exportArchive', '-archivePath', record.archive, '-exportPath', join(directory, 'ipa'),
    '-exportOptionsPlist', plist, ...provisioning()])
  let ipa = join(directory, 'ipa/Borsa.ipa')
  if (!dryRun) {
    const matches = readdirSync(join(directory, 'ipa')).filter(name => name.endsWith('.ipa'))
    if (matches.length !== 1) throw new Error('Xcode did not export exactly one IPA.')
    ipa = join(directory, 'ipa', matches[0])
    const unpack = join(directory, 'verification')
    try {
      run('ditto', ['-x', '-k', ipa, unpack], { capture: true, quiet: true })
      verifyBundle(join(unpack, 'Payload/Borsa.app'), record, { distribution: true })
    } finally { rmSync(unpack, { recursive: true, force: true }) }
    writeJson(join(directory, 'export.json'), { ...record, ipa })
  } else verifyBundle('<unpacked App Store IPA>/Payload/Borsa.app', record, { distribution: true })
  console.log(`App Store IPA: ${ipa}`)
  return ipa
}

function upload() {
  const auth = authentication(true)
  const record = options.archive ? existingArchive() : archive()
  const ipa = exportArchive(record)
  const directory = runDirectory('upload', dryRun)
  const plist = join(directory, 'UploadOptions.plist')
  if (!dryRun) writeFileSync(plist, exportPlist(record.team, 'upload'))
  // Xcode exports this same validated archive again with destination=upload.
  execute('xcodebuild', ['-exportArchive', '-archivePath', record.archive, '-exportPath', join(directory, 'result'),
    '-exportOptionsPlist', plist, ...(options['allow-provisioning-updates'] ? ['-allowProvisioningUpdates'] : []), ...auth])
  if (!dryRun) writeJson(join(directory, 'upload.json'), { ...record, validatedIpa: ipa, uploadedAt: new Date().toISOString() })
  console.log(dryRun ? 'Upload plan complete; nothing was sent to Apple.' : 'Xcode upload succeeded. Wait for App Store Connect processing, then configure TestFlight or submit App Review there. The app has not been published.')
}

function doctor() {
  if (dryRun) { console.log('Doctor would check Xcode, build settings, local certificates/profiles and API-key configuration.'); return }
  console.log(`Node ${process.version}`)
  run('xcodebuild', ['-version'])
  run('xcrun', ['swift', '--version'])
  const config = settings()
  requireTeam(config)
  console.log(`App: ${config.bundleId}\nTeam: ${config.team}\nVersion: ${config.version} (${config.build})`)
  const identities = run('security', ['find-identity', '-v', '-p', 'codesigning'], { capture: true, quiet: true })
  const hasIdentity = /[1-9]\d* valid identities found/.test(identities)
  console.log(hasIdentity ? 'Signing identity: available in the current keychain.' : 'Signing identity: not available. Configure your Apple account/certificate in Xcode.')
  const profiles = []
  let unreadableProfiles = 0
  for (const directory of [join(homedir(), 'Library/MobileDevice/Provisioning Profiles'), join(homedir(), 'Library/Developer/Xcode/UserData/Provisioning Profiles')]) {
    if (!existsSync(directory)) continue
    for (const name of readdirSync(directory).filter(name => name.endsWith('.mobileprovision'))) {
      try { profiles.push(parseProfile(run('security', ['cms', '-D', '-i', join(directory, name)], { capture: true, quiet: true, reportError: false }))) }
      catch { unreadableProfiles++ }
    }
  }
  if (unreadableProfiles) console.log(`${unreadableProfiles} local profile(s) could not be decoded; check keychain/filesystem access.`)
  const matching = profiles.filter(profile => {
    const prefix = (profile.ApplicationIdentifierPrefix || profile.TeamIdentifier || [])[0]
    const signed = { ...profile.Entitlements, 'application-identifier': `${prefix}.${config.bundleId}`,
      'com.apple.developer.team-identifier': config.team }
    try { validateProfile(signed, profile, config); return true } catch { return false }
  })
  const missingProfile = matching.length === 0
  console.log(`${config.bundleId}: ${matching.length} local, unexpired profile(s) for this app/team.`)

  try { authentication(true); console.log('Upload API key: configured (Apple permissions not checked).') }
  catch (error) { console.log(`Upload API key: ${error.message}`) }
  console.log('Local profiles do not prove device eligibility or Apple portal approval. Install/export validate the actual signed app.')
  if (missingProfile || !hasIdentity) throw new Error('Local signing prerequisites are incomplete. Configure your Apple account and Xcode signing; then retry with --allow-provisioning-updates if profiles need refreshing.')
}

try {
  options = argumentsFor(process.argv.slice(2))
  dryRun = Boolean(options['dry-run'])
  if (options.command === 'help' || options.help) help()
  else {
    loadEnvironment()
    if (!dryRun) requireMac()
    const commands = { doctor, devices: showDevices, check, prepare: check, install: () => install(false), simulator: () => install(true),
      archive, export: () => exportArchive(existingArchive()), upload, testflight: upload }
    commands[options.command]()
  }
} catch (error) {
  console.error(`\nBorsa: ${error.message}`)
  process.exitCode = 1
}
