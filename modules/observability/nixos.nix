# NixOS impl of ops.observability — agent (node_exporter), GPU exporter, and
# server (Prometheus) roles. A host may enable any combination (anvil = server
# + agent + gpu). See interface.nix for the options contract.
{ config, lib, pkgs, ... }:

let
  cfg = config.ops.observability;
  hasTextfile = lib.elem "textfile" cfg.agent.enabledCollectors;
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
  ];
}
