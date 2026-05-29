{
  description = "ops-stack — reusable fleet ops modules (observability, ingress, …) for the gerchowl fleet";

  # No inputs yet: this is a modules-only flake; modules consume the consumer's
  # own pkgs/lib. When we add packages/checks/devShells (e.g. dashboards,
  # exporters, a deploy-rs check matrix) we'll introduce nixpkgs + flake-parts
  # for the per-system × multi-output matrix (see gerchowl/anvil#34 review).
  outputs = { self }: {
    # Portable interface + per-platform impls. Same options on both; `config`
    # diverges because systemd ≠ launchd. Server/GPU roles are NixOS-only.
    nixosModules.observability = {
      imports = [
        ./modules/observability/interface.nix
        ./modules/observability/nixos.nix
      ];
    };
    darwinModules.observability = {
      imports = [
        ./modules/observability/interface.nix
        ./modules/observability/darwin.nix
      ];
    };

    nixosModules.default = self.nixosModules.observability;
    darwinModules.default = self.darwinModules.observability;
  };
}
