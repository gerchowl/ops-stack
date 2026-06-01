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

  # ---- ingress (Traefik) ----------------------------------------------------
  # Deliberately a SEPARATE concern from observability: a host-level reverse
  # proxy that can front Grafana now and OpenWebUI/llama/etc. later (route by
  # Host header on one port — the consolidation Tailscale Serve can't do).
  # NixOS-only.
  #
  # certSource is abstracted so the planned Tailscale → headscale migration
  # touches ONLY this option, not Traefik's routing: `tailscale` uses
  # `tailscale cert` today; `internal` uses a self-signed/own-CA cert with no
  # control-plane dependency (survives the headscale switch untouched);
  # `file` points at externally-managed cert/key paths (e.g. headscale-issued).
  options.ops.ingress = {
    enable = lib.mkEnableOption "Traefik reverse proxy (tailnet ingress, Host-routed)";

    entryPointAddress = lib.mkOption {
      type = lib.types.str;
      default = ":8444";
      description = ''
        Traefik HTTPS entrypoint. Default :8444 — 443 (OpenWebUI) and 8443
        (llama-server) are already taken by Tailscale Serve on anvil. Bind to a
        specific tailnet IP (e.g. "100.x.y.z:8444") to keep it tailnet-only.
      '';
    };

    certSource = lib.mkOption {
      type = lib.types.enum [ "tailscale" "internal" "file" ];
      default = "internal";
      description = ''
        Where Traefik's TLS cert comes from. CONTROL-PLANE-AGNOSTIC by design:
          - "internal": Traefik serves its own self-signed cert (default TLS
            store). Zero dependency on Tailscale/headscale — survives the
            headscale migration untouched. Browser shows an untrusted-CA
            warning until the CA is trusted once.
          - "tailscale": use a cert from `tailscale cert <fqdn>` (trusted, no
            warning). Works only while Tailscale's control plane is in use.
          - "file": use externally-managed cert/key at certFile/keyFile (e.g.
            headscale-issued, step-ca, mkcert).
      '';
    };

    certFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "TLS cert path (certSource = \"file\" or \"tailscale\").";
    };
    keyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "TLS key path (certSource = \"file\" or \"tailscale\").";
    };

    routers = lib.mkOption {
      default = [ ];
      description = "Host-routed backends. One service per entry.";
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption { type = lib.types.str; description = "Router/service name (unique)."; };
          host = lib.mkOption { type = lib.types.str; description = "Host header to match, e.g. grafana.anvil.<tailnet>."; };
          upstream = lib.mkOption { type = lib.types.str; description = "Backend URL, e.g. http://127.0.0.1:3000."; };
        };
      });
    };
  };
}
