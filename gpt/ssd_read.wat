;; Read one byte of an existing config.json. Written by OpenAI Codex.
;; probe() returns 0..255 for a byte, -256 for EOF, or a negated WASI errno.
;; The host may preopen one directory (descriptor 3). Only read rights are requested.
;; wasmtime run --dir "MODEL_DIRECTORY::/model" --invoke probe gpt/ssd_read.wat
;; Omit --dir and its value to run the control.
;; overview() lists regular files as bc'text (blocked context), relative to the preopen.
;; wasmtime run --dir "HOST_DIRECTORY::/disk" --invoke overview gpt/ssd_read.wat
;; Output is tab-separated UTF-8. Percent signs and control bytes in names use %HH.
(module
  (import "wasi_snapshot_preview1" "path_open" (func $open
    (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_read" (func $read (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_close" (func $close (param i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_readdir" (func $readdir (param i32 i32 i32 i64 i32) (result i32)))
  (import "wasi_snapshot_preview1" "path_filestat_get" (func $stat (param i32 i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit" (func $exit (param i32)))
  (memory (export "memory") 4)
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
      (else (i32.const -256))))

  (data (i32.const 200) "bc'text\09")
  (data (i32.const 216) "link\09")
  (data (i32.const 224) "other\09")
  (data (i32.const 232) "skipped\09")
  (data (i32.const 248) "\09errno=")
  (data (i32.const 256) "files=")
  (data (i32.const 264) " links=")
  (data (i32.const 272) " other=")
  (data (i32.const 280) " skipped=")
  (data (i32.const 296) "\0a.")
  (data (i32.const 304) "0123456789ABCDEF")
  (global $buffered (mut i32) (i32.const 0))

  ;; Buffer stdout in 32 KiB batches. A broken pipe must not look like a complete list.
  (func $flush (local $pos i32) (local $written i32)
    (block $done (loop $more
      (br_if $done (i32.eq (local.get $pos) (global.get $buffered)))
      (i32.store (i32.const 48) (i32.add (i32.const 4096) (local.get $pos)))
      (i32.store (i32.const 52) (i32.sub (global.get $buffered) (local.get $pos)))
      (if (call $write (i32.const 1) (i32.const 48) (i32.const 1) (i32.const 56))
        (then (call $exit (i32.const 1)) unreachable))
      (local.set $written (i32.load (i32.const 56)))
      (if (i32.eqz (local.get $written)) (then (call $exit (i32.const 1)) unreachable))
      (local.set $pos (i32.add (local.get $pos) (local.get $written)))
      (br $more)))
    (global.set $buffered (i32.const 0)))

  (func $emit (param $src i32) (param $len i32) (local $n i32)
    (block $done (loop $copy
      (br_if $done (i32.eqz (local.get $len)))
      (local.set $n (i32.sub (i32.const 32768) (global.get $buffered)))
      (if (i32.gt_u (local.get $n) (local.get $len)) (then (local.set $n (local.get $len))))
      (memory.copy (i32.add (i32.const 4096) (global.get $buffered)) (local.get $src) (local.get $n))
      (global.set $buffered (i32.add (global.get $buffered) (local.get $n)))
      (if (i32.eq (global.get $buffered) (i32.const 32768)) (then (call $flush)))
      (local.set $src (i32.add (local.get $src) (local.get $n)))
      (local.set $len (i32.sub (local.get $len) (local.get $n)))
      (br $copy))))

  (func $number (param $value i64) (local $p i32)
    (local.set $p (i32.const 384))
    (loop $digit
      (local.set $p (i32.sub (local.get $p) (i32.const 1)))
      (i32.store8 (local.get $p) (i32.add (i32.const 48)
        (i32.wrap_i64 (i64.rem_u (local.get $value) (i64.const 10)))))
      (local.set $value (i64.div_u (local.get $value) (i64.const 10)))
      (br_if $digit (i64.ne (local.get $value) (i64.const 0))))
    (call $emit (local.get $p) (i32.sub (i32.const 384) (local.get $p))))

  ;; Keep a raw path prefix from 0x10000 until the directory stack at 0x30000.
  ;; Escape only while printing, so names passed back to WASI stay byte-exact.
  (func $path (param $len i32) (local $i i32) (local $start i32) (local $ch i32)
    (if (i32.eqz (local.get $len)) (then (call $emit (i32.const 297) (i32.const 1)) (return)))
    (block $done (loop $chars
      (br_if $done (i32.eq (local.get $i) (local.get $len)))
      (local.set $ch (i32.load8_u (i32.add (i32.const 0x10000) (local.get $i))))
      (if (i32.or (i32.lt_u (local.get $ch) (i32.const 32))
                  (i32.or (i32.eq (local.get $ch) (i32.const 37)) (i32.eq (local.get $ch) (i32.const 127))))
        (then
          (call $emit (i32.add (i32.const 0x10000) (local.get $start)) (i32.sub (local.get $i) (local.get $start)))
          (i32.store8 (i32.const 400) (i32.const 37))
          (i32.store8 (i32.const 401) (i32.load8_u offset=304 (i32.shr_u (local.get $ch) (i32.const 4))))
          (i32.store8 (i32.const 402) (i32.load8_u offset=304 (i32.and (local.get $ch) (i32.const 15))))
          (call $emit (i32.const 400) (i32.const 3))
          (local.set $start (i32.add (local.get $i) (i32.const 1)))))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $chars)))
    (call $emit (i32.add (i32.const 0x10000) (local.get $start)) (i32.sub (local.get $len) (local.get $start))))

  (func $skip (param $len i32) (param $err i32)
    (call $emit (i32.const 232) (i32.const 8))
    (call $path (local.get $len))
    (call $emit (i32.const 248) (i32.const 7))
    (call $number (i64.extend_i32_u (local.get $err)))
    (call $emit (i32.const 296) (i32.const 1)))

  ;; Each open directory owns an 8192-byte page and a 32-byte frame header:
  ;; fd, prefix length, 64-bit resume cookie, cursor, used bytes. The explicit
  ;; stack keeps directory nesting off the Wasm call stack.
  (func $frame (param $frame i32) (param $fd i32) (param $prefix i32)
    (memory.fill (local.get $frame) (i32.const 0) (i32.const 32))
    (i32.store (local.get $frame) (local.get $fd))
    (i32.store offset=4 (local.get $frame) (local.get $prefix)))

  (func (export "overview") (export "run")
    (local $f i32) (local $fd i32) (local $prefix i32) (local $len i32)
    (local $pos i32) (local $remain i32) (local $entry i32) (local $name i32)
    (local $size i32) (local $kind i32) (local $err i32) (local $child i32)
    (local $files i64) (local $links i64) (local $other i64) (local $skips i64)
    (local.set $f (i32.const 0x30000))
    (call $frame (local.get $f) (i32.const 3) (i32.const 0))
    (block $finished (loop $walk
      (local.set $fd (i32.load (local.get $f)))
      (local.set $prefix (i32.load offset=4 (local.get $f)))
      (local.set $len (local.get $prefix))
      (block $pop (block $failed
        (local.set $pos (i32.load offset=16 (local.get $f)))
        (if (i32.eq (local.get $pos) (i32.load offset=20 (local.get $f))) (then
          (local.set $err (call $readdir (local.get $fd) (i32.add (local.get $f) (i32.const 32))
            (i32.const 8192) (i64.load offset=8 (local.get $f)) (i32.add (local.get $f) (i32.const 20))))
          (br_if $failed (local.get $err))
          (br_if $pop (i32.eqz (i32.load offset=20 (local.get $f))))
          (local.set $pos (i32.const 0))))
        (local.set $remain (i32.sub (i32.load offset=20 (local.get $f)) (local.get $pos)))
        (local.set $entry (i32.add (i32.add (local.get $f) (i32.const 32)) (local.get $pos)))
        (block $partial
          (br_if $partial (i32.lt_u (local.get $remain) (i32.const 24)))
          (local.set $size (i32.load offset=16 (local.get $entry)))
          (br_if $partial (i32.gt_u (local.get $size) (i32.sub (local.get $remain) (i32.const 24))))
          (i32.store offset=16 (local.get $f) (i32.add (local.get $pos) (i32.add (i32.const 24) (local.get $size))))
          (i64.store offset=8 (local.get $f) (i64.load (local.get $entry)))
          (local.set $name (i32.add (local.get $entry) (i32.const 24)))
          (if (i32.eq (i32.load8_u (local.get $name)) (i32.const 46)) (then
            (br_if $walk (i32.eq (local.get $size) (i32.const 1)))
            (br_if $walk (i32.and (i32.eq (local.get $size) (i32.const 2))
                                  (i32.eq (i32.load8_u offset=1 (local.get $name)) (i32.const 46))))))
          (block $entry_error
            (local.set $err (i32.const 37)) ;; WASI NAMETOOLONG
            (br_if $entry_error (i32.gt_u (i32.add (i32.add (local.get $prefix) (i32.const 1)) (local.get $size))
                                          (i32.const 0x20000)))
            (if (local.get $prefix) (then
              (i32.store8 offset=0x10000 (local.get $prefix) (i32.const 47))
              (local.set $len (i32.add (local.get $len) (i32.const 1)))))
            (memory.copy (i32.add (i32.const 0x10000) (local.get $len)) (local.get $name) (local.get $size))
            (local.set $len (i32.add (local.get $len) (local.get $size)))
            (local.set $kind (i32.load8_u offset=20 (local.get $entry)))
            (if (i32.eqz (local.get $kind)) (then
              (local.set $err (call $stat (local.get $fd) (i32.const 0) (local.get $name) (local.get $size) (i32.const 80)))
              (br_if $entry_error (local.get $err))
              (local.set $kind (i32.load8_u (i32.const 96)))))
            (if (i32.eq (local.get $kind) (i32.const 3)) (then
              (local.set $child (i32.add (local.get $f) (i32.const 8224)))
              (if (i32.gt_u (i32.add (local.get $child) (i32.const 8224)) (i32.shl (memory.size) (i32.const 16)))
                (then (local.set $err (i32.const 48)) ;; WASI NOMEM
                      (br_if $entry_error (i32.eq (memory.grow (i32.const 1)) (i32.const -1)))))
              ;; DIRECTORY, no symlink following; PATH_OPEN | FD_READDIR | PATH_FILESTAT_GET.
              (local.set $err (call $open (local.get $fd) (i32.const 0) (local.get $name) (local.get $size)
                (i32.const 2) (i64.const 0x46000) (i64.const 0x46000) (i32.const 0) (i32.const 64)))
              (br_if $entry_error (local.get $err))
              (local.set $f (local.get $child))
              (call $frame (local.get $f) (i32.load (i32.const 64)) (local.get $len))
              (br $walk)))
            (if (i32.eq (local.get $kind) (i32.const 4)) (then
              (local.set $files (i64.add (local.get $files) (i64.const 1)))
              (call $emit (i32.const 200) (i32.const 8)))
              (else (if (i32.eq (local.get $kind) (i32.const 7)) (then
                (local.set $links (i64.add (local.get $links) (i64.const 1)))
                (call $emit (i32.const 216) (i32.const 5)))
                (else (local.set $other (i64.add (local.get $other) (i64.const 1)))
                      (call $emit (i32.const 224) (i32.const 6))))))
            (call $path (local.get $len))
            (call $emit (i32.const 296) (i32.const 1))
            (br $walk))
          (call $skip (local.get $len) (local.get $err))
          (local.set $skips (i64.add (local.get $skips) (i64.const 1)))
          (br $walk))
        ;; WASI may truncate the last entry of a page. Replay from the last complete cookie.
        (local.set $err (i32.const 37))
        (br_if $failed (i32.eqz (local.get $pos)))
        (i32.store offset=16 (local.get $f) (i32.load offset=20 (local.get $f)))
        (br $walk))
      (call $skip (local.get $prefix) (local.get $err))
      (local.set $skips (i64.add (local.get $skips) (i64.const 1))))
      (br_if $finished (i32.eq (local.get $f) (i32.const 0x30000)))
      (local.set $err (call $close (local.get $fd)))
      (if (local.get $err) (then
        (call $skip (local.get $prefix) (local.get $err))
        (local.set $skips (i64.add (local.get $skips) (i64.const 1)))))
      (local.set $f (i32.sub (local.get $f) (i32.const 8224)))
      (br $walk)))
    (call $emit (i32.const 256) (i32.const 6)) (call $number (local.get $files))
    (call $emit (i32.const 264) (i32.const 7)) (call $number (local.get $links))
    (call $emit (i32.const 272) (i32.const 7)) (call $number (local.get $other))
    (call $emit (i32.const 280) (i32.const 9)) (call $number (local.get $skips))
    (call $emit (i32.const 296) (i32.const 1)) (call $flush)))
