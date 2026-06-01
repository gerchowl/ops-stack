# NixOS impl of ops.observability — agent (node_exporter), GPU exporter, and
# server (Prometheus) roles. A host may enable any combination (anvil = server
# + agent + gpu). See interface.nix for the options contract.
{ config, lib, pkgs, ... }:

let
  cfg = config.ops.observability;
  hasTextfile = lib.elem "textfile" cfg.agent.enabledCollectors;
  ing = config.ops.ingress;
  # TLS is configured (file/tailscale point Traefik at explicit paths;
  # "internal" lets Traefik serve its built-in self-signed default cert).
  ingHasCertPaths = ing.certSource != "internal" && ing.certFile != null && ing.keyFile != null;
in
{
  config = lib.mkMerge [
    # ---- agent: node_exporter ----
    (lib.mkIf cfg.agent.enable {
      services.prometheus.exporters.node = {
        enable = true;
        listenAddress = cfg.agent.listenAddress;
        port = cfg.agent.port;
        enabledCollectors = cfg.agent.enabledCollectors;
        extraFlags = lib.optionals hasTextfile
          [ "--collector.textfile.directory=${cfg.agent.textfileDir}" ];
      };

      systemd.tmpfiles.rules = lib.optionals hasTextfile
        [ "d ${cfg.agent.textfileDir} 0755 node-exporter node-exporter - -" ];

      # Source-restrict the exporter port to the listed scrapers (iptables
      # firewall pattern; port is NOT added to allowedTCPPorts so default-drop
      # covers everyone else).
      networking.firewall.extraCommands = lib.concatMapStrings (src: ''
        iptables -I nixos-fw -p tcp -s ${src} --dport ${toString cfg.agent.port} -j nixos-fw-accept
      '') cfg.agent.allowScrapeFrom;
      networking.firewall.extraStopCommands = lib.concatMapStrings (src: ''
        iptables -D nixos-fw -p tcp -s ${src} --dport ${toString cfg.agent.port} -j nixos-fw-accept || true
      '') cfg.agent.allowScrapeFrom;
    })

    # ---- GPU exporter (nvidia-smi based; consumer Blackwell OK) ----
    (lib.mkIf cfg.gpu.enable {
      services.prometheus.exporters.nvidia-gpu = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = 9835;
      };
    })

    # ---- server: Prometheus ----
    (lib.mkIf cfg.server.enable {
      services.prometheus = {
        enable = true;
        listenAddress = cfg.server.listenAddress;
        port = cfg.server.port;
        retentionTime = cfg.server.retention;
        scrapeConfigs = map (t: {
          job_name = t.job;
          static_configs = [{
            targets = [ t.address ];
            labels = t.labels;
          }];
        }) cfg.server.scrapeTargets;
      };
    })

    # ---- server: Grafana (provisioned with the Prometheus datasource) ----
    (lib.mkIf (cfg.server.enable && cfg.server.grafana.enable) {
      services.grafana = {
        enable = true;
        settings.server = {
          http_addr = cfg.server.grafana.listenAddress;
          http_port = cfg.server.grafana.port;
          domain = cfg.server.grafana.domain;
          root_url = "https://${cfg.server.grafana.domain}/";
        };
        provision.datasources.settings.datasources = [{
          name = "Prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://${cfg.server.listenAddress}:${toString cfg.server.port}";
          isDefault = true;
        }];
      };
    })

    # ---- ingress: Traefik (Host-routed reverse proxy) ----
    # Control-plane-agnostic TLS (see interface.nix certSource): explicit
    # cert/key paths for file|tailscale; built-in self-signed for "internal".
    # Routes by Host header on one entrypoint → can front many backends
    # (Grafana now; OpenWebUI/llama later) — the consolidation Tailscale Serve
    # can't do. Survives the planned headscale migration: only certSource flips.
    (lib.mkIf ing.enable {
      services.traefik = {
        staticConfigOptions = {
          entryPoints.websecure.address = ing.entryPointAddress;
          # No ACME: tailnet-internal. TLS comes from the dynamic config below.
          log.level = "INFO";
        };
        dynamicConfigOptions = {
          http = {
            routers = lib.listToAttrs (map (r: {
              name = r.name;
              value = {
                rule = "Host(`${r.host}`)";
                service = r.name;
                entryPoints = [ "websecure" ];
                tls = { };
              };
            }) ing.routers);
            services = lib.listToAttrs (map (r: {
              name = r.name;
              value.loadBalancer.servers = [{ url = r.upstream; }];
            }) ing.routers);
          };
          # Default cert for the websecure entrypoint. For "internal" we omit
          # this entirely and Traefik generates a self-signed default cert.
          tls = lib.mkIf ingHasCertPaths {
            stores.default.defaultCertificate = {
              certFile = ing.certFile;
              keyFile = ing.keyFile;
            };
          };
        };
      };

      # Traefik (runs as the `traefik` user) must read the cert/key when they're
      # explicit files. Caller is responsible for the files existing + readable
      # by group traefik (e.g. a `tailscale cert` oneshot writing into dataDir).
      assertions = [{
        assertion = ing.certSource == "internal" || ingHasCertPaths;
        message = "ops.ingress.certSource = \"${ing.certSource}\" requires certFile + keyFile to be set.";
      }];
    })
  ];
}
