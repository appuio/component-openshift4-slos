// main template for openshift4-slos
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local slo = import 'slos.libsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_slos;


local setPriorityClass = {
  patch: |||
    - op: add
      path: "/spec/template/spec/priorityClassName"
      value: "system-cluster-critical"
  |||,
  target: {
    kind: 'Deployment',
    name: 'scheduler-canary-controller-manager',
  },
};

local controllerResources = params.canary_scheduler_controller.resources;

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
      params.canary_scheduler_controller.kustomize_input {
        patches+: [
          setPriorityClass,
        ],
        // NOTE(sg): We generate replacements for each entry of
        // `params.canary_scheduler_controller.resources.limits` and
        // `params.canary_scheduler_controller.resources.requests` here. This
        // works around the limitation that Kustomize replacements can only
        // have a string as `sourceValue` without having a statically managed
        // list of replacements for individual fields in `requests` and
        // `limits`.
        replacements+: [
          {
            sourceValue: controllerResources.limits[field],
            targets: [ {
              select: {
                kind: 'Deployment',
              },
              fieldPaths: [
                'spec.template.spec.containers.[name=manager].resources.limits.%s' % field,
              ],
            } ],
          }
          for field in
            std.objectFields(controllerResources.limits)
        ] + [
          {
            sourceValue: controllerResources.requests[field],
            targets: [ {
              select: {
                kind: 'Deployment',
              },
              fieldPaths: [
                'spec.template.spec.containers.[name=manager].resources.requests.%s' % field,
              ],
            } ],
          }
          for field in
            std.objectFields(controllerResources.requests)
        ],
      },
    )
  else {
    kustomization: { resources: [] },
  };

kustomization
