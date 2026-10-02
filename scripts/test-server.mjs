#!/usr/bin/env node
import { readdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'

const root = dirname(dirname(fileURLToPath(import.meta.url)))
// Explicit files avoid Bun's repository-wide pattern scan (which also sees build artifacts).
const files = readdirSync(join(root, 'Tests/Server')).filter(name => name.endsWith('.test.mjs'))
  .sort().map(name => join(root, 'Tests/Server', name))
if (!files.length) throw new Error('Sunucu testleri bulunamadı.')
const result = spawnSync('bun', ['test', ...files, ...process.argv.slice(2)], { cwd: root, stdio: 'inherit' })
if (result.error) console.error('Bun test çalıştırıcısı başlatılamadı:', result.error.message)
process.exitCode = result.status ?? 1
