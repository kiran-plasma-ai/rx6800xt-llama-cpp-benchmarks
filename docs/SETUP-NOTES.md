# Setup notes

Operational notes from building this stack. They are here so a later session does not
rediscover them; the numbers live in [../RESULTS.md](../RESULTS.md).

## Hardware and backend

- Ryzen 5 5600X (12 threads), 32 GB RAM, AMD RX 6800 XT 16 GB (NAVI21, RDNA2, `gfx1030`).
- Backend is **Vulkan/RADV only**. HIP was deliberately disabled: ROCm 10.1 segfaults on
  `hipStreamCreate` here. llama.cpp's Vulkan backend needs no ROCm.
- No cmake and no Vulkan headers in the distro packages on this machine; both are installed
  per-user (see below).

## llama.cpp install layout

| Path | Meaning |
|---|---|
| `~/.local/share/llama.cpp` | active install (`bin/`, `lib/`, `include/`) |
| `~/.local/share/llama.cpp-current` | symlink → `llama.cpp`, referenced by scripts |
| `~/.local/share/llama.cpp-<oldcommit>` | previous install, kept as rollback |
| `~/.local/bin/llama-{server,cli,bench,quantize}` | symlinks → `llama.cpp-current/bin/<name>` |

CMake strips RUNPATH on install ("Set non-toolchain portion of runtime path ... to ''"), so
every invocation needs `LD_LIBRARY_PATH=~/.local/share/llama.cpp/lib`. A missing value shows
up as `libllama-server-impl.so: cannot open shared object file`, which looks like a build
failure and is not one.

## Rebuild

```sh
bench/build-llama-vulkan.sh b12669 ~/.local/share/llama.cpp-new
```

Build with an install prefix, then swap: move the old install aside, `mv llama.cpp-new
llama.cpp`, repoint `llama.cpp-current` and the four `~/.local/bin` symlinks at
`llama.cpp-current/bin/<name>`.

cmake came from `uv tool install cmake` (4.4.5). Vulkan headers are cloned to
`/tmp/Vulkan-Headers` and SPIRV-Headers built into `/tmp/spirv-headers-install`; both are
temporary and must be re-created after a reboot — the script does that.

## Service

`systemd/llama-server-inkling.service` is a user unit on port 8882. Install it at
`~/.config/systemd/user/`, then:

```sh
systemctl --user daemon-reload
systemctl --user enable --now llama-server-inkling
curl -sf http://127.0.0.1:8882/health   # ~30 s to load; prints {"status":"ok"}
```

- It binds `127.0.0.1` on purpose: llama-server has **no authentication**, so a `0.0.0.0`
  bind exposes the model to anything that can route to the host. Put it behind an
  authenticating proxy before widening the bind.
- `enable` is a separate decision from `start`. Without it the unit does not come back at
  login or reboot.
- Rollback is starting the unit again on a known-good model file.

## Inkling 2 Mini specifics

- Arch `inkling2_loop`: 26.4B MoE, 3.4B active, 24 layers with layers 6–17 looped three
  times, 128 experts (8 active), up to 1M context.
- The chat template defaults `reasoning_effort` to 0.9 (`high`). Pass
  `--chat-template-kwargs '{"reasoning_effort": "low"}'` or a request-level
  `chat_template_kwargs`; support in llama.cpp is recent (b12633+).
- Thinking comes back in `reasoning_content`, the answer in `content`. A small `max_tokens`
  can be eaten entirely by reasoning, leaving `content` empty — that is not a broken server.
- Text-only re-quantizations (e.g. abliterated community builds) have no vision tower and no
  MTP drafter: drop `--mmproj` and any `dspark` argument for those.

## Pitfalls

- **Do not benchmark with the server running.** Model + KV cache hold the VRAM; a second
  load either fails or spills to the CPU and measures the wrong thing. Stop the unit, bench,
  restart. `llama-bench --list-devices` shows free VRAM.
- **`llama-bench` output and pipes.** The results table is printed at the end of the run;
  piping it through `grep` has come back empty. Redirect the full output to a log and grep
  the log (`bench/bench.sh` does this).
- **Context size is not free.** `-c 131072` with `q8_0` KV fits next to the 12.68 GiB
  Q3_K_XL on 16 GB, but leaves little room for a second process using the GPU.
- **Gated model repositories.** The `orcarouter/...` abliterated packs are gated. `README.md`
  is readable without approval; the `.gguf` files return `403 GatedRepo` until the account
  clicks *Agree and access repository* in a browser. There is no API route for that click
  (`/api/models/<repo>/ask-access` and friends return 404), so it cannot be automated.
- **Strata** (the HIP/CUDA engine) does not help on this card: no Vulkan backend, the
  `gfx1030` path has no matrix cores or hipBLASLt kernels (its prompt GEMMs fall back to
  generic rocBLAS, ~6.6x slower), and its own Inkling row for RDNA2 is an RX 6700 XT at
  17.8 tok/s decode. See [../RESULTS.md](../RESULTS.md#engines-considered).
