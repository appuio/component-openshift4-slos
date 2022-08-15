// main template for openshift4-slos
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_slos;

local matchLabels = {
  'app.kubernetes.io/instance': 'prometheus-blackbox-exporter',
  'app.kubernetes.io/name': params.blackbox_exporter.name,
};

local labels = matchLabels {
  'app.kubernetes.io/managed-by': 'commodore',
  'app.kubernetes.io/component': 'openshift4-slos',
};

local exporterConfig = std.manifestYamlDoc(params.blackbox_exporter.config, true, false);

local sa =
  kube.ServiceAccount(params.blackbox_exporter.name) {
    metadata+: {
      labels+: labels,
      namespace: params.blackbox_exporter.namespace,
    },
  };

local configMap =
  kube.ConfigMap(params.blackbox_exporter.name) {
    metadata+: {
      labels+: labels,
      namespace: params.blackbox_exporter.namespace,
    },
    data+: {
      'blackbox.yaml': exporterConfig,
    },
  };

local deploy = com.namespaced(
  params.blackbox_exporter.namespace,
  kube.Deployment(params.blackbox_exporter.name) {
    metadata+: {
      labels+: labels,
      name: params.blackbox_exporter.name,
      namespace: params.blackbox_exporter.namespace,
    },
    spec+: {
      replicas: 1,
      selector: {
        matchLabels: matchLabels,
      },
      template+: {
        metadata+: {
          annotations: {
            'checksum/config': std.md5(exporterConfig),
          },
          labels+: labels,
        },
        spec+: {
          containers: [
            kube.Container('blackbox-exporter') {
              args: [
                '--config.file=/config/blackbox.yaml',
              ],
              image: '%s/%s:%s' % [ params.images.blackbox_exporter.registry, params.images.blackbox_exporter.image, params.images.blackbox_exporter.tag ],
              imagePullPolicy: 'IfNotPresent',
              ports_: {
                http: {
                  containerPort: 9115,
                },
              },
              local probe = {
                httpGet: {
                  path: '/health',
                  port: 'http',
                },
              },
              livenessProbe: probe,
              readinessProbe: probe,
              resources: params.blackbox_exporter.deployment.resources,
              securityContext: {},
              volumeMounts_: {
                config: {
                  mountPath: '/config',
                },
              },
            },
          ],
          restartPolicy: 'Always',
          securityContext: {},
          serviceAccountName: sa.metadata.name,
          volumes_: {
            config: {
              configMap: {
                name: configMap.metadata.name,
              },
            },
          },
        },
      },
    },
  },
);

local service =
  kube.Service(params.blackbox_exporter.name) {
    metadata+: {
      labels+: labels,
      namespace: params.blackbox_exporter.namespace,
    },
    target_pod:: deploy.spec.template,
  };

if params.blackbox_exporter.enabled == true then {
  '10_blackbox_exporter_sa': sa,
  '20_blackbox_exporter_deploy': deploy,
  '20_blackbox_exporter_configmap': configMap,
  '20_blackbox_exporter_service': service,
} else {}
