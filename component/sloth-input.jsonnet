// main template for openshift4-slos
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_slos;

local specs = std.mapWithKey(
  function(name, obj)
    obj {
      sloth_input+: {
        [if std.objectHas(obj.sloth_input, '_slos') then 'slos']+: [
          {
            alerting: {
              labels: params.alerting.labels,
              page_alert: {
                labels: params.alerting.page_labels,
              },
              ticket_alert: {
                labels: params.alerting.ticket_labels,
              },
            },
          }
          +
          com.makeMergeable(
            obj.sloth_input._slos[name] { name: name }
          )
          for name in std.objectFields(obj.sloth_input._slos)
        ],
      },
    },
  params.specs
);

if std.length(specs) == 0 then
  // Create an empty yaml file so sloth does not throw an error "No files found"
  { empty: null }
else
  std.mapWithKey(function(name, obj) obj.sloth_input, specs)
