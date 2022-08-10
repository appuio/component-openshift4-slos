local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.openshift4_slos;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('openshift4-slos', params.namespace);

{
  'openshift4-slos': app,
}
