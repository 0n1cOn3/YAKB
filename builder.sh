#!/usr/bin/env bash
set -euo pipefail
# ----------------------------------------------------------------------
# Written by: cyberknight777
# Co-Developed by: 0n1cOn3
# Project Name: YAKB
# Current Release: v3.1-SINGLE-FILE
# ----------------------------------------------------------------------
# Copyright (c) 2022-2025 Cyber Knight
# License: GNU GENERAL PUBLIC LICENSE v3, 29 June 2007
# ----------------------------------------------------------------------

# ========== LOGGING FUNCTIONS ==========
log() { echo -e "\e[1;32m[INFO]\e[0m $*"; }
err() { echo -e "\e[1;31m[✗] ERROR:\e[0m $*" >&2; }

cleanup_on_abort() {
  echo -e "\n\e[1;33m[INFO] Aborted — Performing partial cleanup...\e[0m"

  [[ -d "${KDIR}/neutron-clang" ]] && rm -rf "${KDIR}/neutron-clang" && log "Partial Neutron-Clang cleaned."
  [[ -d "${KDIR}/out" ]] && rm -rf "${KDIR}/out" && log "Partial out/ directory cleaned."
  [[ -d "${KDIR}/anykernel3-dragonheart/modules" ]] && rm -rf "${KDIR}/anykernel3-dragonheart/modules" && log "Anykernel modules cleaned."
  [[ -d "${KDIR}/prebuilt" ]] && rm -rf "${KDIR}/prebuilt" && log "Partial prebuilt repo cleaned."
  find "${KDIR}" -type f -name ".pwd" -exec rm -f {} \;

  echo -e "\n\e[1;31m[✗] Build aborted — partial files cleaned, logs preserved.\e[0m"
  exit 1
}

# INTERRUPT SIGNAL HANDLER
trap cleanup_on_abort SIGINT SIGTERM

# ========== GLOBAL VARIABLES — FULLY HARDENED ==========

# Disable Telegram Notifications for local builds
export TELEGRAM_OVERRIDE=unset

# Kernel config
export CONFIG=dragonheart_defconfig

# Directories
KDIR=$(pwd); export KDIR

# Linker & compiler
export LINKER="ld.lld"
export DEVICE="OnePlus 7 Series"
export CODENAME="op7"
export BUILDER="cyberknight777"
export COMPILER="clang"

# Build meta info
DATE=$(date +"%Y-%m-%d"); export DATE
REPO_URL="https://github.com/cyberknight777/dragonheart_kernel_oneplus_sm8150"
COMMIT_HASH=$(git rev-parse --short HEAD); export COMMIT_HASH

# Processor count
PROCS=$(nproc --all); export PROCS

# Version file readout (with verification)
if [[ ! -f "${KDIR}/version" ]]; then
  err "version file not found! Please check https://github.com/cyberknight777/YAKB#version-file"
  exit 1
fi

KBUILD_BUILD_VERSION=$(grep num= version | cut -d= -f2)
VERSION=$(grep ver= version | cut -d= -f2)
export KBUILD_BUILD_VERSION
export KBUILD_BUILD_USER="cyberknight777"
export KBUILD_BUILD_HOST="builder"
zipn="DragonHeart-${CODENAME}-${VERSION}"
export VERSION zipn

# ========== ENVIRONMENT VARIABLE FALLBACKS ==========
export PASSWORD="${PASSWORD:-}"
export GH_TOKEN="${PASSWORD}"
export TOKEN="${TOKEN:-}"
export CHATID="${CHATID:-}"
export TGI="${TGI:-1}"

# ========== CI / DEBUG / RELEASE LOGIC ==========
export DEBUG_BUILD=0

# Detect CI environment
if [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" || "${GITLAB_CI:-}" == "true" || "${JENKINS_HOME:-}" != "" ]]; then
  log "CI environment detected — forcing Release build unless overridden"
  export DEBUG_BUILD=0
fi

# Allow external override (for local or CI debug builds)
if [[ "${YAKB_DEBUG:-}" == "1" ]]; then
  log "External override detected via YAKB_DEBUG=1 — enabling Debug mode"
  export DEBUG_BUILD=1
fi
# ========== BUILD FLAG HANDLING ==========
apply_build_flags() {
  if [[ "${DEBUG_BUILD}" == "1" ]]; then
    log "Debug Build Mode Activated"
    export KCFLAGS="-O0 -g"
  else
    log "Release Build Mode Activated"
    export KCFLAGS="-O2"
  fi
}

# Apply Debug/Release build flags immediately after detection
apply_build_flags

# ========== ENVIRONMENT CHECK ==========
env_check() {
  local args="$*"
  local missing=()

  # Skip for help & clean
  [[ "$args" == *"--help"* || "$args" == *"help"* || "$args" == *"clean"* ]] && return 0

  # Prebuilt sync requires GitHub credentials
  if [[ "$args" == *"pre="* || "$args" == *"pre "* ]]; then
    for var in PASSWORD GH_TOKEN; do
      [[ -z "${!var:-}" ]] && missing+=("$var")
    done
  fi

  # Telegram token check only if Telegram enabled
  if [[ "${TGI}" == "1" && ( "$args" == *"img"* || "$args" == *"yakbmod"* || "$args" == *"mod"* || "$args" == *"hdr"* ) ]]; then
    [[ -z "${TOKEN:-}" ]] && missing+=("TOKEN")
  fi

  if [[ ${#missing[@]} -ne 0 ]]; then
    err "Missing environment variables: ${missing[*]}"
    exit 1
  fi
}

# ========== TOOLCHAIN SETUP ==========
setup_toolchain() {
  if [[ "${COMPILER}" == "gcc" ]]; then
    [[ ! -d "${KDIR}/gcc64" ]] && git clone https://github.com/cyberknight777/gcc-arm64 --depth=1 gcc64
    [[ ! -d "${KDIR}/gcc32" ]] && git clone https://github.com/cyberknight777/gcc-arm --depth=1 gcc32

    KBUILD_COMPILER_STRING=$("${KDIR}/gcc64/bin/aarch64-elf-gcc" --version | head -n 1)
    export KBUILD_COMPILER_STRING
    export PATH="${KDIR}/gcc32/bin:${KDIR}/gcc64/bin:/usr/bin/:${PATH}"

    MAKE=(
      O=out
      CROSS_COMPILE=aarch64-elf-
      CROSS_COMPILE_ARM32=arm-eabi-
      LD="${KDIR}/gcc64/bin/aarch64-elf-${LINKER}"
      AR=aarch64-elf-ar
      AS=aarch64-elf-as
      NM=aarch64-elf-nm
      OBJDUMP=aarch64-elf-objdump
      OBJCOPY=aarch64-elf-objcopy
      CC=aarch64-elf-gcc
      KCFLAGS="${KCFLAGS}"
    )
  elif [[ "${COMPILER}" == "clang" ]]; then
    if [[ ! -f "${KDIR}/neutron-clang/bin/clang" ]]; then
      rm -rf "${KDIR}/neutron-clang"
      mkdir "${KDIR}/neutron-clang"
      cd "${KDIR}/neutron-clang" || exit 1
      bash <(curl -s "https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman") -S
      cd "${KDIR}" || exit 1
    fi

    KBUILD_COMPILER_STRING=$("${KDIR}/neutron-clang/bin/clang" -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')
    export KBUILD_COMPILER_STRING
    export PATH="${KDIR}/neutron-clang/bin/:/usr/bin/:${PATH}"

    MAKE=(
      O=out
      LLVM=1
      KCFLAGS="${KCFLAGS}"
    )
  fi
}

# ========== TELEGRAM ==========
tg() {
  [[ "${TGI}" == "0" ]] && return
  curl -sX POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d chat_id="${CHATID}" \
    -d parse_mode=Markdown \
    -d disable_web_page_preview=true \
    -d text="$1" &>/dev/null
}

tgs() {
  [[ "${TGI}" == "0" ]] && return
  local MD5
  MD5=$(md5sum "$1" | cut -d' ' -f1)
  curl -fsSL -X POST -F document=@"$1" "https://api.telegram.org/bot${TOKEN}/sendDocument" \
    -F "chat_id=${CHATID}" \
    -F "parse_mode=Markdown" \
    -F "caption=$2 | *MD5*: \`$MD5\`"
}
# ========== CORE PREPARATION ==========
prepare_build() {
  setup_toolchain
  rgn
}

# ========== BUILD: Kernel Image ==========
img() {
  prepare_build

  if [[ "${DEBUG_BUILD}" == "1" ]]; then
    "${KDIR}/scripts/config" --file "${KDIR}/out/.config" -e CONFIG_DEBUG_INFO -e CONFIG_DEBUG_KERNEL
  else
    "${KDIR}/scripts/config" --file "${KDIR}/out/.config" -d CONFIG_DEBUG_INFO -d CONFIG_DEBUG_KERNEL
  fi
  make "${MAKE[@]}" olddefconfig

  log "[*] Building Kernel..."
  local BUILD_START=$(date +%s)

  if time make -j"${PROCS}" "${MAKE[@]}" Image dtbo.img dtb.img 2>&1 | tee log.txt; then
    local BUILD_END=$(date +%s)
    local DIFF=$((BUILD_END - BUILD_START))
    tg "*Kernel built after $((DIFF / 60)) min $((DIFF % 60)) sec*"
    log "[✓] Kernel built successfully!"
    cp -p "${KDIR}/out/arch/arm64/boot/"{Image,dtb.img,dtbo.img} "${KDIR}/out/dist"
  else
    tgs "log.txt" "*Build failed*"
    err "Build Failed!"
    exit 1
  fi
}

# ========== BUILD: DTBs ==========
dtb() {
  prepare_build
  make -j"${PROCS}" "${MAKE[@]}" dtbs dtbo.img dtb.img
  cp -p "${KDIR}/out/arch/arm64/boot/"{dtb.img,dtbo.img} "${KDIR}/out/dist"
  log "[✓] DTBs built successfully."
}

# ========== BUILD: Modules ==========
mod() {
  prepare_build
  make -j"${PROCS}" "${MAKE[@]}" modules
  make "${MAKE[@]}" INSTALL_MOD_PATH="${KDIR}/out/modules" modules_install
  find "${KDIR}/out/modules" -type f -iname '*.ko' -exec cp {} "${KDIR}/anykernel3-dragonheart/modules/system/lib/modules/" \;
  log "[✓] Modules built successfully."
}

# ========== BUILD: Headers ==========
hdr() {
  prepare_build
  mkdir -p "${KDIR}/out/kernel_uapi_headers/usr"
  make -j"${PROCS}" "${MAKE[@]}" INSTALL_HDR_PATH="${KDIR}/out/kernel_uapi_headers/usr" headers_install
  find "${KDIR}/out/kernel_uapi_headers" '(' -name ..install.cmd -o -name .install ')' -exec rm '{}' +
  tar -czf "${KDIR}/out/kernel-uapi-headers.tar.gz" --directory="${KDIR}/out/kernel_uapi_headers" usr/
  cp -p "${KDIR}/out/kernel-uapi-headers.tar.gz" "${KDIR}/out/dist"
  log "[✓] Headers built successfully."
}

# ========== BUILD: YAML-Powered Vendor Module Packaging ==========
yakbmod() {
  DLKM_DIR="out/vendor_dlkm/lib/modules/0.0/vendor/lib/modules"
  VNDR_DIR="out/vendor_ramdisk/lib/modules/0.0/lib/modules"
  mkdir -p "${DLKM_DIR}" "${VNDR_DIR}" anykernel3-dragonheart/modules

  # Manual list — self-contained, no external profiles
  DLKM_MODULES=(bq25980_mmi.ko bt_drv_connac1x.ko connfem.ko fpsensor_mtk_spi.ko gps_pwr.ko)
  VNDR_MODULES=(leds-gpio.ko met.ko met_emi_api.ko met_gpu_api.ko met_ipi_api.ko)

  for mod in "${DLKM_MODULES[@]}"; do
    if cp "out/dist/${mod}" "${DLKM_DIR}/"; then
      "${KDIR}/neutron-clang/bin/llvm-strip" --strip-debug "${DLKM_DIR}/${mod}" || err "DLKM strip failed: ${mod}"
    else
      err "DLKM copy failed: ${mod}"
    fi
  done

  for mod in "${VNDR_MODULES[@]}"; do
    if cp "out/dist/${mod}" "${VNDR_DIR}/"; then
      "${KDIR}/neutron-clang/bin/llvm-strip" --strip-debug "${VNDR_DIR}/${mod}" || err "VNDR strip failed: ${mod}"
    else
      err "VNDR copy failed: ${mod}"
    fi
  done

  depmod -b "out/vendor_dlkm" 0.0
  cp out/vendor_dlkm/lib/modules/0.0/modules.{alias,dep,softdep} "${DLKM_DIR}/"
  sed -i -e 's|\\([^: ]*lib/modules/[^: ]*\\)|/\\1|g' "${DLKM_DIR}/modules.dep"
  (cd out/vendor_dlkm/lib/modules/0.0/vendor && tar -cvpf - lib/ | xz -9e -T0 > dlkm.tar.xz && mv dlkm.tar.xz "${KDIR}/anykernel3-dragonheart/modules/")

  depmod -b "out/vendor_ramdisk" 0.0
  cp out/vendor_ramdisk/lib/modules/0.0/modules.{alias,dep,softdep} "${VNDR_DIR}/"
  sed -i -e 's|\\([^: ]*lib/modules/[^: ]*\\)|/\\1|g' "${VNDR_DIR}/modules.dep"
  (cd out/vendor_ramdisk/lib/modules/0.0 && find lib | cpio -o -H newc | lz4 -l -12 --favor-decSpeed > dlkm.cpio.lz4 && mv dlkm.cpio.lz4 "${KDIR}/anykernel3-dragonheart/modules/")

  log "HARDENED embedded module packaging complete (no external profile dependency)"
}

# ========== PREBUILT SYNC (unchanged, fully integrated logic) ==========
pre() {
  local repo="${1:-}"
  if [[ -z "${repo}" ]]; then err "Repository not provided."; exit 1; fi

  log "[*] Syncing prebuilts..."
  git clone "https://github.com/${repo}.git" prebuilt
  cd prebuilt || exit 1
  echo "https://cyberknight777:${PASSWORD}@github.com" > .pwd
  git config credential.helper "store --file .pwd"
  cp -p "${KDIR}/out/dist/"{Image,dtb.img,dtbo.img} "${KDIR}/prebuilt/"
  tar -xvf "${KDIR}/out/dist/kernel-uapi-headers.tar.gz" -C "${KDIR}/prebuilt/kernel-headers/"

  for file in "${KDIR}/prebuilt/modules/vendor_boot/"*.ko; do
    filename=$(basename "${file}")
    if [[ -e "${KDIR}/out/dist/${filename}" ]]; then
      cp -p "${KDIR}/out/dist/${filename}" "${KDIR}/prebuilt/modules/vendor_boot/"
    fi
  done

  for file in "${KDIR}/prebuilt/modules/vendor_dlkm/"*.ko; do
    filename=$(basename "${file}")
    if [[ -e "${KDIR}/out/dist/${filename}" ]]; then
      cp -p "${KDIR}/out/dist/${filename}" "${KDIR}/prebuilt/modules/vendor_dlkm/"
    fi
  done

  git add Image dtb.img dtbo.img kernel-headers modules
  git commit -s -m "kernel: Update prebuilts $(date -u '+%d%m%Y%I%M')" -m "- Auto-generated commit."
  git commit --amend --reset-author --no-edit
  git push
  cd "${KDIR}" || exit 1
  rm -rf prebuilt
  log "[✓] Prebuilts updated."
}
# ========== FINAL ARGUMENT PARSER & EXECUTION ==========

if [[ "$#" -eq 0 ]]; then
  log "Interactive menu disabled in CI-safe mode."
  echo "Usage: $0 <command>"
  echo "Available commands: img, dtb, mod, hdr, yakbmod, clean, upr=V, lto=thin|full, pre=repo, --debug, --release, --notelegram"
  exit 1
fi

for arg in "$@"; do
  case "$arg" in
    img) img ;;
    dtb) dtb ;;
    mod) mod ;;
    hdr) hdr ;;
    yakbmod) yakbmod ;;
    clean) clean ;;
    upr=*) upr="${arg#*=}"; upr "$upr" ;;
    lto=*) lto="${arg#*=}"; lto "$lto" ;;
    pre=*) pre="${arg#*=}"; pre "$pre" ;;
    --debug) export DEBUG_BUILD=1; apply_build_flags ;;
    --release) export DEBUG_BUILD=0; apply_build_flags ;;
    --notelegram) export TGI=0; TELEGRAM_OVERRIDE=disabled ;;
    help|--help)
      echo "Usage: $0 <command>"
      echo "Available: img dtb mod hdr yakbmod clean upr=V lto=thin|full pre=repo --debug --release --notelegram"
      exit 0
      ;;
    *)
      err "Unknown argument: $arg"
      exit 1
      ;;
  esac
done

# After arguments parsing — Telegram override message
if [[ "${TELEGRAM_OVERRIDE}" == "disabled" ]]; then
  log "Telegram notifications disabled via --notelegram flag"
fi

# Perform final env check (hardening)
env_check "$@"
