// main template for openshift4-slos
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local slo = import 'slos.libsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_slos;


// Define outputs below
local mergeSpec = function(name, spec)
  local slothRendered = std.parseJson(kap.yaml_load('%s/sloth-output/%s.yaml' % [ inv.parameters._base_directory, name ]));
  local metadata = com.makeMergeable(std.get(spec, 'metadata', {}));
  kube._Object('monitoring.coreos.com/v1', 'PrometheusRule', name) {
    metadata+: metadata,
    spec: slothRendered,
  }
;

local rules = std.mapWithKey(mergeSpec, slo.Specs);

local probes = com.generateResources(
  params.blackbox_exporter.probes,
  function(name) kube._Object('monitoring.coreos.com/v1', 'Probe', name) {
    metadata+: {
      namespace: params.blackbox_exporter.namespace,
    },
    spec+: {
      prober+: {
        url: '%s.%s.svc:9115' % [ params.blackbox_exporter.name, params.blackbox_exporter.namespace ],
        scheme: 'http',
        path: '/probe',
      },
    },
  }
);

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
  '20_probes': probes,
  '30_canaryImageStream': canaryImageStream,
  '30_canary': canary,
}
+ (import 'blackbox-exporter.libsonnet')
+ rules
