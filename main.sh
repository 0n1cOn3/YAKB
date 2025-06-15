#!/usr/bin/env bash
# ----------------------------------------------------------------------
# Written by: cyberknight777
# Co-Developed by: 0n1cOn3
# Project Name: YAKB
# Current Release: v3.0
# ----------------------------------------------------------------------
# Copyright (c) 2022-2025 Cyber Knight
# License: GNU GENERAL PUBLIC LICENSE v3, 29 June 2007
# ----------------------------------------------------------------------

set -euo pipefail

# ========== ENVIRONMENT CHECK ==========
env_check() {
  local missing=()
  for var in PASSWORD TOKEN GH_TOKEN; do
    [[ -z "${!var:-}" ]] && missing+=("$var")
  done
  if [[ ${#missing[@]} -ne 0 ]]; then
    echo -e "\e[1;31m[✗] ERROR: Missing environment variables: ${missing[*]}\e[0m"
    exit 1
  fi
}
env_check

# ========== GLOBAL VARS ==========
export CONFIG=dragonheart_defconfig
KDIR=$(pwd); export KDIR
export LINKER="ld.lld"
export DEVICE="OnePlus 7 Series"
DATE=$(date +"%Y-%m-%d"); export DATE
export CODENAME="op7"
export BUILDER="cyberknight777"
export REPO_URL="https://github.com/cyberknight777/dragonheart_kernel_oneplus_sm8150"
COMMIT_HASH=$(git rev-parse --short HEAD); export COMMIT_HASH
export TGI=1
PROCS=$(nproc --all); export PROCS
export COMPILER=clang
GH_TOKEN="${PASSWORD}"; export GH_TOKEN
export PROFILE_YAML="profiles/motorola_cancunf.yaml"

# ========== BUILD TYPE HANDLING WITH CI ENV AUTODETECT ==========

# Default to release build
export DEBUG_BUILD=0

# Detect CI environments
if [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" || "${GITLAB_CI:-}" == "true" || "${JENKINS_HOME:-}" != "" ]]; then
  log "CI environment detected → Forcing Release build unless overridden"
  export DEBUG_BUILD=0
fi

# Allow external override via environment
if [[ "${YAKB_DEBUG:-}" == "1" ]]; then
  log "External override via YAKB_DEBUG=1 → Debug Build Activated"
  export DEBUG_BUILD=1
fi

apply_build_flags


# ========== SIMPLE LOGGING ==========
log() { echo -e "\e[1;32m[INFO]\e[0m $*"; }
err() { echo -e "\e[1;31m[✗] ERROR:\e[0m $*" >&2; }

# ========== PRE-FLIGHT PREP ==========
if [[ "${CI:-0}" == 0 ]]; then
  for b in dialog make curl wget unzip find zip; do
    if ! command -v "$b" >/dev/null; then
      err "Install $b!"
      exit 1
    fi
  done
fi

# ========== CLONE AND TOOLCHAIN SETUP ==========
if [[ "${COMPILER}" == "gcc" ]]; then
  if [[ ! -d "${KDIR}/gcc64" ]]; then
    git clone https://github.com/cyberknight777/gcc-arm64 --depth=1 gcc64
  fi
  if [[ ! -d "${KDIR}/gcc32" ]]; then
    git clone https://github.com/cyberknight777/gcc-arm --depth=1 gcc32
  fi
  KBUILD_COMPILER_STRING=$("${KDIR}"/gcc64/bin/aarch64-elf-gcc --version | head -n 1)
  export KBUILD_COMPILER_STRING
  export PATH="${KDIR}/gcc32/bin:${KDIR}/gcc64/bin:/usr/bin/:${PATH}"
  MAKE+=(
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
  MAKE+=(
    O=out
    LLVM=1
    KCFLAGS="${KCFLAGS}"
  )
fi

# Clone AnyKernel3 if not present
if [[ ! -d "${KDIR}/anykernel3-dragonheart/" ]]; then
  git clone --depth=1 https://github.com/cyberknight777/anykernel3 -b "${CODENAME}" anykernel3-dragonheart
fi

# Version file check
if [[ ! -f "${KDIR}/version" ]]; then
  err "version file not found!!! Read https://github.com/cyberknight777/YAKB#version-file for more information."
  exit 1
fi

KBUILD_BUILD_VERSION=$(grep num= version | cut -d= -f2)
export KBUILD_BUILD_VERSION
export KBUILD_BUILD_USER="cyberknight777"
export KBUILD_BUILD_HOST="builder"
VERSION=$(grep ver= version | cut -d= -f2)
kver="${KBUILD_BUILD_VERSION}"
zipn="DragonHeart-${CODENAME}-${VERSION}"

# ========== SIGNAL HANDLER ==========
trap 'echo -e "\n\n[✗] Received INTR call - Exiting..."; exit 0' SIGINT
# ========== TELEGRAM ==========
tg() {
  curl -sX POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d chat_id="${CHATID}" \
    -d parse_mode=Markdown \
    -d disable_web_page_preview=true \
    -d text="$1" &>/dev/null
}

tgs() {
  local MD5
  MD5=$(md5sum "$1" | cut -d' ' -f1)
  curl -fsSL -X POST -F document=@"$1" "https://api.telegram.org/bot${TOKEN}/sendDocument" \
    -F "chat_id=${CHATID}" \
    -F "parse_mode=Markdown" \
    -F "caption=$2 | *MD5*: \`$MD5\`"
}

# ========== KERNEL BUILD ==========
rgn() {
  echo -e "\n\e[1;93m[*] Regenerating defconfig! \e[0m"
  mkdir -p "${KDIR}/out/{dist,modules,kernel_uapi_headers/usr}"
  make "${MAKE[@]}" "$CONFIG"
  cp -rf "${KDIR}/out/.config" "${KDIR}/arch/arm64/configs/${CONFIG}"
  echo -e "\n\e[1;32m[✓] Defconfig regenerated! \e[0m"
}

img() {
  if [[ "${TGI}" == "1" ]]; then
    tg "
*Build Number*: \`${kver}\`
*Status*: \`${STATUS:-Development}\`
*Builder*: \`${BUILDER}\`
*Core count*: \`$(nproc --all)\`
*Device*: \`${DEVICE} [${CODENAME}]\`
*Kernel Version*: \`$(make kernelversion 2>/dev/null)\`
*Date*: \`$(date)\`
*Zip Name*: \`${zipn}\`
*Compiler*: \`${KBUILD_COMPILER_STRING}\`
*Linker*: \`$("${KDIR}/neutron-clang/bin/${LINKER}" -v | head -n1 | sed 's/(compatible with [^)]*)//' | perl -pe 's/\\(http.*?\\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')\`
*Branch*: \`$(git rev-parse --abbrev-ref HEAD)\`
*Last Commit*: [${COMMIT_HASH}](${REPO_URL}/commit/${COMMIT_HASH})
"
  fi

  rgn

  # Apply Debug Kernel Configurations
  if [[ "${DEBUG_BUILD}" == "1" ]]; then
    "${KDIR}/scripts/config" --file "${KDIR}/out/.config" -e CONFIG_DEBUG_INFO -e CONFIG_DEBUG_KERNEL
  else
    "${KDIR}/scripts/config" --file "${KDIR}/out/.config" -d CONFIG_DEBUG_INFO -d CONFIG_DEBUG_KERNEL
  fi
  make "${MAKE[@]}" olddefconfig

  echo -e "\n\e[1;93m[*] Building Kernel! \e[0m"
  local BUILD_START BUILD_END DIFF
  BUILD_START=$(date +"%s")

  if time make -j"${PROCS}" "${MAKE[@]}" Image dtbo.img dtb.img 2>&1 | tee log.txt; then
    BUILD_END=$(date +"%s")
    DIFF=$((BUILD_END - BUILD_START))
    tg "*Kernel built after $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)*"
    echo -e "\n\e[1;32m[✓] Kernel built successfully! \e[0m"
    echo -e "\n\e[1;93m[*] Copying built files! \e[0m"
    cp -p "${KDIR}/out/arch/arm64/boot/"{Image,dtb.img,dtbo.img} "${KDIR}/out/dist"
  else
    tgs "log.txt" "*Build failed*"
    err "Build Failed!"
    exit 1
  fi
}

mod() {
  if [[ "${TGI}" == "1" ]]; then
    tg "*Building Modules!*"
  fi
  rgn
  echo -e "\n\e[1;93m[*] Building Modules! \e[0m"
  make -j"${PROCS}" "${MAKE[@]}" modules
  make "${MAKE[@]}" INSTALL_MOD_PATH="${KDIR}/out/modules" modules_install
  find "${KDIR}/out/modules" -type f -iname '*.ko' -exec cp {} "${KDIR}/anykernel3-dragonheart/modules/system/lib/modules/" \;
  echo -e "\n\e[1;32m[✓] Built and copied Modules! \e[0m"
}

hdr() {
  if [[ "${TGI}" == "1" ]]; then
    tg "*Building UAPI Headers!*"
  fi
  rgn
  echo -e "\n\e[1;93m[*] Building UAPI Headers! \e[0m"
  mkdir -p "${KDIR}/out/kernel_uapi_headers/usr"
  make -j"${PROCS}" "${MAKE[@]}" INSTALL_HDR_PATH="${KDIR}/out/kernel_uapi_headers/usr" headers_install
  find "${KDIR}/out/kernel_uapi_headers" '(' -name ..install.cmd -o -name .install ')' -exec rm '{}' +
  tar -czf "${KDIR}/out/kernel-uapi-headers.tar.gz" --directory="${KDIR}/out/kernel_uapi_headers" usr/
  cp -p "${KDIR}/out/kernel-uapi-headers.tar.gz" "${KDIR}/out/dist"
  echo -e "\n\e[1;32m[✓] Headers built and copied! \e[0m"
}

clean() {
  echo -e "\n\e[1;93m[*] Cleaning source and out/ directory! \e[0m"
  make clean && make mrproper && rm -rf "${KDIR}/out"
  echo -e "\n\e[1;32m[✓] Source cleaned and out/ removed! \e[0m"
}

upr() {
  local version="${1:-}"
  if [[ -z "${version}" ]]; then err "Version not provided."; exit 1; fi
  echo -e "\n\e[1;93m[*] Bumping localversion to -DragonHeart-${version}! \e[0m"
  "${KDIR}/scripts/config" --file "${KDIR}/arch/arm64/configs/${CONFIG}" --set-str CONFIG_LOCALVERSION "-DragonHeart-${version}"
  rgn
  echo -e "\n\e[1;32m[✓] Uprev complete: -DragonHeart-${version}! \e[0m"
}

lto() {
  local mode="${1:-}"
  if [[ -z "${mode}" ]]; then err "LTO mode not specified"; exit 1; fi
  echo -e "\n\e[1;93m[*] Modifying LTO mode to ${mode}! \e[0m"
  if [[ "${mode}" == "full" ]]; then
    "${KDIR}/scripts/config" --file "${KDIR}/arch/arm64/configs/${CONFIG}" -e LTO_CLANG_FULL -d LTO_CLANG_THIN
  elif [[ "${mode}" == "thin" ]]; then
    "${KDIR}/scripts/config" --file "${KDIR}/arch/arm64/configs/${CONFIG}" -d LTO_CLANG_FULL -e LTO_CLANG_THIN
  else
    err "Incorrect LTO mode"
    exit 1
  fi
  echo -e "\n\e[1;32m[✓] LTO mode modified to ${mode}! \e[0m"
}

pre() {
  local repo="${1:-}"
  if [[ -z "${repo}" ]]; then err "Repository not provided."; exit 1; fi
  if [[ "${TGI}" == "1" ]]; then
    tg "*Copying built objects to prebuilt kernel tree!*"
  fi
  echo -e "\n\e[1;93m[*] Copying built objects to prebuilt kernel tree! \e[0m"
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
  git commit -s -m "kernel: Update prebuilts $(date -u '+%d%m%Y%I%M')" -m "- This is an auto-generated commit."
  git commit --amend --reset-author --no-edit
  git push
  cd "${KDIR}" || exit 1
  rm -rf prebuilt
  echo -e "\n\e[1;32m[✓] Prebuilts updated! \e[0m"
}
yakbmod() {
  local profile="${1:-$PROFILE_YAML}"
  [[ ! -f "${profile}" ]] && err "Profile YAML not found: ${profile}" && exit 1
  command -v yq >/dev/null || { err "yq YAML processor not found!"; exit 1; }

  mapfile -t DLKM_MODULES < <(yq '.dlkm_modules[]' "${profile}")
  mapfile -t VNDR_MODULES < <(yq '.vndr_modules[]' "${profile}")
  DLKM_URL=$(yq '.urls.dlkm_load' "${profile}")
  VNDR_URL=$(yq '.urls.vndr_load' "${profile}")

  DLKM_DIR="out/vendor_dlkm/lib/modules/0.0/vendor/lib/modules"
  VNDR_DIR="out/vendor_ramdisk/lib/modules/0.0/lib/modules"
  mkdir -p "${DLKM_DIR}" "${VNDR_DIR}" anykernel3-dragonheart/modules

  wget -q "${DLKM_URL}" -O "${DLKM_DIR}/modules.load"
  wget -q "${VNDR_URL}" -O "${VNDR_DIR}/modules.load"

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

  log "YAKB modular vendor module packaging complete (profile: ${profile})"
}

# ========== MENU HANDLER ==========
ndialog() {
  HEIGHT=16
  WIDTH=50
  CHOICE_HEIGHT=30
  BACKTITLE="Yet Another Kernel Builder"
  TITLE="YAKB v3.1 Hardened"
  MENU="Choose one:"

  OPTIONS=(
    1 "Build kernel"
    2 "Build DTBs"
    3 "Build modules"
    4 "Build kernel UAPI headers"
    5 "Copy built objects to prebuilt kernel tree"
    6 "Modify LTO mode"
    7 "Open menuconfig"
    8 "Regenerate defconfig"
    9 "Uprev localversion"
    10 "YAML Vendor Module Packaging"
    11 "Clean build tree"
    12 "Toggle Debug/Release Mode"
    13 "Exit"
  )

  CHOICE=$(dialog --clear --backtitle "$BACKTITLE" --title "$TITLE" --menu "$MENU" "$HEIGHT" "$WIDTH" "$CHOICE_HEIGHT" "${OPTIONS[@]}" 2>&1 >/dev/tty)
  clear

  case "$CHOICE" in
    1) img ;;
    2) dtb ;;
    3) mod ;;
    4) hdr ;;
    5) read -r -p "Enter prebuilt repo: " pr; pre "$pr" ;;
    6) read -r -p "Enter LTO mode (thin|full): " lt; lto "$lt" ;;
    7) mcfg ;;
    8) rgn ;;
    9) read -r -p "Enter version: " ver; upr "$ver" ;;
    10) yakbmod "$PROFILE_YAML" ;;
    11) clean; img ;;
    12)
      if [[ "${DEBUG_BUILD}" == "0" ]]; then
        export DEBUG_BUILD=1
      else
        export DEBUG_BUILD=0
      fi
      apply_build_flags
      ndialog
      ;;
    13) echo "Exiting YAKB..."; exit 0 ;;
  esac
}

# ========== ARGUMENT HANDLER ==========
if [[ "$#" -eq 0 ]]; then
  ndialog
fi

for arg in "$@"; do
  case "$arg" in
    mcfg) mcfg ;;
    img) img ;;
    dtb) dtb ;;
    mod) mod ;;
    hdr) hdr ;;
    clean) clean ;;
    yakbmod) yakbmod "$PROFILE_YAML" ;;
    rgn) rgn ;;
    --pre=*) pre="${arg#*=}"; pre "$pre" ;;
    --lto=*) lto="${arg#*=}"; lto "$lto" ;;
    --upr=*) upr="${arg#*=}"; upr "$upr" ;;
    --profile=*) PROFILE_YAML="${arg#*=}" ;;
    --debug) export DEBUG_BUILD=1; apply_build_flags ;;
    --release) export DEBUG_BUILD=0; apply_build_flags ;;
    help|--help) echo "Usage: $0 [options]"; exit 0 ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done
