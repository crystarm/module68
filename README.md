# module68

`module68` is a small virtual machine and assembler written in ALGOL 68. It runs `.m68` text images and includes a minimal assembler for simple legacy `.asm` programs.

## Requirements

- [Algol68G](https://jmvdveer.home.xs4all.nl/en.algol-68-genie.html) (`a68g`)
- POSIX shell for scripts and tests

On Ubuntu/Debian:

```sh
sudo apt-get install algol68g
```

## Usage

Run an existing `.m68` image:

```sh
a68g src/module68_vm.a68 -- examples/hi.m68
```

Assemble a legacy `.asm` file:

```sh
chmod +x scripts/build-asm.sh
scripts/build-asm.sh input.asm output.m68
```

Enable VM tracing when needed:

```sh
a68g src/module68_vm.a68 -- --trace examples/hi.m68
```

The current assembler supports a small instruction set and does not resolve labels or jumps:

```asm
mov r0, 72
sys 1
halt
```

## Tests

Run the shell testbench:

```sh
chmod +x tests/testbench.sh
tests/testbench.sh
```

## Project layout

- `src/module68_vm.a68` — virtual machine implementation
- `src/module68_asm.a68` — minimal assembler
- `examples/` — sample assembly and `.m68` images
- `tests/testbench.sh` — automated VM/assembler testbench
