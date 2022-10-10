// main template for openshift4-slos
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local slo = import 'slos.libsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_slos;


local kustomization =
  if params.canary_scheduler_controller.enabled then
    local image = params.images.canary_scheduler_controller;
    com.Kustomization(
      'https://github.com/appuio/scheduler-canary-controller//config/default',
      params.canary_scheduler_controller.manifests_version,
      {
        'quay.io/appuio/scheduler-canary-controller': {
          newTag: image.tag,
          newName: '%(registry)s/%(image)s' % image,
        },
      },
      params.canary_scheduler_controller.kustomize_input,
    )
  else {
    kustomization: {},
  };

kustomization
