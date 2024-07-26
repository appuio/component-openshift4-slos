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
  local metadata = com.makeMergeable(
    std.get(spec, 'metadata', {}) + {
      labels+: { 'monitoring.syn.tools/enabled': 'true' },
    },
  );
  local extra_rules = std.get(spec, 'extra_rules', []);
  kube._Object('monitoring.coreos.com/v1', 'PrometheusRule', kube.hyphenate(name)) {
    metadata+: metadata,
    spec: slothRendered {
      [if std.length(extra_rules) > 0 then 'groups']+: [
        {
          name: 'syn-sloth-slo-%s-extra-rules' % name,
          rules: extra_rules,
        },
      ],
    },
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
        affinity: {
          nodeAffinity: params.canary_node_affinity,
        },
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

local storageCanaries = std.flattenArrays(std.filterMap(
  function(storageclass) params.slos.storage.canary._sli.volume_plugins[storageclass] != null,
  function(storageclass)
    local p = params.slos.storage.canary._sli.volume_plugins_default_params + com.makeMergeable(params.slos.storage.canary._sli.volume_plugins[storageclass]);
    local manifestName = 'storage-canary-%s' % if storageclass == '' then 'default' else storageclass;
    [
      kube.PersistentVolumeClaim(manifestName) {
        metadata+: {
          namespace: params.namespace,
        },
        spec+: {
          accessModes: [ p.accessMode ],
          resources: {
            requests: {
              storage: p.size,
            },
          },
          [if storageclass != '' then 'storageClassName']: storageclass,
        },
      },
      kube._Object('monitoring.appuio.io/v1beta1', 'SchedulerCanary', manifestName) {
        metadata+: {
          namespace: params.namespace,
        },
        spec: {
          interval: p.interval,
          maxPodCompletionTimeout: p.maxPodCompletionTimeout,
          forbidParallelRuns: true,
          podTemplate: {
            metadata: {},
            spec: {
              affinity: {
                nodeAffinity: params.canary_node_affinity,
              },
              containers: [
                {
                  command: [
                    'sh',
                    '-c',
                  ],
                  args: [
                    std.join(';\n', [
                      'set -euo pipefail',
                      'f="/testmount/t-`date -Iseconds`"',
                      'echo test > "$f"',
                      'test `cat "$f"` = "test"',
                      'rm -f "$f"',
                    ]),
                  ],
                  image: 'image-registry.openshift-image-registry.svc:5000/%s/%s:latest' % [ canaryImageStream.metadata.namespace, canaryImageStream.metadata.name ],
                  imagePullPolicy: 'Always',
                  name: 'storage',
                  resources: {},
                  terminationMessagePath: '/dev/termination-log',
                  terminationMessagePolicy: 'File',
                  volumeMounts: [
                    {
                      mountPath: '/testmount',
                      name: 'test',
                    },
                  ],
                },
              ],
              volumes: [
                {
                  name: 'test',
                  persistentVolumeClaim: {
                    claimName: manifestName,
                  },
                },
              ],
              restartPolicy: 'Never',
              schedulerName: 'default-scheduler',
              securityContext: {},
              terminationGracePeriodSeconds: 10,
            },
          },
        },
      },
    ]
  ,
  std.objectFields(params.slos.storage.canary._sli.volume_plugins)
));

{
  '00_namespace': kube.Namespace(params.namespace) {
    metadata+: {
      annotations+: {
        'openshift.io/node-selector': '',
      },
      labels+: {
        'openshift.io/cluster-monitoring': 'true',
        'monitoring.syn.tools/infra': 'true',
      },
    },
  },
  '10_secrets': com.generateResources(params.secrets, function(name) com.namespaced(params.namespace, kube.Secret(name))),
  [if params.canary_scheduler_controller.enabled then '30_canaryImageStream']: canaryImageStream,
  [if params.canary_scheduler_controller.enabled then '30_canary']: canary,
  [if params.canary_scheduler_controller.enabled then '32_storageCanary']: storageCanaries,
}
+ blackbox.deployment
+ blackbox.probes
+ (if params.network_canary.enabled then network_canary else {})
+ rules
