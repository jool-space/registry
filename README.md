# jool.space package registry

Julia package registry for [jool.space](https://github.com/jool-space). Install with:

```julia
using Pkg
Registry.add(url="https://registry.jool.space")
```

## Releasing a package

Registration, tagging, and the GitHub release happen in one synchronous CI run — no Registrator server, no TagBot.

Once per package, copy [`examples/release.yml`](examples/release.yml) to `.github/workflows/release.yml`. Then, to release:

- **GitHub UI:** Actions → Release → Run workflow → choose `patch` / `minor` / `major` / `x.y.z` / `current`.
- **CLI:** `gh workflow run release.yml -f bump=patch`

The workflow bumps `Project.toml`, commits, registers the version here, tags `vX.Y.Z`, and creates a release with generated notes. Every step is skip-if-already-done, so re-running a failed run completes it. Concurrent releases of different packages are serialized against the registry with a rebase-and-retry push.

Who can release: anyone with write access to the package repo. The trust model is GitHub's.

## Yanking a version

Actions → Yank → Run workflow (package name + version). Sets `yanked = true`: the resolver stops picking that version, but pinned manifests keep working.

## How it works

- [`.github/workflows/register.yml`](.github/workflows/register.yml) — reusable workflow called by package repos; checks out the package and this registry side by side.
- [`scripts/register.jl`](scripts/register.jl) — idempotent bump → register ([LocalRegistry](https://github.com/GunnarFarneback/LocalRegistry.jl) headless) → tag.
- [`scripts/check.jl`](scripts/check.jl) — structural consistency check, plus a real `Pkg.Registry.add` into a scratch depot, on every push.
- The registry is read through `https://registry.jool.space` (a server-side redirect to this repo, which git follows) and written only via the deploy key from CI.

## Setup (registry maintainer)

1. **Deploy key**: an SSH keypair; public half as a deploy key on this repo with write access, private half as the `REGISTRY_DEPLOY_KEY` secret (org-level so every package repo inherits it).
2. **Domain**: `registry.jool.space` must be a server-side 301/302 to this repo's URL, preserving path and query (git's first request is `/info/refs?service=git-upload-pack`). GitHub Pages cannot do this; use registrar URL forwarding or a Cloudflare redirect rule. Verify with `git ls-remote https://registry.jool.space`.
