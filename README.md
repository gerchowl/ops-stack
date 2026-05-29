# ops-stack

Reusable Nix modules for the **gerchowl fleet's ops layer** — observability now,
ingress / SSO / logs to follow. Consumed as a flake input by each machine's
config (anvil, dotfiles/Macs, vcore3); **not** a monorepo. Decision + reviews:
[gerchowl/anvil#34](https://github.com/gerchowl/anvil/issues/34).

## Design

- **Modules, not a config.** A flake exposing `nixosModules.observability` and
  `darwinModules.observability`. Consumers add the input and set `ops.*` options.
- **Portable interface, per-platform impl.** `interface.nix` holds the options
  (the contract); `nixos.nix` / `darwin.nix` hold the `config` (systemd vs
  launchd). Server + GPU roles are NixOS-only.
- **Server/agent split.** anvil = `server` + `agent` + `gpu`; Macs / vcore3 =
  `agent` only, scraped over the tailnet.
- Native NixOS service modules first; containers (podman) only as an escape
  hatch for services without a good module (e.g. authentik, later).

## Usage

NixOS (e.g. anvil — server + its own agent):

```nix
# flake.nix inputs
ops-stack.url = "github:gerchowl/ops-stack";

# host module
imports = [ inputs.ops-stack.nixosModules.observability ];
ops.observability = {
  agent.enable = true;
  agent.listenAddress = "10.0.0.1";       # bridge/tailnet IP
  gpu.enable = true;
  server.enable = true;
  server.scrapeTargets = [
    { job = "node-host"; address = "127.0.0.1:9100"; labels.host = "anvil"; }
    { job = "gpu";       address = "127.0.0.1:9835"; labels.host = "anvil"; }
    # … fleet agents over the tailnet
  ];
};
```

darwin (nix-darwin — agent only):

```nix
imports = [ inputs.ops-stack.darwinModules.observability ];
ops.observability.agent = {
  enable = true;
  listenAddress = "100.x.y.z";            # this host's tailnet IP
};
```

## Status

- [x] Observability metrics core (Prometheus server + node/GPU exporters, agent)
- [ ] Grafana + Traefik (tailnet TLS) + Loki + Alloy
- [ ] darwin agent validated + Apple-Silicon GPU/power exporter
- [ ] deploy-rs + per-host sops layout (fleet fan-out)

Follow-ups tracked as issues in this repo.
