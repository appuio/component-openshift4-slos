// main template for openshift4-slos
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local blackbox = import 'blackbox-exporter.libsonnet';
local slo = import 'slos.libsonnet';

local network_canary = import 'network-canary.libsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_slos;


// Define outputs below
local mergeSpec = function(name, spec)
  local slothRendered = std.parseJson(kap.yaml_load('%s/sloth-output/%s.yaml' % [ inv.parameters._base_directory, name ]));
  local metadata = com.makeMergeable(std.get(spec, 'metadata', {}));
  kube._Object('monitoring.coreos.com/v1', 'PrometheusRule', kube.hyphenate(name)) {
    metadata+: metadata,
    spec: slothRendered,
  }
;

local rules = std.mapWithKey(mergeSpec, slo.Specs);


local canaryImageStream = kube._Object('image.openshift.io/v1', 'ImageStream', 'canary') {
  local upstreamImage = params.images.canary,
  metadata+: {
    namespace: params.namespace,
  },
  spec+: {
    tags: [
      {
        annotations: null,
        from: {
          kind: 'DockerImage',
          name: '%(registry)s/%(image)s:%(tag)s' % upstreamImage,
        },
        importPolicy: {},
        name: 'latest',
        referencePolicy: {
          type: 'Local',
        },
      },
    ],
  },
};

local canary = kube._Object('monitoring.appuio.io/v1beta1', 'SchedulerCanary', 'canary') {
  metadata+: {
    namespace: params.namespace,
  },
  spec: {
    local sliConfig = params.slos['workload-schedulability'].canary._sli,
    interval: sliConfig.podStartInterval,
    maxPodCompletionTimeout: sliConfig.overallPodTimeout,
    podTemplate: {
      metadata: {},
      spec: {
        containers: [
          {
            command: [
              'sh',
              '-c',
            ],
            args: [
              'date',
            ],
            image: 'image-registry.openshift-image-registry.svc:5000/%s/%s:latest' % [ canaryImageStream.metadata.namespace, canaryImageStream.metadata.name ],
            imagePullPolicy: 'Always',
            name: 'date',
            resources: {},
            terminationMessagePath: '/dev/termination-log',
            terminationMessagePolicy: 'File',
          },
        ],
        restartPolicy: 'Never',
        schedulerName: 'default-scheduler',
        securityContext: {},
        terminationGracePeriodSeconds: 10,
      },
    },
  },
};

{
  '00_namespace': kube.Namespace(params.namespace) {
    metadata+: {
      labels+: {
        'openshift.io/cluster-monitoring': 'true',
      },
    },
  },
  '30_canaryImageStream': canaryImageStream,
  '30_canary': canary,
}
+ blackbox.deployment
+ blackbox.probes
+ (if params.network_canary.enabled then network_canary else {})
+ rules
