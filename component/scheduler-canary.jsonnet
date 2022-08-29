// main template for openshift4-slos
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local slo = import 'slos.libsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_slos;


local kustomization = {
  kustomization: {
    resources: [
      'https://github.com/appuio/scheduler-canary-controller//config/default?ref=%s' % params.canary_scheduler_controller.manifests_version,
    ],
    local image = params.images.canary_scheduler_controller,
    images: [ {
      name: 'quay.io/appuio/scheduler-canary-controller',
      newTag: image.tag,
      newName: '%s/%s' % [ image.registry, image.image ],
    } ],
  } + com.makeMergeable(params.canary_scheduler_controller.kustomize_input),
};

if params.canary_scheduler_controller.enabled then
  kustomization
else
  { kustomization: {} }
