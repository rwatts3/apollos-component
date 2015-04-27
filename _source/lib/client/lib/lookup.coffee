# ###
#
#   This file is a direct copy of Blaze lookup.js with modifications described
#   in this pull request: https://github.com/meteor/meteor/pull/4036
#
#   TODO:
#     - Remove this file once the pull request is merged in.
#
# ###
#
#
# # If `x` is a function, binds the value of `this` for that function
# # to the current data context.
# bindDataContext = (x) ->
#
#   if typeof x is "function"
#     ->
#       data = Blaze.getData()
#       data ?= {}
#       x.apply data, arguments
#     return
#
#   return x
#
#
# wrapHelper = (f, templateFunc) ->
#
#   # XXX COMPAT WITH METEOR 1.0.3.2
#   if not Blaze.Template._withTemplateInstanceFunc
#     return Blaze._wrapCatchingExceptions(f, 'template helper')
#
#
#
#
#   if typeof f isnt "function"
#     return f
#
#   ->
#     self = @
#     args = arguments
#
#     Blaze.Template._withTemplateInstanceFunc templateFunc, ->
#       Blaze._wrapCatchingExceptions(f, "template helper").apply self, args
#
#
#
# Blaze._getTemplateHelper = (template, name, templateInstance) ->
#
#   if template.__helpers.has name
#
#     helper = template.__helpers.get name
#
#     if helper?
#       return wrapHelper bindDataContext(helper), templateInstance
#     else
#       return null
#
#
#   if name of template
#
#     if template[name]?
#       return wrapHelper bindDataContext(template[name]), templateInstance
#     else
#       return null
#
#
#
#   return null
#
#
#
# Blaze._getTemplate = (name, templateInstance) ->
#
#   if (name of Blaze.Template) and (Blaze.Template[name] instanceof Blaze.Template)
#     return Blaze.Template[name]
#
#   return null
#
#
# Blaze.View::lookup = (name, _options) ->
#
#   template = @.template
#   lookupTemplate = _options and _options.template
#
#
#   if @.templateInstance
#     boundTmplInstance = _.bind @.templateInstance, @
#
#   if /^\./.test(name)
#
#     # starts with a dot. must be a series of dots which maps to an
#     # ancestor of the appropriate height.
#     if !/^(\.)+$/.test(name)
#
#       throw new Error("id starting with dot must be a series of dots")
#
#     return Blaze._parentData(name.length - 1, true)
#
#
#   else if (template and (helper = Blaze._getTemplateHelper(template, name, boundTmplInstance)))?
#
#     return helper
#
#   else if (lookupTemplate and (foundTemplate = Blaze._getTemplate(name, boundTmplInstance)))?
#
#     return foundTemplate
#
#   else if Blaze._globalHelpers[name]?
#
#     return wrapHelper(bindDataContext(Blaze._globalHelpers[name]), boundTmplInstance)
#
#   else
#
#     return ->
#       isCalledAsFunction = arguments.length > 0
#       data = Blaze.getData()
#
#       if lookupTemplate and !(data and data[name])
#
#         throw new Error("No such template: " + name)
#
#       if isCalledAsFunction and !(data and data[name])
#
#         throw new Error("No such function: " + name)
#
#       if !data
#         return null
#
#       x = data[name]
#
#       if typeof x != "function"
#
#         if isCalledAsFunction
#           throw new Error("Can\"t call non-function: " + x)
#
#         return x
#
#       x.apply data, arguments
#
#   return null
