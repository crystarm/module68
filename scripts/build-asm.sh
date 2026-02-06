#!/bin/sh
set -eu
if [ "$#" -lt 1 ]; then
  echo "usage: $0 input.asm [output.m68]" >&2
  exit 2
fi
in="$1"
out="${2:-${in%.asm}.m68}"
a68g src/module68_asm.a68 -- "$in" "$out"
