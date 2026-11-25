# Inkling 2 Mini on an RX 6800 XT — llama.cpp Vulkan benchmarks

What one RDNA2 card does with a 26.4B Mixture-of-Experts model when llama.cpp runs on Vulkan
instead of ROCm, and what the engine build is worth.

**Hardware:** Ryzen 5 5600X, 32 GB RAM, AMD Radeon RX 6800 XT 16 GB (NAVI21, `gfx1030`).
**Software:** llama.cpp b12669 (`1.0.0-dev`, commit `30ec35a`) and e6d624b, `GGML_VULKAN=ON`,
Vulkan/RADV, Mesa radv driver. No ROCm — HIP was disabled on this machine because ROCm 10.1
segfaults on `hipStreamCreate`. The Vulkan backend does not need it.

## Headline

Same weights, same flags, two engine builds:

| llama.cpp | model | pp512 t/s | tg128 t/s |
|---|---|---:|---:|
| e6d624b | Inkling 2 Mini UD-Q3_K_XL, 12.68 GiB | 537.87 | 27.40 |
| **b12669** | Inkling 2 Mini UD-Q3_K_XL, 12.68 GiB | **810.33** | **52.17** |

**+50.7% prompt processing, +90.4% generation** from the rebuild alone. Full tables, the
16.41 GiB partial-offload case, method and caveats: [RESULTS.md](RESULTS.md).

## Reproduce

```sh
# build llama.cpp with Vulkan into ~/.local/share/llama.cpp
bench/build-llama-vulkan.sh b12669 ~/.local/share/llama.cpp

# bench every GGUF with the same flags, keeping the full log
bench/bench.sh ~/models/inkling2/Inkling-2-Mini-UD-Q3_K_XL.gguf
```

The build script fetches Vulkan headers into `/tmp` when the distro has none, clones
`--depth 1 --branch <tag>`, configures `-G Ninja -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
-DLLAMA_CURL=OFF`, and installs. Installs strip RUNPATH, so binaries need
`LD_LIBRARY_PATH=<prefix>/lib`; both scripts set it.

## Serve it

[`systemd/llama-server-inkling.service`](systemd/llama-server-inkling.service) is a systemd
user unit: OpenAI-compatible endpoint on port 8882, `-ngl 99`, `-c 131072` with `q8_0` KV
cache, `--jinja`. It binds `127.0.0.1` because llama-server has no authentication.

Inkling-specific flags and every dead end found along the way — the stripped RUNPATH "build
failure", the empty `llama-bench | grep`, gated model repos, why Strata does not help on
RDNA2 — are in [docs/SETUP-NOTES.md](docs/SETUP-NOTES.md).

## Scope

One machine, one model family, one GPU, no per-tensor overrides or thread tuning. These are
not claims about other cards; on RDNA3/RDNA4 the matrix cores and a hipBLASLt or Vulkan
tuning table change the picture substantially.
