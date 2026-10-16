{ config, lib, pkgs, nodes, ... }:

# Prometheus, Loki and Grafana on one host. Prometheus scrapes every host's homelab.monitoring.targets,
# every host ships its journal to Loki (default.nix). Grafana is the only UI, admin login from sops.
let
  cfg = config.homelab.monitoring.server;
  inherit (lib) mkOption types;

  monitored = lib.filterAttrs (_: node: node.config.homelab.monitoring.enable) nodes;
  jobs = lib.unique (lib.concatMap (node: lib.attrNames node.config.homelab.monitoring.targets) (lib.attrValues monitored));

  # One job per target name, each host a static target named after it.
  scrapeConfig = job: {
    job_name = job;
    tls_config.insecure_skip_verify = true; # self-signed (incus), only used by https targets
    static_configs = lib.mapAttrsToList (name: node:
      let
        inherit (node.config.homelab.monitoring) address;
        t = node.config.homelab.monitoring.targets.${job};
      in {
        targets = [ "${address}:${toString t.port}" ];
        labels = t.labels // {
          instance = name;
          __scheme__ = t.scheme;
          __metrics_path__ = t.path;
        };
      }) (lib.filterAttrs (_: node: node.config.homelab.monitoring.targets ? ${job}) monitored);
  };

  # Pinned upstream dashboards, they pick the datasource through a variable so they load as-is.
  dashboards = pkgs.linkFarm "grafana-dashboards" (lib.mapAttrsToList (name: src: {
    name = "${name}.json";
    path = pkgs.fetchurl src;
  }) {
    node-exporter-full = {
      url = "https://raw.githubusercontent.com/rfmoz/grafana-dashboards/99a25cc154c21c4fcbae1aa24352bf1b6764d847/prometheus/node-exporter-full.json";
      hash = "sha256-3+opah4hCqZoGXYU03CLVnGKmb53lKHCwBLNUdp+y4k=";
    };
    ceph-cluster = {
      url = "https://raw.githubusercontent.com/ceph/ceph/v20.2.4/monitoring/ceph-mixin/dashboards_out/ceph-cluster-advanced.json";
      hash = "sha256-7SeqdN29xf9na/ao13OJjEJM2aqbqUu1ERWWAIbUsQ0=";
    };
    ceph-osds = {
      url = "https://raw.githubusercontent.com/ceph/ceph/v20.2.4/monitoring/ceph-mixin/dashboards_out/osds-overview.json";
      hash = "sha256-1R1S8c+fUTs1j3UUqDXNJ2b2o8rOuV4VE1phlGhCyag=";
    };
    ceph-pools = {
      url = "https://raw.githubusercontent.com/ceph/ceph/v20.2.4/monitoring/ceph-mixin/dashboards_out/pool-overview.json";
      hash = "sha256-sDRkyzFBxBAtlT3rcmdflFBXv7oj9TDDXcTXFGNKbb4=";
    };
  });

  lokiDir = config.services.loki.dataDir;
in
{
  options.homelab.monitoring.server = {
    enable = lib.mkEnableOption "Prometheus, Loki and Grafana for every host in the flake";

    grafanaPort = mkOption {
      type = types.port;
      default = 3000;
    };

    # Every host pushes its journal here.
    lokiPort = mkOption {
      type = types.port;
      default = 3100;
    };

    metricsRetention = mkOption {
      type = types.str;
      default = "30d";
    };

    logsRetention = mkOption {
      type = types.str;
      default = "14d";
    };

    # Holds grafana-admin-password and grafana-secret-key.
    secretsFile = mkOption {
      type = types.path;
      default = config.sops.defaultSopsFile;
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      listenAddress = "127.0.0.1"; # Grafana is the UI
      retentionTime = cfg.metricsRetention;
      globalConfig = {
        scrape_interval = "30s";
        evaluation_interval = "30s";
      };
      ruleFiles = [ ./config/rules.yml ];
      scrapeConfigs = map scrapeConfig jobs;
    };

    services.loki = {
      enable = true;
      configuration = {
        auth_enabled = false;
        server = {
          http_listen_port = cfg.lokiPort;
          grpc_listen_address = "127.0.0.1";
        };
        common = {
          path_prefix = lokiDir;
          replication_factor = 1;
          ring = {
            instance_addr = "127.0.0.1";
            kvstore.store = "inmemory";
          };
          storage.filesystem = {
            chunks_directory = "${lokiDir}/chunks";
            rules_directory = "${lokiDir}/rules";
          };
        };
        schema_config.configs = [{
          from = "2026-10-01";
          store = "tsdb";
          object_store = "filesystem";
          schema = "v13";
          index = {
            prefix = "index_";
            period = "24h";
          };
        }];
        limits_config.retention_period = cfg.logsRetention;
        compactor = {
          working_directory = "${lokiDir}/compactor";
          retention_enabled = true;
          delete_request_store = "filesystem";
        };
        analytics.reporting_enabled = false;
      };
    };

    sops.secrets = lib.genAttrs [ "grafana-admin-password" "grafana-secret-key" ] (key: {
      sopsFile = cfg.secretsFile;
      inherit key;
      owner = "grafana";
      restartUnits = [ "grafana.service" ];
    });

    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "0.0.0.0";
          http_port = cfg.grafanaPort;
        };
        security = {
          admin_user = "admin";
          admin_password = "$__file{${config.sops.secrets."grafana-admin-password".path}}";
          secret_key = "$__file{${config.sops.secrets."grafana-secret-key".path}}";
        };
        analytics = {
          reporting_enabled = false;
          check_for_updates = false;
        };
      };

      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            uid = "prometheus";
            type = "prometheus";
            url = "http://127.0.0.1:${toString config.services.prometheus.port}";
            isDefault = true;
          }
          {
            name = "Loki";
            uid = "loki";
            type = "loki";
            url = "http://127.0.0.1:${toString cfg.lokiPort}";
          }
        ];
        dashboards.settings.providers = [{
          name = "homelab";
          options.path = dashboards;
        }];
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.grafanaPort cfg.lokiPort ];
  };
}
