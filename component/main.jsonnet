// main template for openshift4-slos
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_slos;

// Define outputs below
local mergeSpec = function(name, spec)
  local slothRendered = std.parseJson(kap.yaml_load('sloth-output/%s.yaml' % name));
  local metadata = com.makeMergeable(std.get(spec, 'metadata', {}));
  kube._Object('monitoring.coreos.com/v1', 'PrometheusRule', name) {
    metadata+: metadata,
    spec: slothRendered,
  }
;

std.mapWithKey(mergeSpec, params.specs)
