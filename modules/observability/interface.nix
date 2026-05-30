# Portable options for the observability module — platform-free (imported by
# BOTH the NixOS and darwin module). This is the contract; impls diverge in
# nixos.nix / darwin.nix. See gerchowl/anvil#34.
{ lib, ... }:
{
  options.ops.observability = {
    agent = {
      enable = lib.mkEnableOption "node_exporter agent (this host exports metrics)";

      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = ''
          Address node_exporter binds. Set to the host's tailnet (or bridge) IP
          so the server can scrape it; pair with `allowScrapeFrom` on NixOS. On
          darwin (no NixOS firewall) bind the tailnet IP and gate with a
          Tailscale ACL — never 0.0.0.0 on a roaming laptop.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 9100;
      };

      allowScrapeFrom = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Source IPs permitted to reach the exporter port (NixOS firewall,
          source-restricted accept). Empty = rely on listenAddress binding only.
          NixOS-only; ignored on darwin.
        '';
      };

      enabledCollectors = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "systemd" "processes" "textfile" ];
        description = "node_exporter collectors. NixOS defaults; darwin ignores Linux-only ones.";
      };

      textfileDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/node-exporter-textfiles";
        description = "Directory the textfile collector reads *.prom from (per-host collectors drop files here).";
      };
    };

    gpu.enable = lib.mkEnableOption "NVIDIA GPU exporter (nvidia-smi based, :9835). NixOS-only.";

    server = {
      enable = lib.mkEnableOption "Prometheus server (scrapes the fleet)";

      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Prometheus bind address (front it with Traefik/Tailscale for UI access).";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 9090;
      };

      retention = lib.mkOption {
        type = lib.types.str;
        default = "90d";
      };

      scrapeTargets = lib.mkOption {
        default = [ ];
        description = "Targets the server scrapes. One static target per entry.";
        type = lib.types.listOf (lib.types.submodule {
          options = {
            job = lib.mkOption { type = lib.types.str; description = "Prometheus job_name."; };
            address = lib.mkOption { type = lib.types.str; description = "host:port to scrape."; };
            labels = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "Static labels attached to this target.";
            };
          };
        });
      };

      grafana = {
        enable = lib.mkEnableOption "Grafana, auto-provisioned with the server's Prometheus datasource";
        listenAddress = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Grafana bind address. Keep on loopback; front it with the ingress for tailnet access.";
        };
        port = lib.mkOption { type = lib.types.port; default = 3000; };
        domain = lib.mkOption {
          type = lib.types.str;
          default = "localhost";
          description = "Grafana root_url domain — set to the ingress FQDN once Traefik fronts it.";
        };
      };
    };
  };
}
