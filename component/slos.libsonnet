local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_slos;

local defaultSlos = {
  'workload-schedulability': {
    local config = params.slos['workload-schedulability'],
    sloth_input: {
      version: 'prometheus/v1',
      service: 'workload-schedulability',
      _slos: {
        [if config.canary.enabled then 'canary']: {
          description: 'OpenShift workload schedulability SLO based on github.com/appuio/scheduler-canary-controller canary',
          sli: {
            events: {
              local queryParams = { namespace: params.namespace },
              error_query: 'sum by (name) (rate(scheduler_canary_pod_until_completed_seconds_count{exported_namespace="%(namespace)s",reason="timed_out"}[{{.window}}]))' % queryParams,
              total_query: 'sum by (name) (rate(scheduler_canary_pod_until_completed_seconds_count{exported_namespace="%(namespace)s"}[{{.window}}]))' % queryParams,
            },
          },
          alerting: {
            name: 'SLO_CanaryWorkloadTimesOut',
            annotations: {
              summary: 'Canary workloads time out.',
            },
            page_alert: {},
            ticket_alert: {},
          },
        } + config.canary,
      },
    },
  },

  storage: {
    local config = params.slos.storage,
    sloth_input: {
      version: 'prometheus/v1',
      service: 'storage',
      _slos: {
        'csi-operations': {
          description: 'SLO based on number of failed csi operations',
          sli: {
            events: {
              error_query: 'sum(rate(storage_operation_duration_seconds_count{volume_plugin=~"%s",operation_name=~"%s",status="fail-unknown"}[{{.window}}]))' % [ config['csi-operations']._sli.volume_plugin, config['csi-operations']._sli.operation_name ],
              total_query: 'sum(rate(storage_operation_duration_seconds_count{volume_plugin=~"%s",operation_name=~"%s"}[{{.window}}]))' % [ config['csi-operations']._sli.volume_plugin, config['csi-operations']._sli.operation_name ],
            },
          },
          alerting: {
            name: 'SLO_StorageOperationHighErrorRate',
            annotations: {
              summary: 'High storage operation error rate',
            },
            page_alert: {},
            ticket_alert: {},
          },
        } + config['csi-operations'],
      },
    },
  },
  ingress: {
    local config = params.slos.ingress,
    local os = com.getValueOrDefault(inv.parameters, 'openshift', {}),
    local appsDomain = com.getValueOrDefault(os, 'appsDomain', ''),

    sloth_input: {
      version: 'prometheus/v1',
      service: 'ingress',
      _slos: {
        canary: {
          description: 'OpenShift ingress SLO based on canary availability',
          sli: {
            raw: {
              error_ratio_query: '1 - avg_over_time(ingress_canary_route_reachable[{{.window}}])',
            },
          },
          alerting: {
            name: 'SLO_ClusterIngressFailure',
            annotations: {
              summary: 'Probes to ingress canary fail',
              [if appsDomain != '' then 'canary_url']: 'canary-openshift-ingress-canary.%s' % appsDomain,
            },
            page_alert: {},
            ticket_alert: {},
          },
        } + config.canary,
      },
    },
  },
  kubernetes_api: {
    local config = params.slos.kubernetes_api,
    sloth_input: {
      version: 'prometheus/v1',
      service: 'kubernetes_api',
      _slos: {
        requests: {
          description: 'Kubernetes API Server SLO based on failed requests',
          sli: {
            events: {
              error_query: 'sum(rate(apiserver_request_total{code=~"(5..|429)",apiserver=~"%s"}[{{.window}}]))' % [ config.requests._sli.apiserver ],
              total_query: 'sum(rate(apiserver_request_total{apiserver=~"%s"}[{{.window}}]))' % [ config.requests._sli.apiserver ],
            },
          },
          alerting: {
            name: 'SLO_KubeApiServerHighErrorRate',
            annotations: {
              summary: 'High Kubernetes API server error rate',
            },
            page_alert: {},
            ticket_alert: {},
          },
        } + config.requests,
        canary: {
          description: 'Kubernetes API Server SLO based on canary probes',
          sli: {
            raw: {
              error_ratio_query: '1 - (sum_over_time(probe_success{job="probe-k8s-api"}[{{.window}}])/count_over_time(up{job="probe-k8s-api"}[{{.window}}]))',
            },
          },
          alerting: {
            name: 'SLO_KubeApiServerFailure',
            annotations: {
              summary: 'Probes to Kubernetes API server fail',
            },
            page_alert: {},
            ticket_alert: {},
          },
        } + config.canary,
      },
    },
  },

  network: {
    local config = params.slos.network,
    sloth_input: {
      version: 'prometheus/v1',
      service: 'network',
      _slos: {
        requests: {
          description: 'Kubernetes network SLO based on lost pings',
          sli: {
            events: {
              error_query: 'sum(rate(ping_rtt_seconds_count{reason="lost"}[{{.window}}]))',
              total_query: 'sum(rate(ping_rtt_seconds_count[{{.window}}]))',
            },
          },
          alerting: {
            name: 'SLO_NetworkPacketLossHigh',
            annotations: {
              summary: 'High number of lost network packets',
            },
            page_alert: {},
            ticket_alert: {},
          },
        } + config.canary,
      },
    },
  },
};

local patchSLO(slo) =
  local p =
    {
      alerting: {
        labels: params.alerting.labels,
        page_alert: {
          labels: params.alerting.page_labels,
        },
        ticket_alert: {
          labels: params.alerting.ticket_labels,
        },
      },
    }
    +
    com.makeMergeable(slo);
  local enabled = com.getValueOrDefault(p, 'enabled', true);
  if enabled then p else null;

local patchSlothInput(name, spec) =
  local slos = std.prune(std.map(
    patchSLO,
    com.getValueOrDefault(spec.sloth_input, 'slos', [])
    +
    [
      spec.sloth_input._slos[name] { name: name }
      for name in std.objectFields(
        com.getValueOrDefault(spec.sloth_input, '_slos', {})
      )
    ]
  ));
  if std.length(slos) > 0 then
    spec {
      sloth_input+: {
        slos: slos,
      },
    }
  else null;


local addRunbook(name, spec) =
  local f(sloName, slo) = slo {
    alerting+: {
      annotations+: {
        runbook_url: 'https://hub.syn.tools/openshift4-slos/runbooks/%s.html#%s' % [ name, sloName ],
      },
    },
  };
  spec {
    sloth_input+: {
      _slos: std.mapWithKey(f, spec.sloth_input._slos),
    },
  };

local specs = std.mapWithKey(addRunbook, defaultSlos) + com.makeMergeable(params.specs);
{
  Specs: std.prune(std.mapWithKey(patchSlothInput, specs)),
}
