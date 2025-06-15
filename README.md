# YAKB — Yet Another Kernel Builder (v3.1)

YAKB is an modular BSP-grade Build Kernel Orchestrator written in Bash.

- Two-way UX:- Use as an argument-based CLI tool or via an interactive menu.
- DLKM/VNDR: Supports modular vendor packaging.
- Enterprise-Grade: Integrated error handling, CI compliance, and advanced logging.
- OTA, Telegram, and GitHub Release flows fully supported.

## 🚀 Usage

### Preparation

Edit `builder.sh` as needed.

- All variables are commented inline for clarity..

### CLI

```bash
bash builder.sh img mkzip
```

This builds the kernel and produces an AnyKernel3 zip.

```bash
bash builder.sh yakbmod
```

### Menu

```bash
bash builder.sh
```

Runs the interactive menu with all build, packaging, and uprev options.

## 🧑‍💻 Features

- Argument-based and menu-based usage
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

## 🛠️ Integrations

- OTA JSON/Release logic supported out-of-the-box
- Telegram API integration (requires `TOKEN`)
- GitHub Releases support (requires `GH_TOKEN`)

## 📖 Documentation

- See comments in `builder.sh` for configuration details.

## 🤝 Contributing

- PRs, bugfixes, and device profiles are welcome.
- Issues for CI/CD improvements or new device support are encouraged.

## Misc

- Version file

Adapt this [commit](https://github.com/cyberknight777/dragonheart_kernel_oneplus_sm8150/commit/8a48d7facf525e050e7e6939031c602f9d035a1f) for yourself.
