

Package.describe({
  'name': 'newspring:components',
  'version': '0.1.0',
  'summary': ''

});


Package.onUse(function(api) {


  api.versionsFrom('1.0.3.1');
  api.use('meteor-platform');
  api.use('blaze');
  api.use('templating');
  api.use('underscore');
  api.use('tracker');
  api.use('ejson');
  api.use('spacebars');
  api.use('reactive-var');


  api.addFiles('lib/client/lib/helpers.js', 'client');
  api.addFiles('lib/client/lib/lookup.js', 'client');
  api.addFiles('lib/client/lib/vars.js', 'client');
  api.addFiles('lib/client/base.js', 'client');
  api.addFiles('lib/client/component.js', 'client');
  api.addFiles('lib/client/xport.js', 'client');


  api.export('Component', 'client');
});


Package.onTest(function(api) {


  api.use('mocha');
  api.use('components');
});