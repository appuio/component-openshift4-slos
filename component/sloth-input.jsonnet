// main template for openshift4-slos
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local slos = import 'slos.libsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_slos;

local input = std.mapWithKey(function(name, obj) obj.sloth_input, slos.Specs);
if std.length(input) == 0 then
  // Create an empty yaml file so sloth does not throw an error "No files found"
  { empty: null }
else
  input
