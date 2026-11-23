;; Read one byte of an existing config.json. Written by OpenAI Codex.
;; probe() returns 0..255 for a byte, -256 for EOF, or a negated WASI errno.
;; The host may preopen one directory (descriptor 3). Only read rights are requested.
;; wasmtime run --dir "MODEL_DIRECTORY::/model" --invoke probe gpt/ssd_read.wat
;; Omit --dir and its value to run the control.
(module
  (import "wasi_snapshot_preview1" "path_open" (func $open
    (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_read" (func $read (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_close" (func $close (param i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 0) "config.json")
  ;; Scratch offsets: 16 = file descriptor, 24 = iovec, 32 = bytes read, 36 = byte.
  (func (export "probe") (result i32)
    (local $fd i32) (local $err i32) (local $close_err i32)
    (local.set $err (call $open (i32.const 3) (i32.const 0) (i32.const 0)
      (i32.const 11) (i32.const 0) (i64.const 2) (i64.const 0) (i32.const 0) (i32.const 16)))
    (if (local.get $err) (then (return (i32.sub (i32.const 0) (local.get $err)))))
    (local.set $fd (i32.load (i32.const 16)))
    (i32.store (i32.const 24) (i32.const 36))
    (i32.store (i32.const 28) (i32.const 1))
    (local.set $err (call $read (local.get $fd) (i32.const 24) (i32.const 1) (i32.const 32)))
    (local.set $close_err (call $close (local.get $fd)))
    (if (local.get $err) (then (return (i32.sub (i32.const 0) (local.get $err)))))
    (if (local.get $close_err) (then (return (i32.sub (i32.const 0) (local.get $close_err)))))
    (if (result i32) (i32.load (i32.const 32))
      (then (i32.load8_u (i32.const 36)))
      (else (i32.const -256)))))
