// main template for openshift4-slos
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_slos;

local patchSLO(slo) =
  local p =
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
    com.makeMergeable(slo);
  local enabled = com.getValueOrDefault(p, 'enabled', true);
  if enabled then p else null;

local extractSlothInput(name, spec) =
  local slos = std.prune(std.map(
    patchSLO,
    com.getValueOrDefault(spec.sloth_input, 'slos', [])
    +
    [
      spec.sloth_input._slos[name] { name: name }
      for name in std.objectFields(
        com.getValueOrDefault(spec.sloth_input, '_slos', {})
      )
    ]
  ));
  if std.length(slos) > 0 then
    spec.sloth_input {
      slos: slos,
    }
  else null;


local input = std.prune(std.mapWithKey(extractSlothInput, params.specs));

{
  Input: input,
}
