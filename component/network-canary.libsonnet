local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local slo = import 'slos.libsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_slos;

local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift');
local splitNodeSelector = std.split(params.network_canary.nodeselector, '=');

local ns = kube.Namespace(params.network_canary.namespace) {
  metadata+: {
    annotations+: {
      'openshift.io/node-selector': params.network_canary.nodeselector,
    },
    labels+: {
      'openshift.io/cluster-monitoring': 'true',
      [if !isOpenshift then 'monitoring.syn.tools/infra']: 'true',
    },
  },
};

local ds = kube.DaemonSet('network-canary') {
  metadata+: {
    namespace: params.network_canary.namespace,
  },
  local image = params.images.network_canary,
  spec+: {
    template+: {
      spec+: {
        containers_+: {
          canary: kube.Container('canary') {
            image: '%s/%s:%s' % [ image.registry, image.image, image.tag ],
            ports_+: { metrics: { containerPort: 2112 } },
            args_: {
              'ping-dns': 'network-canary',
            },
            args: [ '/canary' ] + super.args,
            resources: params.network_canary.resources,
            env_+: {
              POD_IP: {
                fieldRef: {
                  fieldPath: 'status.podIP',
                },
              },
            },
          },
        },
        [if !isOpenshift then 'nodeSelector']: {
          [splitNodeSelector[0]]: splitNodeSelector[1],
        },
        [if !isOpenshift then 'securityContext']: {
          // on non-OCP (tested on RKE2/Ubuntu) we need to set the rootless
          // ping sysctl.
          sysctls: [ {
            name: 'net.ipv4.ping_group_range',
            value: '0 2147483647',
          } ],
        },
        tolerations: std.objectValues(params.network_canary.tolerations),
      },
    },
  },
};

local svc = kube.Service('network-canary') {
  metadata+: {
    namespace: params.network_canary.namespace,
  },
  target_pod: ds.spec.template,
  spec+: {
    clusterIP: 'None',
  },
};


local sm = kube._Object('monitoring.coreos.com/v1', 'ServiceMonitor', 'network-canary') {
  metadata+: {
    namespace: params.network_canary.namespace,
  },
  spec+: {
    endpoints: [ { port: 'metrics' } ],
    selector: {
      matchLabels: {
        name: 'network-canary',
      },
    },
  },
};

{
  '10_network_canary_namespace': ns,
  '20_network_canary_daemonset': ds,
  '20_network_canary_service': svc,
  '20_network_canary_servicemonitor': sm,
}
