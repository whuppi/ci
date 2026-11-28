#!/usr/bin/env bash
# The Android emulator on Linux and macOS: boot, wait until the framework has
# settled, then either save a snapshot or run a command.
#
#   emulator.sh snapshot          cold boot, settle, kill: the kill saves the
#                                 quick-boot snapshot the cache archives
#   emulator.sh run <command>     boot (from the snapshot when there is one),
#                                 settle, unlock, animations off, run <command>
#                                 through /tmp/emulator-run.sh, kill
#
# Env: ANDROID_HOME, API (the AVD's API level), SNAP_FLAG for `run`
# (-no-snapshot-save to resume and discard, -no-snapshot for a cold boot).
#
# Why settle, not sys.boot_completed: that property reads 1 when init has
# started the framework, while system_server is still publishing services.
# A command sent then fails with "No service published for: input", and a
# snapshot saved then holds a half-started system that every later run
# resumes: input never appears, or the guest drops off adb minutes later.
# So both commands wait for the services and the package manager first.
set -uo pipefail

SDK="${ANDROID_HOME:?ANDROID_HOME is not set}"
ADB="$SDK/platform-tools/adb"
SERIAL=emulator-5554
API="${API:?API is not set}"
BOOT_SECONDS=600
SETTLE_SECONDS=300

adb_() { "$ADB" -s "$SERIAL" "$@"; }

log() { echo "emulator.sh: $*"; }

ensure_avd() {
  [ -d "$HOME/.android/avd/test.avd" ] && return 0
  local avdmgr pkg="system-images;android-${API};aosp_atd;x86_64"
  avdmgr="$(find "$SDK/cmdline-tools" -path '*/bin/avdmanager' -type f | sed -n 1p)"
  [ -n "$avdmgr" ] || { echo "::error::avdmanager not found under $SDK/cmdline-tools"; return 1; }
  log "creating AVD test from $pkg"
  echo no | "$avdmgr" create avd --force -n test --abi x86_64 --package "$pkg" >/dev/null
}

# Starts the emulator with the given flags; returns at once.
launch() {
  log "launching with flags: ${*:-<none: save a quick-boot snapshot on kill>}"
  "$SDK/emulator/emulator" -port 5554 -avd test "$@" -no-window -noaudio -no-boot-anim \
    >/tmp/emulator-stdout.log 2>&1 &
  echo $! >/tmp/emulator.pid
}

# Stops the emulator and waits for its process, so a snapshot save finishes.
stop() {
  adb_ emu kill >/dev/null 2>&1 || true
  local pid waited=0
  pid=$(cat /tmp/emulator.pid 2>/dev/null || true)
  while [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 60 ]; do
    sleep 1; waited=$((waited + 1))
  done
  if [ -n "$pid" ]; then kill -9 "$pid" 2>/dev/null || true; fi
  "$ADB" kill-server >/dev/null 2>&1 || true
  "$ADB" start-server >/dev/null 2>&1 || true
}

service_up() { adb_ shell service check "$1" 2>/dev/null | grep "Service $1: found" >/dev/null; }

# Booted and settled within the time limits, or returns 1 with the reason.
settle() {
  local start=$SECONDS svc
  until [ "$(adb_ shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do
    [ $((SECONDS - start)) -lt "$BOOT_SECONDS" ] || { log "no boot_completed in ${BOOT_SECONDS}s"; return 1; }
    sleep 2
  done
  log "boot_completed after $((SECONDS - start))s"
  start=$SECONDS
  for svc in package activity input settings window; do
    until service_up "$svc"; do
      [ $((SECONDS - start)) -lt "$SETTLE_SECONDS" ] || { log "service $svc not published in ${SETTLE_SECONDS}s"; return 1; }
      sleep 1
    done
  done
  until [ "$(adb_ shell getprop init.svc.bootanim 2>/dev/null | tr -d '\r')" = stopped ] \
    && adb_ shell pm path android 2>/dev/null | grep '^package:' >/dev/null; do
    [ $((SECONDS - start)) -lt "$SETTLE_SECONDS" ] || { log "the package manager did not answer in ${SETTLE_SECONDS}s"; return 1; }
    sleep 1
  done
  log "settled after $((SECONDS - start))s more"
}

prepare() {
  adb_ shell input keyevent 82 || return 1
  adb_ shell settings put global window_animation_scale 0.0 || return 1
  adb_ shell settings put global transition_animation_scale 0.0 || return 1
  adb_ shell settings put global animator_duration_scale 0.0 || return 1
}

cmd="${1:-}"
case "$cmd" in
  snapshot)
    ensure_avd || exit 1
    launch
    if ! settle; then
      echo "::error::the emulator never settled; no snapshot is saved"
      tail -40 /tmp/emulator-stdout.log
      stop
      rm -rf "$HOME/.android/avd/test.avd/snapshots"
      exit 1
    fi
    # The framework keeps starting background work after the services are up;
    # a short quiet period keeps that out of the saved image.
    sleep 5
    stop
    [ -d "$HOME/.android/avd/test.avd/snapshots/default_boot" ] \
      || { echo "::error::the emulator exited without saving default_boot"; tail -40 /tmp/emulator-stdout.log; exit 1; }
    log "snapshot default_boot saved"
    ;;
  run)
    [ $# -ge 2 ] || { echo "usage: emulator.sh run <command>"; exit 2; }
    ensure_avd || exit 1
    if [ -n "${SNAP_FLAG:-}" ]; then launch "$SNAP_FLAG"; else launch; fi
    if ! settle; then
      # Nothing has run yet: a resumed snapshot that never settles is the
      # emulator's fault, so the same boot is never tried twice. A cold boot
      # ignores the snapshot.
      echo "::warning::the emulator did not settle; booting once more, cold"
      tail -40 /tmp/emulator-stdout.log
      stop
      launch -no-snapshot
      settle || { echo "::error::the emulator did not settle on a cold boot either"; tail -40 /tmp/emulator-stdout.log; stop; exit 1; }
    fi
    prepare || { echo "::error::the emulator rejected input or settings after settling"; stop; exit 1; }
    bash /tmp/emulator-run.sh "$2"
    status=$?
    stop
    exit "$status"
    ;;
  *)
    echo "usage: emulator.sh snapshot | run <command>"
    exit 2
    ;;
esac
