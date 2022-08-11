// main template for openshift4-slos
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
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

{
  '00_namespace': kube.Namespace(params.namespace) {
    metadata+: {
      labels+: {
        'openshift.io/cluster-monitoring': 'true',
      },
    },
  },
  '20_probes': probes,
} + (import 'blackbox-exporter.libsonnet') + std.mapWithKey(mergeSpec, params.specs)
