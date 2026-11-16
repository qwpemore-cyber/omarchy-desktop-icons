#!/usr/bin/env bash
set -euo pipefail

# The project is symlinked into the shell's plugin folder, and Quickshell's
# module cache can keep serving the previous QML after a plain rescan. A shell
# restart is the reliable way to see code changes while developing.
omarchy restart shell
