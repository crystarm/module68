#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VM_SRC="$ROOT_DIR/src/module68_vm.a68"
ASM_SRC="$ROOT_DIR/src/module68_asm.a68"

if ! command -v a68g >/dev/null 2>&1; then
  echo "SKIP: a68g not found in PATH" >&2
  exit 77
fi

if [ ! -f "$VM_SRC" ]; then
  echo "ERROR: VM source not found: $VM_SRC" >&2
  exit 2
fi

if [ ! -f "$ASM_SRC" ]; then
  echo "ERROR: assembler source not found: $ASM_SRC" >&2
  exit 2
fi

TMPDIR=$(mktemp -d)
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT INT TERM

PASS=0
FAIL=0

write_m68_image() {
  out_file=$1
  flags=$2
  shift 2

  code_size=$#
  szhi=$((code_size / 256))
  szlo=$((code_size % 256))

  {
    printf "77 54 56 33 1 %s %s %s " "$flags" "$szhi" "$szlo"
    for b in "$@"; do
      printf "%s " "$b"
    done
    printf "\n"
  } >"$out_file"
}

run_case() {
  name=$1
  expected_hex=$2
  shift 2

  img="$TMPDIR/${name}.m68"
  out_bin="$TMPDIR/${name}.out"
  err_log="$TMPDIR/${name}.err"

  write_m68_image "$img" 1 "$@"

  if ! (cd "$ROOT_DIR" && a68g src/module68_vm.a68 -- "$img" >"$out_bin" 2>"$err_log"); then
    FAIL=$((FAIL + 1))
    echo "FAIL: $name (VM execution error)"
    sed -n '1,120p' "$err_log" >&2 || true
    return
  fi

  got_hex=$(od -An -tx1 -v "$out_bin" | tr -d ' \n')

  case "$got_hex" in
    *"$expected_hex")
      PASS=$((PASS + 1))
      echo "PASS: $name"
      ;;
    *)
      FAIL=$((FAIL + 1))
      echo "FAIL: $name"
      echo "  expected suffix: $expected_hex"
      echo "  got            : $got_hex"
      ;;
  esac
}

run_asm_case() {
  name=$1
  expected_hex=$2
  shift 2

  asm_file="$TMPDIR/${name}.asm"
  img="$TMPDIR/${name}.m68"
  out_bin="$TMPDIR/${name}.out"
  asm_log="$TMPDIR/${name}.asm.log"
  err_log="$TMPDIR/${name}.err"

  rm -f "$img"

  {
    for line in "$@"; do
      printf "%s\n" "$line"
    done
  } >"$asm_file"

  if ! (cd "$ROOT_DIR" && a68g src/module68_asm.a68 -- "$asm_file" "$img" >"$asm_log" 2>&1); then
    FAIL=$((FAIL + 1))
    echo "FAIL: $name (assembler execution error)"
    sed -n '1,120p' "$asm_log" >&2 || true
    return
  fi

  if [ ! -f "$img" ]; then
    FAIL=$((FAIL + 1))
    echo "FAIL: $name (assembler did not create output image)"
    sed -n '1,120p' "$asm_log" >&2 || true
    return
  fi

  if ! (cd "$ROOT_DIR" && a68g src/module68_vm.a68 -- "$img" >"$out_bin" 2>"$err_log"); then
    FAIL=$((FAIL + 1))
    echo "FAIL: $name (VM execution error)"
    sed -n '1,120p' "$err_log" >&2 || true
    return
  fi

  got_hex=$(od -An -tx1 -v "$out_bin" | tr -d ' \n')

  case "$got_hex" in
    *"$expected_hex")
      PASS=$((PASS + 1))
      echo "PASS: $name"
      ;;
    *)
      FAIL=$((FAIL + 1))
      echo "FAIL: $name"
      echo "  expected suffix: $expected_hex"
      echo "  got            : $got_hex"
      ;;
  esac
}

run_jc_case() {
  name=$1
  jc=$2
  fl=$3
  expected_hex=$4

  run_case "$name" "$expected_hex" \
    3 10 128 0 0 0 0 0 0 0 \
    3 67 64 0 0 0 0 0 0 0 \
    1 68 "$jc" \
    1 66 "$fl" \
    1 11 70 \
    96 \
    1 12 1 \
    8 10 11 \
    1 1 1 \
    1 2 134 \
    1 3 1 \
    1 69 1 \
    192 \
    108 \
    108 108 108 108 108 108 108 108 108 108 108 108 108 108 \
    1 11 84 \
    8 10 11 \
    1 1 1 \
    1 2 134 \
    1 3 1 \
    1 69 1 \
    192 \
    108
}

run_asm_case "asm_creates_missing_output" "4f" \
  "mov r0, 79" \
  "sys 1" \
  "halt"

run_case "jp_delay_slot_jc_jt" "42" \
  2 10 128 0 64 0 0 \
  1 11 65 \
  1 68 1 \
  2 67 128 27 0 0 0 \
  96 \
  1 11 66 \
  1 11 67 \
  8 10 11 \
  1 1 1 \
  2 2 128 6 64 0 0 \
  1 3 1 \
  1 69 1 \
  192 \
  1 1 0 \
  1 69 2 \
  192 \
  108

run_case "call_ret_delay_slots" "4259" \
  2 10 128 0 64 0 0 \
  1 11 65 \
  1 12 97 \
  2 67 128 64 0 0 0 \
  100 \
  1 11 66 \
  8 10 11 \
  9 10 12 8 \
  1 1 1 \
  2 2 128 6 64 0 0 \
  1 3 1 \
  1 69 1 \
  192 \
  2 2 128 14 64 0 0 \
  192 \
  1 1 0 \
  1 69 2 \
  192 \
  108 \
  1 12 120 \
  104 \
  1 12 89 \
  108

run_case "mixed_endian_roundtrip" "2211443366558877" \
  2 10 128 0 64 0 0 \
  3 11 136 119 102 85 68 51 34 17 \
  8 10 11 \
  4 12 10 \
  9 10 12 8 \
  1 1 1 \
  2 2 128 8 64 0 0 \
  1 3 8 \
  1 69 1 \
  192 \
  1 1 0 \
  1 69 2 \
  192 \
  108

run_case "tagged_pair_layout" "0201040306050b071211141316151817" \
  2 10 128 0 64 0 0 \
  3 20 11 7 6 5 4 3 2 1 \
  3 21 24 23 22 21 20 19 18 17 \
  8 10 20 \
  9 10 21 8 \
  1 1 1 \
  2 2 128 0 64 0 0 \
  1 3 16 \
  1 69 1 \
  192 \
  1 1 0 \
  1 69 2 \
  192 \
  108

run_case "mixed_endian_alt_roundtrip" "117f332255447766" \
  2 10 128 0 64 0 0 \
  3 11 119 102 85 68 51 34 17 127 \
  8 10 11 \
  4 12 10 \
  9 10 12 8 \
  1 1 1 \
  2 2 128 8 64 0 0 \
  1 3 8 \
  1 69 1 \
  192 \
  1 1 0 \
  1 69 2 \
  192 \
  108

run_case "jp_delay_slot_target_snapshot" "41" \
  3 10 128 0 0 0 0 0 0 0 \
  3 67 96 0 0 0 0 0 0 0 \
  1 68 1 \
  96 \
  3 67 64 0 0 0 0 0 0 0 \
  108 \
  108 108 108 108 108 108 108 108 108 108 108 108 108 108 108 108 108 108 108 108 108 108 108 108 108 108 108 108 108 \
  1 11 66 \
  8 10 11 \
  1 1 1 \
  1 2 134 \
  1 3 1 \
  1 69 1 \
  192 \
  108 \
  108 108 108 108 108 108 108 108 108 108 108 108 \
  1 11 65 \
  8 10 11 \
  1 1 1 \
  1 2 134 \
  1 3 1 \
  1 69 1 \
  192 \
  108

run_jc_case "jc0_never" 0 0 "46"
run_jc_case "jc1_always" 1 0 "54"
run_jc_case "jc2_z_false" 2 0 "46"
run_jc_case "jc2_z_true" 2 1 "54"
run_jc_case "jc3_nz_false" 3 1 "46"
run_jc_case "jc3_nz_true" 3 0 "54"
run_jc_case "jc4_n_false" 4 0 "46"
run_jc_case "jc4_n_true" 4 2 "54"
run_jc_case "jc5_c_false" 5 0 "46"
run_jc_case "jc5_c_true" 5 4 "54"
run_jc_case "jc6_v_false" 6 0 "46"
run_jc_case "jc6_v_true" 6 8 "54"
run_jc_case "jc7_nxorv_false" 7 10 "46"
run_jc_case "jc7_nxorv_true" 7 2 "54"

echo
echo "Summary: PASS=$PASS FAIL=$FAIL"

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
