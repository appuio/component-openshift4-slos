local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local slo = import 'slos.libsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_slos;

local ds = kube.DaemonSet('network-canary') {
  metadata+: {
    namespace: params.namespace,
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
            env_+: {
              POD_IP: {
                fieldRef: {
                  fieldPath: 'status.podIP',
                },
              },
            },
          },
        },
        tolerations: [
          {
            effect: 'NoSchedule',
            key: 'node-role.kubernetes.io/infra',
            operator: 'Exists',
          },
          {
            key: 'storagenode',
            operator: 'Exists',
          },
        ],
      },
    },
  },
};

local svc = kube.Service('network-canary') {
  metadata+: {
    namespace: params.namespace,
  },
  target_pod: ds.spec.template,
  spec+: {
    clusterIP: 'None',
  },
};

{
  '20_network_canary_daemonset': ds,
  '20_network_canary_service': svc,
}
