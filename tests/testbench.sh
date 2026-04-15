#!/bin/sh
set -eu

# module68/tests/testbench.sh
# Тестбенч для пунктов 1.3 плана:
# - delay slot для JP/CALL/RET
# - универсальный JP через JC/JT
# - mixed-endian для 64-битных слов
# - tagged-value в паре регистров (tag + payload)

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VM_SRC="$ROOT_DIR/src/module68_vm.a68"

if ! command -v a68g >/dev/null 2>&1; then
  echo "SKIP: a68g не найден в PATH" >&2
  exit 77
fi

if [ ! -f "$VM_SRC" ]; then
  echo "ERROR: не найден VM source: $VM_SRC" >&2
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
  # usage: write_m68_image <out_file> <flags> <byte1> <byte2> ...
  out_file=$1
  flags=$2
  shift 2

  code_size=$#
  szhi=$((code_size / 256))
  szlo=$((code_size % 256))

  {
    # magic + ver + flags + size
    printf "77 54 56 33 1 %s %s %s " "$flags" "$szhi" "$szlo"
    for b in "$@"; do
      printf "%s " "$b"
    done
    printf "\n"
  } >"$out_file"
}

run_case() {
  # usage: run_case <name> <expected_hex> <bytes...>
  name=$1
  expected_hex=$2
  shift 2

  img="$TMPDIR/${name}.m68"
  out_bin="$TMPDIR/${name}.out"
  err_log="$TMPDIR/${name}.err"

  # flags=1 => new decoder mode (не legacy)
  write_m68_image "$img" 1 "$@"

  if ! (cd "$ROOT_DIR" && a68g src/module68_vm.a68 -- "$img" >"$out_bin" 2>"$err_log"); then
    FAIL=$((FAIL + 1))
    echo "FAIL: $name (VM execution error)"
    sed -n '1,120p' "$err_log" >&2 || true
    return
  fi

  got_hex=$(od -An -tx1 -v "$out_bin" | tr -d ' \n')

  # a68g может печатать предупреждения в stdout до вывода программы.
  # Поэтому сравниваем по суффиксу (фактические байты теста в конце потока).
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

# 1) JP через JC/JT + delay slot для JP
# Ожидаем символ 'B' (0x42), потому что delay slot должен выполниться и изменить r11 на 66.
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

# 2) CALL/RET + delay slot для CALL и RET
# Ожидаем "BY" => 0x42 0x59:
# - r11='B' из delay slot после CALL
# - r12='Y' из delay slot после RET
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

# 3) Mixed-endian roundtrip: ST -> LD -> ST, затем write 8 байт
# Значение: 0x1122334455667788
# Ожидаемые байты mixed-endian: 22 11 44 33 66 55 88 77
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

# 4) Tagged-value pair (экзотический формат):
# Rt=r20 (tag), Rp=r21 (payload).
# Проверяем фактическую укладку пары в память через ST.
# Избегаем нулевых байтов в ожидаемом выводе (иначе REPR может "съесть" их в stdout).
# tag-word=0x010203040506070b -> mixed: 02 01 04 03 06 05 0b 07
# payload=0x1112131415161718 -> mixed: 12 11 14 13 16 15 18 17
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

echo
echo "Summary: PASS=$PASS FAIL=$FAIL"

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
