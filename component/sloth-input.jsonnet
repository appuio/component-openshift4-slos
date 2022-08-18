// main template for openshift4-slos
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local sloth = import 'sloth.libsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_slos;

local input = sloth.Input;
if std.length(input) == 0 then
  // Create an empty yaml file so sloth does not throw an error "No files found"
  { empty: null }
else
  input
