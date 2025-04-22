local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_slos;

// Each entry in this object is used as the base definition for an SLI/SLO
// pair managed by the component.
// Field `sloth_input` is rendered into a valid input for Sloth and the
// resulting Sloth output is loaded again in main.jsonnet and emitted as a
// PrometheusRule object.
// You can specify additional metadata for the resulting `PrometheusRule`
// object in the optional top-level field `metadata`.
// If you need additional Prometheus rules (e.g. a recording rule to remove
// noisy labels from a metric) to define your SLI query, you can specify
// complete additional rules in top-level field `extra_rules` in the
// corresponding SLO's definition. The contents of this field are added to the
// resulting PrometheusRule object as an extra rule group (cf. main.jsonnet).
local defaultSlos = {
  customer_facing_beta: {
    local config = params.slos['customer-facing-beta'],

    extra_rules: [
      {
        record: 'appuio_ocp4_slo:customer_facing_slo_ingress:error',
        expr: |||
          absent_over_time((sum(rate(haproxy_frontend_http_responses_total{code=~"[1-4]xx"}[1m])) > 0)[3m:]) AND absent_over_time((ingress_canary_route_reachable >0)[3m:])
        |||,
      },
    ],

    sloth_input: {
      version: 'prometheus/v1',
      service: 'customer-facing-beta',
      _slos: {
        ingress: {
          description: |||
            [BETA] Customer facing ingress SLO based on the availability of the ingress.

            NO successful request and NO successful canary request over a period of 3 minutes starts counting to the error budget.

            See https://kb.vshn.ch/oc4/explanations/decisions/customer-facing-slo.html
          |||,
          sli: {
            raw: {
              error_ratio_query:
                '1 - avg_over_time(appuio_ocp4_slo:customer_facing_slo_ingress:error[{{.window}}])',
            },
          },

          alerting: {
            name: 'SLO_CustomerFacingBetaIngressFailure',
            page_alert: {},
            ticket_alert: {},
          },
        } + config.ingress,
      },
    },
  },

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
              error_query: 'sum(rate(scheduler_canary_pod_until_completed_seconds_count{name="canary",exported_namespace="%(namespace)s",reason!="completed"}[{{.window}}]))' % queryParams,
              total_query: 'sum(rate(scheduler_canary_pod_until_completed_seconds_count{name="canary",exported_namespace="%(namespace)s"}[{{.window}}]))' % queryParams,
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
      _slos: std.foldl(
        function(prev, plugin)
          local storageClassName = if plugin == '' then 'default' else plugin;
          local canaryName = 'storage-canary-%s' % storageClassName;
          prev {
            [canaryName]: {
              description: 'OpenShift workload schedulability SLO based on github.com/appuio/scheduler-canary-controller canary',
              sli: {
                events: {
                  local queryParams = { name: canaryName, namespace: params.namespace },
                  error_query: 'sum(rate(scheduler_canary_pod_until_completed_seconds_count{name="%(name)s",exported_namespace="%(namespace)s",reason!="completed"}[{{.window}}]))' % queryParams,
                  total_query: 'sum(rate(scheduler_canary_pod_until_completed_seconds_count{name="%(name)s",exported_namespace="%(namespace)s"}[{{.window}}]))' % queryParams,
                },
              },
              alerting: {
                name: 'SLO_StorageCanaryWorkloadTimesOut',
                annotations: {
                  summary: 'Storage canary workloads time out.',
                },
                labels: {
                  storageclass: storageClassName,
                },
                page_alert: {},
                ticket_alert: {},
              },
            } + config.canary,
          },
        std.filter(
          function(plugin) config.canary._sli.volume_plugins[plugin] != null,
          std.objectFields(config.canary._sli.volume_plugins)
        ),
        {
          'csi-operations': {
            description: 'SLO based on number of failed csi operations',
            sli: {
              events: {
                // We use `or on() vector(0)` here to ensure we always have a
                // value for the error query, even if there's 0 failing storage
                // operations in a time window. This is necessary because the
                // timeseries for status="fail-unknown" may not exist at all if
                // there's no failures.
                error_query:
                  'sum(rate(storage_operation_duration_seconds_count{volume_plugin=~"%s",operation_name=~"%s",status="fail-unknown"}[{{.window}}])) or on() vector(0)'
                  % [ config['csi-operations']._sli.volume_plugin, config['csi-operations']._sli.operation_name ],
                total_query:
                  // We use (sum() > 0) or on() vector(1)) to guard against time
                  // windows where we have 0 storage operations, which would
                  // otherwise result in a division by 0. We do this because,
                  // dividing by 0 results in the whole expression evaluating to
                  // NaN which breaks the SLO alert.
                  // Note that we can safely divide by 1, since there can't be
                  // any failed operations when there's no operations at all, so
                  // if the `vector(1)` is used, the expression will always
                  // reduce to 0/1.
                  '(sum(rate(storage_operation_duration_seconds_count{volume_plugin=~"%s",operation_name=~"%s"}[{{.window}}])) > 0) or on() vector(1)' %
                  [ config['csi-operations']._sli.volume_plugin, config['csi-operations']._sli.operation_name ],
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
        }
      ),
    },
  },
  ingress: {
    local config = params.slos.ingress,
    local os = std.get(inv.parameters, 'openshift', {}),
    // NOTE: appsDomain should always be present if we have parameter `openshift`.
    local appsDomain = std.get(os, 'appsDomain', ''),
    local canaryRoute = 'canary-openshift-ingress-canary.%s' % appsDomain,

    extra_rules: [
      {
        record: 'appuio_ocp4_slo:ingress_canary_route_reachable:no_instance',
        expr: 'max without(pod,instance) (ingress_canary_route_reachable)',
      },
    ],

    sloth_input: {
      version: 'prometheus/v1',
      service: 'ingress',
      _slos: {
        canary: {
          description: 'OpenShift ingress SLO based on canary availability',
          sli: {
            raw: {
              error_ratio_query:
                '1 - avg_over_time(appuio_ocp4_slo:ingress_canary_route_reachable:no_instance{%s}[{{.window}}])'
                % [ if appsDomain != '' then 'host="%s"' % canaryRoute else '' ],
            },
          },
          alerting: {
            name: 'SLO_ClusterIngressFailure',
            annotations: {
              summary: 'Probes to ingress canary fail',
              [if appsDomain != '' then 'canary_url']: canaryRoute,
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
