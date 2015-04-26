Apollos = {}

debug = function() {
  var log = console.log

  log.apply(console, Array.prototype.slice.call(arguments));

}
