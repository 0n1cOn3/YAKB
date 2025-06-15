# YAKB — Yet Another Kernel Builder (v3.0)

YAKB is an modular Android kernel build and vendor module packaging system written in Bash.

- -Two-way UX:- Use as an argument-based CLI tool or via an interactive menu.
- -Profile-driven:- Supports YAML profile definitions for modular vendor (DLKM/VNDR) packaging.
- -Enterprise-Grade:- Integrated error handling, CI compliance, and advanced logging.
- OTA, Telegram, and GitHub Release flows fully supported.

## 🚀 Usage

### Preparation

Edit `main.sh` and YAML profiles as needed.

- All variables are commented inline for clarity.
- Modular device/vendor profiles are found in `profiles/`.

### CLI

```bash
bash main.sh img mkzip
```

This builds the kernel and produces an AnyKernel3 zip.

```bash
bash main.sh yakbmod
```

Or with a custom device profile:

```bash
bash main.sh yakbmod --profile=profiles/your_device.yaml
```

### Menu

```bash
bash main.sh
```

Runs the interactive menu with all build, packaging, and uprev options.

## 🧑‍💻 Features

- Argument-based and menu-based usage
- YAML-driven vendor module factory (yakbmod) for dynamic device profiles
- Full error code/explanation summary at the end of each run
- CI-compatible: works non-interactively, logs all errors for audit and reproducibility
- Preserves OTA, Telegram, and GitHub flows
- Hardened for both CI/CD and interactive workflows

## 🛠 Supported Compilers

- EvaGCC 12.0.0
- Proton Clang 13.0.0
- Neutron Clang 17.0.0
- Any custom Clang toolchain
- Any custom GCC toolchain with GNU binutils

## 📦 Requirements

- bash
- yq (YAML processor, v4+)
- dialog
- make
- curl
- wget
- unzip
- find
- zip
- tar
- xz
- lz4
- cpio
- Clang or GCC toolchain (see above)

### Environment variables for CI/CD

- `PASSWORD`
- `TOKEN`
- `GH_TOKEN`

## 📋 Error Handling

- Each major step uses error codes and explanations.
- Execution continues on error while logging issues.
- Final summary displays all encountered errors.
- `CI_STRICT=1` exits on first error in CI/CD strict mode.

## 📓 Device Profiles

YAML profiles reside under `profiles/` and define module packaging, URLs, and device-specific lists.

Example profile file:

```bash
profiles/motorola_cancunf.yaml
```

## 🛠️ Integrations

- OTA JSON/Release logic supported out-of-the-box
- Telegram API integration (requires `TOKEN`)
- GitHub Releases support (requires `GH_TOKEN`)

## 📖 Documentation

- See comments in `main.sh` for configuration details.
- See `profiles/` for modular device definitions.

## 🤝 Contributing

- PRs, bugfixes, and device profiles are welcome.
- Issues for CI/CD improvements or new device support are encouraged.

## Misc

- Version file

Adapt this [commit](https://github.com/cyberknight777/dragonheart_kernel_oneplus_sm8150/commit/8a48d7facf525e050e7e6939031c602f9d035a1f) for yourself.
