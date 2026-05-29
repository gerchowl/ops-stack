# darwin (nix-darwin) impl of ops.observability — AGENT ONLY. The server/GPU
# roles are NixOS-only (a Mac is never the fleet's Prometheus). node_exporter
# runs as a launchd daemon (defined explicitly rather than relying on a
# nix-darwin prometheus module, for portability).
#
# Caveats (gerchowl/anvil#34 SRE review): darwin node_exporter is shallow — no
# /proc, no GPU. For Apple-Silicon GPU/power, add a macmon/powermetrics
# textfile collector (tracked as an ops-stack follow-up). No NixOS firewall on
# darwin: bind `agent.listenAddress` to the tailnet IP + gate with a Tailscale
# ACL. UNVALIDATED until the fleet fan-out phase (anvil-first proves the NixOS
# path).
{ config, lib, pkgs, ... }:

let
  cfg = config.ops.observability;
in
{
  config = lib.mkIf cfg.agent.enable {
    environment.systemPackages = [ pkgs.prometheus-node-exporter ];

    launchd.daemons.node-exporter = {
      serviceConfig = {
        ProgramArguments = [
          "${pkgs.prometheus-node-exporter}/bin/node_exporter"
          "--web.listen-address=${cfg.agent.listenAddress}:${toString cfg.agent.port}"
        ]
        ++ lib.optionals (lib.elem "textfile" cfg.agent.enabledCollectors)
          [ "--collector.textfile.directory=${cfg.agent.textfileDir}" ];
        KeepAlive = true;
        RunAtLoad = true;
      };
    };
  };
}
