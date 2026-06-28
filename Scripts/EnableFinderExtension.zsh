#!/bin/zsh
# 脚本自述：
# - 脚本名称：EnableFinderExtension.zsh
# - 核心用途：在 Xcode 构建后注册、启用并刷新 JobsTerminalOpener Finder Sync Extension。
# - 影响范围：只影响 com.jobs.JobsTerminalOpener.FinderSyncExtension 和 Finder 进程刷新。
# - 运行提示：由 Xcode Build Phase 自动调用，不需要手动运行。

set +e

LOG_FILE="/tmp/JobsTerminalOpenerBuildPhase.log"
REFRESH_MARKER="/tmp/JobsTerminalOpenerNeedsFinderRestart"
EXTENSION_ID="com.jobs.JobsTerminalOpener.FinderSyncExtension"
APP_PROCESS_NAME="JobsTerminalOpener"
EXTENSION_PROCESS_NAME="JobsTerminalFinderSync"
APP_PATH="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
EXTENSION_PATH="${APP_PATH}/Contents/PlugIns/JobsTerminalFinderSync.appex"

# 查询当前 Finder Sync 扩展注册状态。
status_line() {
  local lines=""
  local current_line=""
  lines="$(/usr/bin/pluginkit -m -p com.apple.FinderSync -A -v 2>/dev/null | /usr/bin/grep -F "${EXTENSION_ID}" || true)"
  current_line="$(print -r -- "${lines}" | /usr/bin/grep -F "${EXTENSION_PATH}" | /usr/bin/head -n 1 || true)"
  if [[ -n "${current_line}" ]]; then
    print -r -- "${current_line}"
    return 0
  fi

  print -r -- "${lines}" | /usr/bin/head -n 1
}
# 判断外层安装脚本是否已经接管扩展注册和启用。
should_skip_build_phase_enable() {
  [[ "${JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE:-0}" == "1" ]]
}
# 外层安装脚本接管时跳过 Build Phase 内的注册副作用。
skip_enable_when_requested() {
  if should_skip_build_phase_enable; then
    echo "skip build phase enable: outer installer will register and enable Finder Sync extension"
    exit 0
  fi
}
# 停止上一轮 Xcode 调试残留的宿主 App。
stop_stale_host_app() {
  /usr/bin/pkill -x "${APP_PROCESS_NAME}" 2>/dev/null || true
  echo "stop stale host app exit=$?"
}
# 停止上一轮 Finder 挂住的扩展进程，避免 Finder 继续跑旧二进制。
stop_stale_extension_process() {
  /usr/bin/pkill -x "${EXTENSION_PROCESS_NAME}" 2>/dev/null || true
  echo "stop stale extension process exit=$?"
}
# 注册宿主 App 到 LaunchServices，让 jobsterminalopener:// 能立刻找到处理程序。
register_host_app_for_url_scheme() {
  local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  if [[ -x "${lsregister}" && -d "${APP_PATH}" ]]; then
    unregister_stale_host_apps "${lsregister}"
    "${lsregister}" -f "${APP_PATH}"
    echo "lsregister host app exit=$?"
    return 0
  fi

  echo "lsregister host app skipped"
}
# 注销旧构建产物里的宿主 App，避免 URL Scheme 被旧 App 接管。
unregister_stale_host_apps() {
  local lsregister="$1"
  local current_path=""
  local workspace_root=""
  local search_root=""
  local candidate_path=""
  current_path="$(cd "${APP_PATH}" 2>/dev/null && pwd -P)"
  workspace_root="$(cd "${SRCROOT}/.." 2>/dev/null && pwd -P)"

  for search_root in "${HOME}/Library/Developer/Xcode/DerivedData" "${workspace_root}/work"; do
    [[ -d "${search_root}" ]] || continue
    while IFS= read -r -d '' candidate_path; do
      candidate_path="$(cd "${candidate_path}" 2>/dev/null && pwd -P)"
      [[ -n "${candidate_path}" ]] || continue
      [[ "${candidate_path}" == "${current_path}" ]] && continue
      "${lsregister}" -u "${candidate_path}" 2>/dev/null || true
      echo "lsregister unregister stale host app=${candidate_path} exit=$?"
    done < <(/usr/bin/find "${search_root}" -path '*/JobsTerminalOpener.app' -type d -print0 2>/dev/null)
  done
}
# 注册当前构建产物里的 Finder Sync 扩展。
register_extension() {
  /usr/bin/pluginkit -a "${EXTENSION_PATH}"
  echo "pluginkit register exit=$?"
}
# 请求系统启用 Finder Sync 扩展。
enable_extension() {
  /usr/bin/pluginkit -e use -i "${EXTENSION_ID}"
  echo "pluginkit enable exit=$?"
}
# 等待 pluginkit 异步登记完成，并在扩展出现后再次启用到 + 状态。
wait_until_extension_enabled() {
  local attempt=""
  local line=""

  for attempt in {1..90}; do
    line="$(status_line)"
    echo "poll ${attempt}=${line}" >&2
    if [[ "${line}" == +* ]]; then
      print -r -- "${line}"
      return 0
    fi
    if [[ -n "${line}" ]]; then
      /usr/bin/pluginkit -e use -i "${EXTENSION_ID}"
      echo "pluginkit retry enable ${attempt} exit=$?" >&2
    fi
    if (( attempt % 10 == 0 )); then
      /usr/bin/pluginkit -a "${EXTENSION_PATH}"
      echo "pluginkit retry register ${attempt} exit=$?" >&2
    fi
    /bin/sleep 0.5
  done

  return 1
}
# 重启 Finder，让 Finder Sync 右键菜单缓存立刻刷新。
restart_finder() {
  echo "restart Finder for FinderSync cache"
  /usr/bin/killall Finder
  echo "killall Finder exit=$?"
}
# 完成一次构建后的扩展注册、启用和 Finder 刷新。
run_enable_flow() {
  echo "[$(/bin/date)] Enable Finder Extension"
  echo "APP_PATH=${APP_PATH}"
  echo "EXTENSION_PATH=${EXTENSION_PATH}"

  local before_line=""
  local after_line=""
  before_line="$(status_line)"
  echo "before=${before_line}"
  stop_stale_host_app
  stop_stale_extension_process
  register_host_app_for_url_scheme

  if [[ ! -d "${EXTENSION_PATH}" ]]; then
    echo "missing extension path"
    /usr/bin/touch "${REFRESH_MARKER}"
    return 0
  fi

  register_extension
  enable_extension
  after_line="$(wait_until_extension_enabled)"
  echo "after=${after_line}"

  if [[ "${after_line}" == +* ]]; then
    restart_finder
    /bin/rm -f "${REFRESH_MARKER}"
    return 0
  fi

  echo "extension not enabled after polling, keep marker for App launch"
  /usr/bin/touch "${REFRESH_MARKER}"
}
# 编排 Xcode Build Phase 自动启用扩展流程。
main() {
  skip_enable_when_requested # 外层安装脚本接管时，避免 Build Phase 重复注册并卡住构建。
  run_enable_flow # 注册并启用 Finder Sync 扩展，成功后刷新 Finder 缓存。
}

main "$@" >> "${LOG_FILE}" 2>&1
exit 0
