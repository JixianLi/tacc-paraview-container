# tacc-paraview-container

Apptainer build recipes for running [ParaView](https://www.paraview.org/) with
the [Topology ToolKit (TTK)](https://topology-tool-kit.github.io/) plugin on
TACC systems (tested on Lonestar6).

This is a **server-only** build: ParaView is compiled without Qt, so the image
provides `pvbatch`, `pvserver`, and the Python module — no desktop GUI. Use it
for batch analysis scripts and for client/server sessions where the desktop
ParaView client runs on your laptop.

## What's included

- ParaView 6.1.1 (canonical edition, Python enabled, MPI off)
- TTK plugin built against ParaView 6.x (pinned to a dev-branch commit, since
  no TTK tagged release supports ParaView 6.x yet)
- Python 3.13 (managed by [uv](https://docs.astral.sh/uv/)) with the `paraview`
  module made importable via a `.pth` file
- TBB-based SMP backend

## Recipes

| Backend | Definition file | When to use |
|---|---|---|
| EGL    | `paraview6.1.1/paraview-egl.def`    | GPU nodes — hardware-accelerated rendering via the host NVIDIA driver (`--nv`) |
| OSMesa | `paraview6.1.1/paraview-osmesa.def` | Any partition — software rendering, no GPU required |

The two `.def` files are thin wrappers that set `BACKEND={egl,osmesa}` and run
[`paraview6.1.1/build-common.sh`](paraview6.1.1/build-common.sh), which holds
the actual build steps (apt deps, ParaView + TTK configure/build, Python
wiring). Bump the ParaView tag, the TTK commit, or any shared build flag in
that one script.

## Requirements

- A TACC system with `apptainer` available (e.g. Lonestar6)
- Outbound HTTPS during the build (apt, `astral.sh`, `gitlab.kitware.com`,
  `github.com`)
- ~10+ GB free in `$APPTAINER_CACHEDIR` and the build output directory

## Build

The build is CPU-heavy and long; run it from an interactive compute session so
you don't hit the login-node per-process CPU-time limit:

```bash
idev -p development -N 1 -n 128 -t 01:00:00
cd $WORK
/path/to/tacc-paraview-container/paraview6.1.1/install.sh
```

Options:

```
install.sh [-b|--backend egl|osmesa] [-o|--output PATH]
```

The cache directory defaults to `$SCRATCH/.apptainer_cache`; override with
`APPTAINER_CACHEDIR`. Output defaults to `./paraview-6.1.1-<backend>.sif`.

## Run

EGL build on a GPU node (passes the host NVIDIA driver into the container):

```bash
apptainer exec --nv paraview-6.1.1-egl.sif pvbatch your_script.py
```

OSMesa build on any partition (no `--nv`):

```bash
apptainer exec paraview-6.1.1-osmesa.sif pvbatch your_script.py
```

To connect a desktop ParaView client, run `pvserver` inside the container on a
compute node and forward the port to your laptop.

## Notes

- The TTK commit is pinned in `build-common.sh` (`TTK_COMMIT=…`). Bump it
  when a TTK tagged release with ParaView 6.x support lands or when you want
  newer dev fixes.
- `.sif` files are gitignored — built images are large and belong on
  `$SCRATCH`/`$WORK`, not in the repo.

## License

MIT — see [LICENSE](LICENSE).
