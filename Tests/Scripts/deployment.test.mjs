import test from 'node:test'
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import {
  argumentsFor, configurationFromSettings, exportPlist, parsePlist, parseProfile,
  physicalPhones, reserveBuild, root, selectDevice, validateProfile,
} from '../../scripts/deployment-lib.mjs'

const team = 'TEAM123456'
const bundleId = 'com.example.borsa'
const config = { bundleId, team, now: Date.UTC(2026, 0, 1) }
const settings = { PRODUCT_BUNDLE_IDENTIFIER: bundleId,
  DEVELOPMENT_TEAM: team, MARKETING_VERSION: '0.1.0', CURRENT_PROJECT_VERSION: '3' }

function signing() {
  const entitlements = { 'application-identifier': `${team}.${bundleId}`, 'com.apple.developer.team-identifier': team }
  return { entitlements, profile: { Entitlements: structuredClone(entitlements), TeamIdentifier: [team],
    ApplicationIdentifierPrefix: [team], ExpirationDate: '2027-01-01T00:00:00Z' } }
}

function phone(identifier = 'core-id', udid = 'phone-udid', name = 'My iPhone') {
  return { identifier, hardwareProperties: { reality: 'physical', productType: 'iPhone18,1', udid },
    connectionProperties: { pairingState: 'paired' }, deviceProperties: { name } }
}

function temporary(t) {
  const directory = mkdtempSync(join(tmpdir(), 'borsa-deployment-test-'))
  t.after(() => rmSync(directory, { recursive: true, force: true }))
  return directory
}

function isolatedCLI(t) {
  const directory = temporary(t)
  mkdirSync(join(directory, 'scripts'))
  for (const file of ['ios.mjs', 'deployment-lib.mjs']) copyFileSync(join(root, 'scripts', file), join(directory, 'scripts', file))
  return { directory, script: join(directory, 'scripts/ios.mjs'), env: { ...process.env, BORSA_TEAM_ID: '',
    APP_STORE_CONNECT_KEY_ID: '', APP_STORE_CONNECT_ISSUER_ID: '', APP_STORE_CONNECT_PRIVATE_KEY_PATH: '' } }
}

test('CLI rejects ambiguous or incompatible arguments before doing work', () => {
  assert.equal(argumentsFor(['install', '--', 'My iPhone']).device, 'My iPhone')
  assert.equal(argumentsFor(['archive', '--build', '15', '--version', '1.2.3']).build, '15')
  for (const args of [['android'], ['install', '--device'], ['install', '--device', ''], ['install', 'one', 'two'],
    ['install', 'one', '--device', 'two'], ['archive', '--build', '0'], ['archive', '--version', '1.x'],
    ['upload', '--archive', '/a', '--build', '5'], ['export', '--version', '1.0'], ['check', '--device', 'one'], ['archive', '--skip-tests']]) {
    assert.throws(() => argumentsFor(args), undefined, args.join(' '))
  }
})

test('device discovery handles both schemas and never selects a Watch or an ambiguous iPhone', () => {
  const newer = { identifier: 'second-core-id', properties: { hardware: { reality: 'physical', deviceType: 'iPhone', udid: 'second-udid' },
    connection: { pairingState: 'paired' }, state: { name: 'Second iPhone' } } }
  const watch = phone('watch', 'watch-udid', 'Watch'); watch.hardwareProperties.productType = 'Watch7,1'
  const unpaired = phone('third'); unpaired.connectionProperties.pairingState = 'unpaired'
  const list = physicalPhones({ result: { devices: [phone(), newer, watch, unpaired] } })
  assert.equal(list.length, 2)
  assert.throws(() => selectDevice(list), /Multiple/)
  assert.equal(selectDevice(list, 'SECOND-UDID').id, 'second-core-id')
  assert.equal(selectDevice(list, 'My iPhone').udid, 'phone-udid')
  assert.throws(() => selectDevice(list, 'Watch'), /No matching/)
  assert.throws(() => selectDevice([]), /No matching/)
})

test('signature and profile must authorize the app identity and signing team', () => {
  const good = signing()
  validateProfile(good.entitlements, good.profile, config)
  for (const source of ['entitlements', 'profile']) {
    const fixture = signing()
    delete (source === 'profile' ? fixture.profile.Entitlements : fixture.entitlements)['application-identifier']
    assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, config))
  }
  const foreign = signing()
  foreign.profile.Entitlements['application-identifier'] = `${team}.com.example.other`
  assert.throws(() => validateProfile(foreign.entitlements, foreign.profile, config))
})

test('profile checks reject expired, foreign-team, unregistered-device and non-App-Store profiles', () => {
  for (const change of [fixture => { fixture.profile.ExpirationDate = '2020-01-01' },
    fixture => { fixture.profile.TeamIdentifier = ['OTHERTEAM0'] }, fixture => { fixture.entitlements['com.apple.developer.team-identifier'] = 'OTHERTEAM0' }]) {
    const fixture = signing(); change(fixture)
    assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, config))
  }
  const fixture = signing()
  assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, { ...config, device: 'my-udid' }), /selected iPhone/)
  fixture.profile.ProvisionedDevices = ['MY-UDID']
  validateProfile(fixture.entitlements, fixture.profile, { ...config, device: 'my-udid' })
  assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, { ...config, distribution: true }), /App Store/)
  delete fixture.profile.ProvisionedDevices
  fixture.profile.Entitlements['get-task-allow'] = true
  assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, { ...config, distribution: true }), /App Store/)
  delete fixture.profile.Entitlements['get-task-allow']
  fixture.profile.ProvisionsAllDevices = true
  assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, { ...config, distribution: true }), /App Store/)
})

test('wildcard profiles and legacy App ID prefixes are accepted only for authorized apps', () => {
  const fixture = signing()
  fixture.profile.ApplicationIdentifierPrefix = ['OLDPREFIX0']
  fixture.entitlements['application-identifier'] = `OLDPREFIX0.${bundleId}`
  fixture.profile.Entitlements['application-identifier'] = 'OLDPREFIX0.com.example.*'
  validateProfile(fixture.entitlements, fixture.profile, config)
  fixture.profile.Entitlements['application-identifier'] = 'OLDPREFIX0.com.unrelated.*'
  assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, config))
  fixture.profile.Entitlements['application-identifier'] = `${team}.*`
  assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, config))
})

test('Xcode settings with a zero-exit error or unresolved/missing signing fields are rejected', () => {
  assert.equal(configurationFromSettings([{ target: 'Borsa', buildSettings: settings }]).team, team)
  assert.throws(() => configurationFromSettings([{ target: 'Borsa', buildSettings: {}, error: 'PIFCache failed' }]), /PIFCache/)
  assert.throws(() => configurationFromSettings([{ target: 'Borsa', buildSettings: { ...settings, PRODUCT_BUNDLE_IDENTIFIER: '$(BORSA_BUNDLE_ID)' } }]), /resolve/)
  assert.throws(() => configurationFromSettings([{ target: 'OtherApp', buildSettings: settings }]), /resolve/)
})

test('build reservations increase across runs without changing source and refuse corrupt/locked state', t => {
  const directory = temporary(t)
  assert.equal(reserveBuild('3', undefined, directory), '4')
  assert.equal(reserveBuild('3', undefined, directory), '5')
  assert.equal(reserveBuild('3', '12', directory), '12')
  assert.equal(reserveBuild('3', '8', directory), '8')
  assert.equal(reserveBuild('3', undefined, directory), '13')
  writeFileSync(join(directory, '.build-number.lock'), '')
  assert.throws(() => reserveBuild('3', undefined, directory), /Another archive/)
  rmSync(join(directory, '.build-number.lock'))
  writeFileSync(join(directory, 'last-build.json'), '{"build":"invalid"}')
  assert.throws(() => reserveBuild('3', undefined, directory), /Invalid local/)
  assert.equal(existsSync(join(directory, '.build-number.lock')), false)
})

test('Apple plist handling accepts dates/certificates and export preserves the chosen build number', { skip: process.platform !== 'darwin' }, () => {
  const xml = `<?xml version="1.0"?><plist version="1.0"><dict>
    <key>DeveloperCertificates</key><array><data>YWJj</data></array>
    <key>ExpirationDate</key><date>2027-01-01T00:00:00Z</date>
    <key>Entitlements</key><dict><key>get-task-allow</key><false/></dict>
    <key>TeamIdentifier</key><array><string>${team}</string></array>
    <key>ProvisionedDevices</key><array><string>my-udid</string></array>
  </dict></plist>`
  const profile = parseProfile(xml)
  assert.equal(profile.ExpirationDate, '2027-01-01T00:00:00Z')
  assert.deepEqual(profile.ProvisionedDevices, ['my-udid'])
  assert.equal(profile.Entitlements['get-task-allow'], false)
  const plist = parsePlist(exportPlist(team, 'upload'))
  assert.equal(plist.method, 'app-store-connect')
  assert.equal(plist.destination, 'upload')
  assert.equal(plist.manageAppVersionAndBuildNumber, false)
})

test('every dry run works from another directory without native tools, credentials or writes', t => {
  const fixture = isolatedCLI(t)
  const env = { ...fixture.env, PATH: '/nonexistent' }
  for (const command of ['doctor', 'devices', 'check', 'prepare', 'install', 'simulator', 'archive', 'export', 'upload', 'testflight']) {
    const result = spawnSync(process.execPath, [fixture.script, command, '--dry-run'], { cwd: tmpdir(), env, encoding: 'utf8' })
    assert.equal(result.status, 0, `${command}: ${result.stderr}`)
    assert.equal(existsSync(join(fixture.directory, 'build')), false, command)
  }
  const upload = spawnSync(process.execPath, [fixture.script, 'upload', '--archive', '/a path/archive.xcarchive', '--dry-run'], { env, encoding: 'utf8' })
  assert.equal(upload.status, 0, upload.stderr)
  assert.ok(!upload.stdout.includes('"swift" "test"'), 'existing archive must not rebuild')
})

test('upload with missing API credentials fails before creating build output or running Xcode', t => {
  const fixture = isolatedCLI(t)
  const result = spawnSync(process.execPath, [fixture.script, 'upload'], { env: { ...fixture.env, PATH: '/nonexistent' }, encoding: 'utf8' })
  assert.equal(result.status, 1)
  assert.match(result.stderr, process.platform === 'darwin' ? /APP_STORE_CONNECT_KEY_ID/ : /macOS/)
  assert.equal(existsSync(join(fixture.directory, 'build')), false)
})

test('simulator installation uses ad hoc signing without requesting provisioning', t => {
  const fixture = isolatedCLI(t)
  const result = spawnSync(process.execPath, [fixture.script, 'simulator', '--dry-run'], {
    env: { ...fixture.env, PATH: '/nonexistent' }, encoding: 'utf8',
  })
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stdout, /CODE_SIGNING_ALLOWED=YES/)
  assert.match(result.stdout, /CODE_SIGN_IDENTITY=-/)
  assert.ok(!result.stdout.includes('-allowProvisioningUpdates'))
  assert.ok(result.stdout.indexOf('"install"') < result.stdout.indexOf('"launch"'))
})

test('a failed native build or ambiguous device never reaches installation or launch', { skip: process.platform !== 'darwin' }, t => {
  const fixture = isolatedCLI(t)
  const binaries = join(fixture.directory, 'bin'); mkdirSync(binaries)
  const log = join(fixture.directory, 'commands.jsonl')
  const fake = join(binaries, 'fake.mjs')
  writeFileSync(fake, `#!${process.execPath}
import { appendFileSync, writeFileSync } from 'node:fs';
import { basename } from 'node:path';
const args = process.argv.slice(2), command = basename(process.argv[1]);
appendFileSync(process.env.TEST_COMMAND_LOG, JSON.stringify({command, args}) + '\\n');
if (command === 'xcodebuild' && args.includes('-showBuildSettings')) console.log(JSON.stringify([{target:'Borsa',buildSettings:${JSON.stringify(settings)}}]));
else if (command === 'xcodebuild') process.exit(17);
else if (command === 'xcrun' && args.includes('list') && args.includes('devices')) {
 const devices = [${JSON.stringify(phone())}];
 if (process.env.TEST_AMBIGUOUS) devices.push(${JSON.stringify(phone('second', 'second-udid', 'Second iPhone'))});
 writeFileSync(args[args.indexOf('--json-output')+1], JSON.stringify({result:{devices}}));
} else process.exit(99);
`)
  chmodSync(fake, 0o755)
  for (const command of ['xcodebuild', 'xcrun']) symlinkSync(fake, join(binaries, command))
  const env = { ...fixture.env, PATH: binaries, TEST_COMMAND_LOG: log }
  const failed = spawnSync(process.execPath, [fixture.script, 'install'], { env, encoding: 'utf8' })
  assert.equal(failed.status, 1)
  assert.match(failed.stderr, /17/)
  let calls = readFileSync(log, 'utf8').trim().split('\n').map(JSON.parse)
  assert.ok(calls.some(call => call.command === 'xcodebuild' && call.args.includes('build')))
  assert.ok(!calls.some(call => call.args.includes('install') || call.args.includes('launch')))
  writeFileSync(log, '')
  const ambiguous = spawnSync(process.execPath, [fixture.script, 'install'], { env: { ...env, TEST_AMBIGUOUS: '1' }, encoding: 'utf8' })
  assert.equal(ambiguous.status, 1)
  assert.match(ambiguous.stderr, /Multiple devices/)
  calls = readFileSync(log, 'utf8').trim().split('\n').map(JSON.parse)
  assert.ok(!calls.some(call => call.args.includes('build') || call.args.includes('install') || call.args.includes('launch')))
})
