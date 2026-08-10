# ONNX Runtime + QNN on the OAK4 NPU — design notes, OS-coupling audit, integration roadmap

Status: **working, verified on-device**. This document explains *what* was
built to run arbitrary ONNX models on the OAK4's Hexagon HTP (NPU/DSP) through
ONNX Runtime's QNN Execution Provider inside a standalone OAK App, *why* each
piece has to exist, *which parts are coupled to a specific Luxonis OS build*,
and *what a long-term integration should look like* at every layer.

Three artifacts came out of this work:

| Artifact | Where | What it is |
|---|---|---|
| `oak4ort` | hackathon workspace `oak4-ort-qnn/oak4ort/` (vendored into apps) | Python package: `qnn_session("model.onnx")` returns an `ort.InferenceSession` running on the HTP. Self-bootstraps a stock container. |
| `oakapp-base:onnxruntime` | this repo, branch `onnxruntime-base` (`Dockerfile.onnxruntime`, `entrypoint.sh`, `npu/npu-setup.sh`) | Base-image variant that prepares the container for the QNN EP at build/start time, so apps need no in-process bootstrapping. |
| `oak4ort_slim` | hackathon workspace `oak4-ort-qnn/oak4ort_slim/` (vendored into apps) | Slim `oak4ort` without the bootstrap — same `qnn_session()` API; **the intended companion of `oakapp-base:onnxruntime`** (§3.1). |

User-facing result:

```python
from oak4ort import qnn_session

sess = qnn_session("model.onnx")   # fp32 ONNX -> fp16 on the HTP, zero model prep
out = sess.run(None, {"input": x})
```

Verified environments: OAK4-S R9 (Luxonis OS RVC4 1.30.1) and OAK4-D R9
(Luxonis OS 1.35.0), `onnxruntime` 1.28.0 + `onnxruntime-qnn` 2.4.0,
oakapp-base 1.2.8/1.2.9 (Debian bookworm, Python 3.12, linux/arm64).

---

## 1. Background — why this is not just `pip install`

The QNN EP involves two separate software worlds that must meet in the middle:

```
 app container (Debian bookworm)          │ device OS (OE/Yocto-based Luxonis OS)
                                          │
 onnxruntime (base, 1.28)                 │
   └─ onnxruntime-qnn plugin EP           │
        └─ libQnnHtp.so (wheel)           │
             └─ dlopen("libcdsprpc.so") ──┼─> FastRPC user-space transport
                                          │     (proprietary, OE-built, device OS only)
                                          │        └─ /dev/adsprpc-smd (kernel driver)
                                          │             └─ Hexagon cDSP
                                          │                  └─ libQnnHtpV73Skel.so
                                          │                     (loaded FROM the container
                                          │                      via ADSP_LIBRARY_PATH)
```

The container is Debian; the FastRPC user-space stack is proprietary
Qualcomm/OE code that exists only on the device OS. The kernel driver node has
a Luxonis-OS-specific name. The DSP-side code (skel) is loaded *from the
container's filesystem* by path. None of these seams work by default, and
each failure is silent (the QNN EP just falls back to CPU).

### Why the `onnxruntime-qnn` plugin EP (and not a custom ORT build)

- Since 2.1.0, Microsoft publishes **Linux aarch64 wheels** of
  `onnxruntime-qnn` on PyPI (`manylinux_2_34`, cp311–cp314). No source build,
  no Qualcomm SDK download or account needed.
- It is a **plugin EP** on top of base `onnxruntime>=1.28`. Consequence: it
  must be registered and selected through the EP-device API
  (`ort.register_execution_provider_library()` + `ort.get_ep_devices()` +
  `SessionOptions.add_provider_for_devices()`). The legacy
  `providers=["QNNExecutionProvider"]` list **does not work** for plugin EPs —
  this cost real debugging time and is a key reason `oak4ort/session.py`
  exists.
- `manylinux_2_34` ⇒ container glibc ≥ 2.34. bookworm has 2.36 — fine. This
  is a *container* constraint, not a device-OS constraint.

### Why the wheel's own QNN runtime (and not the device's QAIRT)

The device OS ships full QAIRT runtimes (`/opt/qcom/aistack/qairt/2.32.6…`,
`2.41.0…`) used by the native DepthAI/SNPE NN stack. Using them from ORT
(`backend_path` → device `libQnnHtp.so`, skels from `/usr/lib/rfsa/adsp`) was
tried and **fails** with `QNN_DEVICE_ERROR_INVALID_CONFIG` (hackathon repo
`RESULTS.md`, "Known-not-working variant"). Decision: use the QNN runtime
bundled in the `onnxruntime-qnn` wheel for *both* the CPU side (stub,
`libQnnHtp.so`) and the DSP side (`libQnnHtpV73Skel.so`, resolved via
`ADSP_LIBRARY_PATH`). Stub and skel stay version-matched by construction,
and — important for the OS-coupling question — **the ORT path is fully
decoupled from the device's QAIRT version**. The device runtime stays
dedicated to the native NN stack; the two never mix.

---

## 2. The five container requirements (and why each exists)

Everything else in this project is packaging for these five facts.

### 2.1 A `/dev/fastrpc-cdsp` node must exist

ORT's NPU detection (`soc_utils.cc`) synthesizes a QNN NPU `EpDevice` when a
node matching `/dev/fastrpc-cdsp*` exists. Luxonis OS provides that node;
apps must pass it through to the container. `libcdsprpc.so` separately opens
`/dev/adsprpc-smd` for the actual FastRPC transport, so that node must also be
passed through.

### 2.2 Device nodes must be passed through *and* cgroup-allowed

`oakapp.toml` needs:

```toml
optional_devices = [
    "/dev/fastrpc-cdsp",         # ONNX Runtime QNN device probe
    "/dev/adsprpc-smd",          # libcdsprpc.so FastRPC transport
    "/dev/dma_heap/qcom,system", # DMA-BUF heaps for buffer allocation
    "/dev/dma_heap/system",
]
allowed_devices = [
    { allow = true, type = "c", major = 496, access = "rw" },  # FastRPC
    { allow = true, type = "c", major = 248, access = "rw" },  # dma_heap
]
```

The non-obvious part: **oak-agent mounts `optional_devices` nodes into the
container but does not add device-cgroup allow rules for them.** `open()` on
the node then fails with `EPERM`, which surfaces as FastRPC transport error
1002, which the QNN EP swallows into a silent CPU fallback. So
`allowed_devices` must be written manually. This is arguably an oak-agent bug
— see roadmap §5.2.

TOML gotcha that bit repeatedly: `optional_devices` / `allowed_devices` /
`optional_mounts` are *top-level* keys and must appear **before** any
`[table]` header in `oakapp.toml`.

### 2.3 The device-OS FastRPC user-space stack must be loadable

The QNN stub `dlopen`s `libcdsprpc.so` — the proprietary FastRPC transport
library. It exists only on the device OS and drags in a closed chain of six
OE/Android support libs that Debian doesn't ship:

| Library | Role |
|---|---|
| `libcdsprpc.so` | FastRPC transport to the compute DSP (dlopened by the QNN stub) |
| `liblog.so.0` | OE/Android logging |
| `libcutils.so.0` | OE/Android utils |
| `libion.so.0` | ION shared-memory allocator |
| `libdmabufheap.so.0` | DMA-BUF heap allocator |
| `libvmmem.so.0` | VM memory helper |
| `libbase.so.0` | OE/Android base |

The chain is closed: everything below (glibc ≥ 2.34, libstdc++, libgcc) is
already in bookworm. Getting these into the container is the single most
"hacked" part of the design — §3.3 describes the two approaches tried. The
app mounts the device `/usr/lib` read-only:

```toml
optional_mounts = ["/usr/lib:/host_usr_lib:ro,rbind"]
```

### 2.4 `libatomic1`

The wheel's CPU-side QNN libraries (`libQnnHtp.so`, `libQnnSystem.so`) link
against `libatomic.so.1`, which `debian:bookworm-slim` doesn't install. Baked
into the base-image variant via apt; the self-bootstrap variant resolves it
from the host-lib mount instead.

### 2.5 `ADSP_LIBRARY_PATH` must point at the wheel's skels

When a QNN graph is dispatched, the DSP-side loader resolves the skel
(`libQnnHtpV73Skel.so`) through the `ADSP_LIBRARY_PATH` of the *calling
process* — i.e. the skel is read out of the container's filesystem. It must
version-match the CPU-side stub. Pointing `ADSP_LIBRARY_PATH` at the
`onnxruntime-qnn` wheel's lib dir guarantees the match and is what makes the
whole path independent of the device QAIRT (§1). The base image freezes this
as a stable symlink `/opt/qnn-libs` → wheel dir.

---

## 3. What was built

### 3.1 `oak4ort` — the user-facing package

Two modules, no dependencies beyond `onnxruntime`/`onnxruntime-qnn`:

- **`bootstrap.py`** — one-shot, idempotent, in-process container setup
  covering the library and environment requirements: sets
  `ADSP_LIBRARY_PATH`, then `dlopen`s `libcdsprpc.so` and the wheel's
  `libQnn*.so` with `RTLD_GLOBAL`, *recursively pre-loading missing
  dependencies by absolute path* from `/host_usr_lib` (it parses the dynamic
  loader's "cannot open shared object file" errors). Loading by absolute path
  avoids putting the OE libs on `LD_LIBRARY_PATH`, where they could shadow
  container libs. Returns a `BootstrapStatus` with a precise, actionable
  error string for every failure mode.
- **`session.py`** — `qnn_session(model_path, fp16=True, cache_context=True,
  performance_mode="burst", fallback_to_cpu=True, ...)`:
  - registers the plugin EP once and selects the NPU via the EP-device API
    (the only way that works, §1);
  - `enable_htp_fp16_precision` on by default → **plain fp32 ONNX runs with
    zero model prep** (no quantization required; QDQ int8 still supported for
    max throughput);
  - **EPContext caching**: the first session compiles the QNN graph
    (0.3–3.2 s depending on the model) and writes an EPContext ONNX next to
    the model (`.oak4ort_cache/`, overridable via `OAK4ORT_CACHE_DIR`);
    subsequent sessions load in 0.02–0.2 s. Cache key = model
    path+size+mtime + ORT/QNN versions + EP options, so option changes (e.g.
    perf mode) get distinct caches;
  - `fallback_to_cpu=False` ("strict") turns both "DSP unavailable" and "some
    node fell off the HTP" (`session.disable_cpu_ep_fallback`) into hard
    errors — without it, failures degrade silently into CPU inference.

Two variants exist in the hackathon workspace, differing only in
`_qnn_ep_devices()`; both expose the identical `qnn_session()` API:

| Variant | Bootstraps? | Runs on |
|---|---|---|
| `oak4-ort-qnn/oak4ort_slim/` (slim) | no — the base image did it | `oakapp-base:onnxruntime` — **the intended pairing with this repo's variant image** |
| `oak4-ort-qnn/oak4ort/` (full) | yes, in-process (`bootstrap.py`) | **any stock oakapp-base** from Docker Hub (also harmless on the variant image — `bootstrap()` is idempotent and every step no-ops there) |

Rule of thumb: app pinned to the onnxruntime base image → vendor
`oak4ort_slim` (less code, the image is the single source of truth); app
that must also run on the stock published image → vendor the full `oak4ort`.
The full variant is what got vendored into other integrations (e.g.
depthai-experiments `roboflow-workflow`), precisely because the variant
image is not published yet. `oakctl` packages only the app directory, so
apps carry a vendored copy next to `main.py`; sync it from the canonical
repo-root folder (reference consumer: `yolo26-dsp/`).

### 3.2 `oakapp-base:onnxruntime` — the base-image variant

`Dockerfile.onnxruntime` (extends the py312 image) + a generic hook
mechanism:

- apt `libatomic1` (§2.4);
- preinstalled pinned `onnxruntime==1.28.0` + `onnxruntime-qnn==2.4.0` —
  saves the large on-device pip download at app install; the pins are the
  tested pair;
- `/opt/qnn-libs` symlink + `ENV ADSP_LIBRARY_PATH=/opt/qnn-libs` (§2.5);
- **`/etc/entrypoint.d/` hook mechanism** added to `entrypoint.sh`: hooks are
  *sourced* (so they can export env) before the app and helper services
  start, and must not fail the entrypoint. Generic — usable by future
  variants;
- `npu/npu-setup.sh` installed as `/etc/entrypoint.d/10-npu-setup.sh`
  (§2.3): symlinks the seven FastRPC libs from `/host_usr_lib` into the
  container's `/usr/lib` + `ldconfig`. Every step is a no-op with a clear log
  line when the devices/mounts aren't passed through, so **the variant is
  harmless for apps that don't use the NPU**.

What the app still must provide (an image *cannot* carry mounts/devices):
route the entrypoint through `/entrypoint.sh`, plus the §2.2 + §2.3 TOML
block. See `README.md` § "ONNX Runtime (NPU) Variant" for the copy-paste
template and `oak4-ort-qnn/yolo26-dsp/oakapp.toml` for a complete consumer.

Branch state: `onnxruntime-base`, one squashed commit on top of `main`
(1.2.9). Not yet published to Docker Hub — during development it was served
from a `registry:2` container running **on the device itself**
(`[base_image] api_url = "http://127.0.0.1:5555"`), because on-device
`docker build`/`save` is broken by fuse-overlayfs.

### 3.3 History: baked blobs → runtime linking (the "blobs from the OS" issue)

The first iteration (preserved on branch `onnxruntime-base-pre-squash`,
commits `ca4c6e2`…`af281d6`) **committed the seven proprietary FastRPC
binaries** — extracted from Luxonis OS 1.35.0 `/usr/lib` — into the public
repo (`fastrpc/arm64/*.so` + `fetch-fastrpc-libs.sh` + a provenance README)
and baked them into the image. That worked, but had two problems:

1. **Redistribution/licensing** — proprietary Qualcomm/OE binaries in a
   public repo and a public Docker Hub image is a legal call nobody made.
2. **OS pinning** — the image would carry user-space libs from one specific
   OS build, silently diverging from the kernel driver / DSP firmware of the
   OS actually running under it.

The final iteration (commit `c94e220`, now squashed into HEAD) removed the
blobs entirely: the app mounts the device `/usr/lib` read-only and the
entrypoint hook **links the libs from the running OS at container start**.
No proprietary bits in the repo or image, and the libs are exactly the ones
belonging to the running kernel/firmware, by construction. The cost: apps
must add one `optional_mounts` line, and the soname list in `npu-setup.sh`
becomes the coupling point (see audit, §4).

> If you inspected an older image/branch and saw blobs: that is the
> pre-squash state. Current HEAD ships **no** OS binaries.

### 3.4 Validation & performance (what "works" means)

Full data: hackathon repo `RESULTS.md` and `benchmark/RESULTS.md`. Highlights:

- **Correctness**: resnet18 HTP vs CPU reference: 10/10 top-1 both int8 and
  fp16; fp16 cosine 1.00000. Five zoo models: worst `1 − cos = 2.7e-4`.
- **Latency** (resnet18): CPU fp32 48.1 ms → HTP fp16 1.9 ms → HTP int8
  **0.8 ms** (~60×).
- **Zoo sweep** (burst, single stream): 7.5–19.6× vs container CPU; the ORT
  path beat the native RVC4 DLC path on 4 of 5 models (ViTs by 2.6–7.6×);
  yolo26 is the counter-example (native DLC 1.78× faster).
- **Real apps**: `yolo26-dsp` 25 ms/frame in a live DepthAI pipeline;
  `smolvlm-dsp` SigLIP encoder 201 ms/frame; the roboflow-workflow
  integration went 2.1 → 20 pred/s (camera-fps-capped).
- Op coverage was a non-issue: full ViTs (attention/LayerNorm/GELU) placed
  100% on the HTP.

Known sharp edges (documented, not fixed):

- **Static shapes required** by the HTP. Fix dynamic dims offline
  (`onnxruntime.tools.make_dynamic_shape_fixed`) or at runtime (the roboflow
  integration fixes batch dims automatically); truly data-dependent graphs
  need the partial-evaluation/freezing technique from
  `smolvlm-dsp/scripts/freeze_vision.py`.
- **`htp_performance_mode` behaves as device-global state**, not
  per-session: a `burst` session leaves the HTP clocked up for later
  `balanced` sessions in the same process (benchmarks must isolate
  processes).
- First-ever session per model pays the HTP compile; ship or pre-warm
  EPContext caches (§5.4).

---

## 4. OS-coupling audit — what is pinned to what

Direct answer to "are we hardcoded to a specific OS?": **current HEAD bakes
nothing from any specific OS build into the image or repo.** All remaining
coupling is at *interface* level — names and numbers Luxonis OS currently
exposes — and each has a distinct failure mode. Ordered from most to least
fragile:

| # | Coupling | Where it lives | Pinned to | Breaks when / how it shows |
|---|---|---|---|---|
| 1 | **cgroup majors 496 (FastRPC) / 248 (dma_heap)** | every app's `allowed_devices` | **kernel build** — char majors are *dynamically allocated*; any kernel config change can move them | `open()` → EPERM → FastRPC 1002 → silent CPU fallback. Workaround: blanket `{ allow = true, access = "rw" }` (used by the hackathon root app). Verify with `ls -l /dev/fastrpc-cdsp /dev/adsprpc-smd` on the device. |
| 2 | **FastRPC soname list** (7 libs, §2.3) | `npu/npu-setup.sh` (fixed list); `bootstrap.py` (dynamic) | OE image contents; sonames (`.so.0`) can bump; ION is a deprecated kernel API that will eventually disappear | hook prints a per-lib WARNING; bootstrap fails with the missing name. `bootstrap.py` is more robust here — it discovers deps from loader errors instead of a fixed list. |
| 3 | **FastRPC device nodes** (`/dev/fastrpc-cdsp`, `/dev/adsprpc-smd`) | every QNN app's `oakapp.toml` | Luxonis OS device contract | QNN discovery fails without the former; FastRPC transport fails without the latter. |
| 4 | **`/dev/fastrpc-cdsp` probe** | upstream ORT `soc_utils.cc` | `onnxruntime` **version** (not the OS) | "plugin registered but no NPU EP device was enumerated". Re-verify on ORT upgrades. |
| 5 | **kernel FastRPC ABI ↔ libcdsprpc** | implicit | matched **by construction** — runtime linking always uses the running OS's own libs | this was the main risk of the abandoned baked-blob approach; gone now. |
| 6 | **Hexagon arch (V73)** | wheel skel selection | SoC (fixed per product, not per OS release) | the QNN runtime bundles and dispatches per-arch skels; nothing hardcoded on our side. |
| 7 | **Device QAIRT versions (2.32/2.41)** | — | **not used at all** (§1) | no coupling — the wheel runtime is self-contained. Deliberate decoupling decision. |
| 8 | glibc ≥ 2.34 / libstdc++ floor | wheel `manylinux_2_34` | container base image (bookworm 2.36 ✓), not the device OS | only if the base image ever moves to an older userland. |
| 9 | ~~baked FastRPC blobs from OS 1.35.0~~ | *removed* (`onnxruntime-base-pre-squash` only) | was: exactly OS 1.35.0 | historical. |

**Bottom line**: nothing requires "Luxonis OS == X.Y.Z". The two most likely
silent breakages on an OS update are #1 (majors) and #2 (sonames) — both are
things the *platform* should own rather than every app's TOML, which is the
core of the roadmap below. Recommended per-OS-release regression check:
run `examples/minimal_dsp.py --strict` (hackathon repo) on the new OS; it
exercises every seam and fails loudly at the first broken one.

---

## 5. Roadmap — making "run ONNX on the DSP" seamless

Target user experience, in decreasing order of ambition:

```python
# A. ideal: nothing OAK-specific at all
sess = onnxruntime.InferenceSession("model.onnx", providers=["QNNExecutionProvider"])

# B. very good: one Luxonis helper, no oakapp.toml boilerplate beyond one flag
from oak4ort import qnn_session
sess = qnn_session("model.onnx")
```

Today a user must: use a special base image (or vendor `bootstrap.py`), route
through `/entrypoint.sh`, and paste a ~15-line TOML block containing kernel
major numbers. Each layer below removes part of that. The layers (extending
the LuxonisOS / default-container / user-level split with two more that turned
out to matter — **oak-agent/oakctl** and **upstream ONNX Runtime**):

### 5.1 LuxonisOS

1. **Define a stable "NPU userspace" contract.** Today we symlink seven
   libraries by name out of an arbitrary OS `/usr/lib` (§2.3). The OS should
   instead provide a versioned, documented bundle — e.g.
   `/opt/luxonis/npu-runtime/{lib/, MANIFEST}` — containing exactly the
   FastRPC user-space stack blessed for container consumption. Containers
   mount that one directory; the soname list (audit #2) becomes an OS-internal
   concern; the manifest makes breakage diagnosable instead of silent.
2. **Stabilize the device numbers story** (audit #1): reserve fixed majors in
   the kernel config, or — better — make the numbers irrelevant by fixing
   cgroup handling in oak-agent (§5.2.1).
4. **Resolve FastRPC redistribution with Qualcomm.** If Luxonis obtains the
   right to redistribute `libcdsprpc.so` + deps (many Qualcomm Linux BSPs do
   ship these openly), the base image can bake them again and the
   `/usr/lib` mount disappears entirely — the pre-squash Dockerfile already
   implements this and can be resurrected. The ABI risk (audit #5) would need
   a CI test per OS release instead.
5. **(Bigger) Preinstall the QNN/QAIRT runtime as a container-consumable SDK**
   with headers/version guarantees, so ORT could target the device runtime
   (the `QNN_DEVICE_ERROR_INVALID_CONFIG` failure would need root-causing
   first). Low priority: the wheel-runtime approach works and self-updates
   with pip.

### 5.2 oak-agent / oakctl (the layer between OS and container)

1. **Fix `optional_devices` to add matching device-cgroup allow rules
   automatically.** This is the root cause of the worst UX failure (EPERM →
   FastRPC 1002 → *silent* CPU fallback) and removes `allowed_devices` — and
   with it the kernel-major hardcoding (audit #1) — from every app's TOML.
   Arguably a plain bug fix.
2. **Add a single opt-in feature flag** to `oakapp.toml`, e.g.
   `features = ["npu"]`, that oak-agent expands into the §2.2 + §2.3
   devices/mounts/cgroup set. The 15-line copy-paste block becomes one line,
   and Luxonis can evolve the underlying node names/paths without breaking
   apps.
3. **`oakctl` diagnostics**: an `oakctl app doctor`-style check that runs the
   §4 regression probe in a scratch container and reports which seam is
   broken (node present? cgroup open OK? libs linkable? EP enumerates NPU?).
   Today users discover problems as "it's slow", i.e. never.

### 5.3 oakapp base image (this repo)

1. **Publish `luxonis/oakapp-base:X.Y.Z-onnxruntime` officially** (linux/arm64
   only; release steps already in `README.md`). Unblocks users from the
   on-device-registry workaround (§3.2).
2. **Consider folding the NPU hooks into the default images.** The
   entrypoint.d mechanism + `npu-setup.sh` are no-ops without the NPU
   passthrough, so they are safe in every variant; then the *only* thing the
   onnxruntime variant adds is preinstalled ORT wheels (a convenience, and it
   pins a tested version pair). That would let users on the stock image get
   NPU support by just pip-installing `onnxruntime-qnn` — no `oak4ort`
   bootstrap needed.
3. **CI**: an on-device (or QEMU + mocked /dev) smoke test that builds the
   variant, runs `minimal_dsp.py --strict` against a matrix of
   {OS release} × {ORT/ORT-QNN version}, catching audit #2/#4 drift before
   users do.
4. Keep the hook contract documented: hooks are sourced, must not exit
   non-zero, may export env — useful for future variants (CUDA-style EPs,
   other accelerators).

### 5.4 User level (`oak4ort`, app templates)

1. **Ship `oak4ort` as a real package** (PyPI `oak4ort`, or fold into
   `depthai` / a `depthai-onnx` extra) instead of vendoring per app. Merge
   the two variants back into one package: full bootstrap (works everywhere)
   that detects and no-ops when the base image/OS already did the work —
   `oak4ort_slim` then disappears, and future platform improvements shrink
   what the package does at runtime, transparently.
2. **Make silent CPU fallback harder to ship by accident**: log an explicit
   one-line placement summary (`X/Y nodes on HTP`) at session creation; and
   consider `fallback_to_cpu=False` as the recommended default in examples —
   apps that *want* graceful degradation opt in.
3. **Pre-warm EPContext at install time.** `prepare_container` steps run on
   the device at app install; a `python -m oak4ort.precompile model.onnx`
   step there moves the 0.3–3.2 s HTP compile from first launch to install.
   Alternatively support shipping prebuilt EPContext caches (they are stable
   for a fixed model + ORT/QNN version + options key).
3. **Model-prep CLI**: wrap the recurring offline steps
   (`make_dynamic_shape_fixed`, QDQ quantization, the `freeze_vision.py`
   partial-evaluation trick) into one `oak4ort prep` command with good
   diagnostics ("this graph has data-dependent shapes at node X").
4. **oakctl app template** (`oakctl init --template onnxruntime`): correct
   TOML + entrypoint + a working minimal app, so nobody re-derives the setup.

### 5.5 Upstream ONNX Runtime (Microsoft/Qualcomm)

1. Ask for an EP provider option to skip device probing
   entirely (explicit "the NPU is there, trust me") — probing by /dev name is
   inherently distro-fragile.

### 5.6 DepthAI (stretch)

An ORT-backed host-node helper (thin wrapper marrying `qnn_session` with
`dai.node.ThreadedHostNode`, as done ad hoc in `yolo26-dsp/main.py`) would
make "native NN for camera models, ORT-QNN for everything else" a supported
pattern inside one pipeline. The benchmark data (`benchmark/RESULTS.md`)
shows each path wins for different model classes (native DLC for yolo26, ORT
for ViTs), so they are complements, not rivals.

---

## 6. Recommended end state and priority order

The minimal set that gets users to "add `onnxruntime-qnn` to requirements,
write normal ORT code":

| Priority | Change | Layer | Removes for the user |
|---|---|---|---|
| 1 | oak-agent: auto-cgroup for `optional_devices` (§5.2.1) | oak-agent | `allowed_devices` + kernel majors + the silent-fallback trap |
| 2 | `features = ["npu"]` expansion (§5.2.2) | oak-agent/oakctl | the whole TOML block |
| 3 | publish `-onnxruntime` base image (§5.3.1), later fold hooks into default images (§5.3.2) | base image | special image / vendored bootstrap |
| 4 | versioned NPU-userspace bundle in the OS (§5.1.1) | OS | soname fragility; makes the mount self-describing |
| 5 | `oak4ort` on PyPI + install-time EPContext precompile (§5.4) | user level | cold-start compile; copy-pasted helper code |

With 1–3 done, `oakapp.toml` needs one flag, any base image works after a pip
install, and `qnn_session()` shrinks to EP registration + EPContext caching —
pure convenience rather than life support. `oak4ort` should remain as the
ergonomic entry point either way (strict mode, caching, good errors).

---

## Appendix A — failure-mode cheat sheet

| Symptom | Cause | Fix |
|---|---|---|
| `QNN EP unavailable: no FastRPC device node` | required FastRPC node was not passed through | add both nodes from §2.2 `optional_devices` |
| FastRPC error 1002 in logs / inference runs but ~10–60× too slow (silent CPU fallback) | device node present but cgroup-denied (EPERM) | add §2.2 `allowed_devices`; check majors with `ls -l /dev/fastrpc-cdsp /dev/adsprpc-smd` |
| `plugin registered but no NPU EP device was enumerated` | `/dev/fastrpc-cdsp` was not passed through | add it to `optional_devices` |
| `cannot load libcdsprpc.so` | `/usr/lib:/host_usr_lib` mount missing | add §2.3 `optional_mounts` |
| `libatomic.so.1: cannot open shared object file` | stock base image without apt `libatomic1` and bootstrap not used | use the onnxruntime base image or `oak4ort.bootstrap()` |
| first inference takes seconds | HTP graph compile (EPContext cache cold) | expected once per model; pre-warm (§5.4.3) |
| `balanced` mode numbers look like `burst` (or vice versa) | HTP perf mode is device-global state | measure per-process; see §3.4 |
| some nodes on CPU (`Unsupported nodes in QNN EP` warning) | op/shape not HTP-placeable (often an export artifact — inconsistent ranks, dynamic dims) | fix the export; `verbose=True` shows placement; `fallback_to_cpu=False` makes it fatal |
| `input 'X' has non-static shape` | dynamic dims | `onnxruntime.tools.make_dynamic_shape_fixed` or graph freezing |

## Appendix B — file map

In this repo (`onnxruntime-base` branch):

| File | Role |
|---|---|
| `Dockerfile.onnxruntime` | base-image variant (§3.2) |
| `entrypoint.sh` | adds the `/etc/entrypoint.d` hook mechanism |
| `npu/npu-setup.sh` | entrypoint hook: FastRPC library linking |
| `README.md` § "ONNX Runtime (NPU) Variant" | user-facing quick reference + TOML template |
| branch `onnxruntime-base-pre-squash` | history incl. the abandoned baked-blob approach (`fastrpc/`) |

In the hackathon workspace (`hackathon/oak4-ort-qnn/`):

| Path | Role |
|---|---|
| `oak4ort/` | full, self-bootstrapping variant (`bootstrap.py` + `session.py`) for stock base images |
| `oak4ort_slim/` | canonical slim variant (no bootstrap) to pair with `oakapp-base:onnxruntime`; vendored into apps |
| `yolo26-dsp/` | reference consumer of the base image + vendored `oak4ort_slim/`; `yolo26-dsp/oakapp.toml` is the reference TOML |
| `examples/minimal_dsp.py` | run any .onnx on the DSP; doubles as the per-OS-release regression probe |
| `PLAN.md`, `RESULTS.md` | original investigation log, correctness + latency validation |
| `benchmark/` | ORT-QNN vs CPU vs native-DLC study across 5 zoo models |
| `recon/` | on-device recon app that established the §1 facts (device nodes, QAIRT versions, lib layout) |
| `smolvlm-dsp/scripts/freeze_vision.py` | technique for making dynamic HF exports HTP-compilable |
