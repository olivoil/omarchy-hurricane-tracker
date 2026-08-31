import assert from "node:assert/strict"
import { once } from "node:events"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { spawn, spawnSync } from "node:child_process"
import vm from "node:vm"
import { fileURLToPath } from "node:url"

const testDir = path.dirname(fileURLToPath(import.meta.url))
const source = fs.readFileSync(path.join(testDir, "..", "Launcher.js"), "utf8")
const launcher = { String }
vm.createContext(launcher)
vm.runInContext(source, launcher)

assert.equal(launcher.dataHome("/custom/data", "/home/test"), "/custom/data")
assert.equal(launcher.dataHome("", "/home/test"), "/home/test/.local/share")
assert.equal(launcher.dataHome("relative/data", "/home/test"), "/home/test/.local/share")
assert.equal(launcher.runtimeHome("/run/user/1000", "", "/home/test"), "/run/user/1000")
assert.equal(launcher.runtimeHome("", "/custom/cache", "/home/test"), "/custom/cache")

const temporaryDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "hurricane-tracker-launcher-"))
try {
  const state = path.join(temporaryDirectory, "launcher.intent")
  const template = path.join(temporaryDirectory, "hurricane-tracker.desktop")
  const destination = path.join(temporaryDirectory, "applications", "hurricane-tracker.desktop")
  const marker = "X-Hurricane-Tracker-Managed=true"
  const icon = path.join(temporaryDirectory, "hurricane-tracker.svg")
  const runReconciler = () => {
    const result = spawnSync("sh", [
      "-c", launcher.launcherEntryScript, "sh",
      state, template, destination, marker, icon
    ], { encoding: "utf8" })
    assert.equal(result.status, 0, result.stderr)
  }

  fs.writeFileSync(template, [
    "[Desktop Entry]",
    "Name=Hurricane Tracker",
    "Icon=@ICON@",
    marker,
    ""
  ].join("\n"))

  fs.writeFileSync(state, "install\n")
  runReconciler()
  assert.match(fs.readFileSync(destination, "utf8"), new RegExp(`Icon=${icon}`))

  // Any pending worker reconciles the newest intent instead of blindly
  // completing the operation for which it was originally started.
  fs.writeFileSync(state, "remove\n")
  runReconciler()
  assert.equal(fs.existsSync(destination), false)

  fs.writeFileSync(state, "install\n")
  runReconciler()
  const blocker = spawn("sh", [
    "-c", 'exec 9>"${1}.lock"; flock 9; printf ready; read line', "sh", state
  ], { stdio: ["pipe", "pipe", "pipe"] })
  await once(blocker.stdout, "data")

  // Queue an installer behind the lock, then publish the newer remove intent.
  // Both detached workers must reconcile removal once the lock is released.
  const pendingInstall = spawn("sh", [
    "-c", launcher.launcherEntryScript, "sh",
    state, template, destination, marker, icon
  ])
  const pendingInstallExit = once(pendingInstall, "exit")
  fs.writeFileSync(state, "remove\n")
  const pendingRemove = spawn("sh", [
    "-c", launcher.launcherEntryScript, "sh",
    state, template, destination, marker, icon
  ])
  const pendingRemoveExit = once(pendingRemove, "exit")
  const blockerExit = once(blocker, "exit")
  blocker.stdin.end("\n")
  const [[blockerStatus], [installStatus], [removeStatus]] = await Promise.all([
    blockerExit, pendingInstallExit, pendingRemoveExit
  ])
  assert.equal(blockerStatus, 0)
  assert.equal(installStatus, 0)
  assert.equal(removeStatus, 0)
  assert.equal(fs.existsSync(destination), false)

  fs.mkdirSync(path.dirname(destination), { recursive: true })
  fs.writeFileSync(destination, "[Desktop Entry]\nName=User-owned entry\n")
  fs.writeFileSync(state, "install\n")
  runReconciler()
  assert.match(fs.readFileSync(destination, "utf8"), /User-owned entry/)

  fs.writeFileSync(state, "remove\n")
  runReconciler()
  assert.equal(fs.existsSync(destination), true)
} finally {
  fs.rmSync(temporaryDirectory, { recursive: true, force: true })
}
