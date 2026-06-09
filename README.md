# ops-stack (retired → g-fleet)

Folded into **`gerchowl/g-fleet`** (ADR-028, 2026-06-08). The observability
module now lives at `g-fleet:modules/observability/{interface,nixos,darwin}.nix`;
anvil's wiring is `g-fleet:modules/anvil-observability.nix`.

ADR-025 kept this a separate public repo for aspirational reuse + anonymous
root-fetch; with 0 external consumers and remote-as-user deploys proven, that
rationale didn't hold. Archived; history preserved. Do not consume as an input.
