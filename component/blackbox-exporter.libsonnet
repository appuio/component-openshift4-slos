// main template for openshift4-slos
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_slos;

local k8sAPICanary = params.slos.kubernetes_api.canary;
local defaultModules = {
  [if k8sAPICanary.enabled then 'http_kube_ca_2xx']: {
    http: {
      follow_redirects: true,
      preferred_ip_protocol: 'ip4',
      tls_config: {
        ca_file: '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt',
      },
      prober: 'http',
      timeout: k8sAPICanary._sli.timeout,
    },
  },
};
local defaultProbes = {
  [if k8sAPICanary.enabled then 'kube-api-server']: {
    spec: {
      jobName: 'probe-k8s-api',
      interval: k8sAPICanary._sli.interval,
      module: 'http_kube_ca_2xx',
      targets: {
        staticConfig: {
          static: [
            'https://kubernetes.default.svc.cluster.local/readyz',
          ],
        },
      },
    },
  },
};

local matchLabels = {
  'app.kubernetes.io/instance': 'prometheus-blackbox-exporter',
  'app.kubernetes.io/name': params.blackbox_exporter.name,
};

local labels = matchLabels {
  'app.kubernetes.io/managed-by': 'commodore',
  'app.kubernetes.io/component': 'openshift4-slos',
};

local exporterConfig = std.manifestYamlDoc(
  {
    modules: defaultModules,
  }
  + com.makeMergeable(params.blackbox_exporter.config),
  true,
  false
);

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

local probes = com.generateResources(
  defaultProbes + params.blackbox_exporter.probes,
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
  deployment: if params.blackbox_exporter.enabled == true then {
    '10_blackbox_exporter_sa': sa,
    '20_blackbox_exporter_deploy': deploy,
    '20_blackbox_exporter_configmap': configMap,
    '20_blackbox_exporter_service': service,
  } else {},
  probes: if params.blackbox_exporter.enabled == true then {
    '20_probes': probes,
  } else {},
}
