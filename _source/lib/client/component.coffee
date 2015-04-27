

class Namespace
  constructor: (@namespace, @templateInstance) ->



###

  We extend the original dot operator to support {{> Foo.Bar}}. This goes through a getTemplateHelper path, but we want to redirect it to the getTemplate path. So we mark it in getTemplateHelper and then here call getTemplate.

###
originalDot = Spacebars.dot
Spacebars.dot = (value, args...) ->

  if value instanceof Namespace
    return Blaze._getTemplate(
      "#{value.namespace}.#{args.join('.')}",
      value.templateInstance
    )

  originalDot value, args...


###

  We override the original lookup method with a similar one, which supports components as well.

  Now the order of the lookup will be, in order:
    a helper of the current template
    a property of the current component
    the name of a component
    the name of a template
    global helper
    a property of the data context

  Returns a function, a non-function value, or null. If a function is found, it is bound appropriately.

  NOTE: This function must not establish any reactive dependencies itself.  If there is any reactivity
  in the value, lookup should return a function.

  TODO: Should we also lookup for a property of the component-level data context (and template-level data context)?

###

Blaze._getTemplateHelper = (template, name, templateInstance) ->

  if template.__helpers.has name

    helper = template.__helpers.get name

    if helper?
      return wrapHelper bindDataContext(helper), templateInstance
    else
      return null


  if name of template

    if template[name]?
      return wrapHelper bindDataContext(template[name]), templateInstance
    else
      return null


  if not templateInstance
    return null

  ###

    Do not resolve component helpers if inside Template.dynamic.
    The reason is that Template.dynamic uses a data context
    value with name "template" internally. But when used inside a component the data context lookup is then resolved
    into a current component's template method and not the data context "template". To force the data context resolving
    Template.dynamic should use "this.template" in its templates, but it does not, so we have a special case here for it.

  ###
  if template.viewName in ['Template.__dynamicWithDataContext', 'Template.__dynamic']
    return null

  ###

    TODO:
    - Blaze.View::lookup should not introduce any reactive dependencies.
    - Can we simply ignore reactivity here?
    - Can this template instance or parent template instances change without reconstructing the component as well? I don't think so.
    - Only data context is changing and this is why templateInstance or .get() are reactive and we do not care about data context here.

  ###
  component = Tracker.nonreactive ->
    return templateInstance().get "component"


  # Component
  if component
    return wrapHelper(
      bindComponent(component, component[name]), templateInstance
    )


  ###

    A special case to support {{> Foo.Bar}}. This goes through a getTemplateHelper path, but we want to redirect it to the getTemplate path. So we mark it and leave to Spacebars.dot to call getTemplate.

    TODO:
      - We should provide a Apollos.Base.getNamespace method instead of accessing components directly.

  ###

  # if name and name of Apollos.Base.components
  #   console.log "inside here"
    # return new Namespace name, templateInstance
    # return template

  return null



bindComponent = (component, helper) ->

  if typeof helper is "function"
    return _.bind helper, component

  return helper


bindDataContext = (helper) ->

  if typeof helper is "function"
    ->
      data = Blaze.getData()
      data ?= {}
      helper.apply data, arguments
    return

  return helper


wrapHelper = (f, templateFunc) ->

  # XXX COMPAT WITH METEOR 1.0.3.2
  if not Blaze.Template._withTemplateInstanceFunc
    return Blaze._wrapCatchingExceptions f, "template helper"

  if typeof f isnt "function"
    return f

  ->
    self = @
    args = arguments

    Blaze.Template._withTemplateInstanceFunc templateFunc, ->
      Blaze._wrapCatchingExceptions(f, "template helper").apply self, args



viewToTemplateInstance = (view) ->

  ###

    We skip contentBlock views which are injected by Meteor when using block helpers (in addition to block helper view). This matches more the visual structure of templates and not the internal implementation.

  ###
  isContent = view.name is '(contentBlock)'
  isElse = view.name is '(elseBlock)'

  while view and (not view.template or isContent or isElse)
    view = view.originalParentView or view.parentView

  # Body view has template field, but not templateInstance.
  # We return null in that case.
  if not view?.templateInstance
    return null

  _.bind view.templateInstance, view


addEvents = (view, component) ->

  eventsList = component.events()

  if not _.isArray eventsList
    debug(
      "`events` methods from the component `#{ component.componentName() or 'unnamed' }` did not return an array of event maps"
    )
    return

  for events in eventsList

    eventMap = {}

    for event, action of events

      do (event, action) ->

        eventMap[event] = (args...) ->

          _event = args[0]

          currentView = Blaze.getView event.currentTarget
          templateInstance = viewToTemplateInstance currentView

          withTemplateInstanceFunc = Template._withTemplateInstanceFunc

          ###

            We set template instance based on the current target so that inside event handlers Component.currentComponent() returns the component of event target.

          ###
          withTemplateInstanceFunc templateInstance, ->

            ###

              We set view based on the current target so that inside event handlers Component.currentData() (and Blaze.getData() and Template.currentData()) returns data context of event target and not component/template.

            ###
            Blaze._withCurrentView currentView, ->
              action.apply component, args

          # Make sure CoffeeScript does not return anything. Returning from event
          # handlers is deprecated.
          return

    # bind them to the views events
    Blaze._addEventMap view, eventMap

    return



# store original Blaze._getTemplate
originalGetTemplate = Blaze._getTemplate
Blaze._getTemplate = (name, templateInstance) ->
  # Blaze.View::lookup should not introduce any reactive dependencies, so we are making sure it is so.
  template = Tracker.nonreactive ->
    componentParent = templateInstance?().get "component"

    Component
      .getComponent(name)?.renderComponent componentParent

  isFunction = typeof template is "function"

  if template and (template instanceof Blaze.Template or isFunction)
    return template


  return originalGetTemplate name



createUIHooks = (component, parentNode) ->

  insertElement: (node, before) =>
    node._uihooks ?= createUIHooks component, node
    component.insertDOMElement parentNode, node, before

  moveElement: (node, before) =>
    node._uihooks ?= createUIHooks component, node
    component.moveDOMElement parentNode, node, before

  removeElement: (node) =>
    node._uihooks ?= createUIHooks component, node
    component.removeDOMElement node.parentNode, node



# store originalDOMAttach
originalDOMRangeAttach = Blaze._DOMRange::attach
# overwrite to new one
Blaze._DOMRange::attach = (parentElement, nextNode, _isMove, _isReplace) ->

  if component = @.view._templateInstance?.component

    oldUIHooks = parentElement._uihooks

    try
      parentElement._uihooks = createUIHooks component, parentElement
      return originalDOMRangeAttach.apply @, arguments

    finally

      parentElement._uihooks = oldUIHooks if oldUIHooks

  originalDOMRangeAttach.apply @, arguments



registerHooks = (template, hooks) ->

  if not template.onCreated
    return

  template.onCreated hooks.onCreated
  template.onRendered hooks.onRendered
  template.onDestroyed hooks.onDestroyed

  return


registerFirstCreatedHook = (template, onCreated) ->

  if not template._callbacks
    return

  template._callbacks.created.unshift onCreated

  return



# Apollos.Component
#
# - reactive vars (✓)
# - subscriptions (✓)
#
# - helpers (✓)
# - events (✓)
# - animations
#
# - onCreated (✓)
# - onRendered (✓)
# - onDestroyed (✓)
#
# - junction selection binding
#
# - parent
# - children

Apollos.components = {}

# Apollos.Base = BaseComponent
class Component extends Apollos.Base

  # TODO: Figure out how to do at the Apollos.Base level?
  @getComponentForElement: (domElement) ->

    if not domElement
      return null

    # This uses the same check if the argument is a DOM element that Blaze._DOMRange.forElement does.
    if domElement.nodeType isnt Node.ELEMENT_NODE
      console.log "Expected DOM element."

    template = Blaze.getView(domElement)?.templateInstance()

    return template?.get('component') or null



    ###

    This class method more or less just creates an instance of a component and calls its renderComponent method. But because we want to allow passing arguments to the component in templates, we have some complicated code around to extract and pass those arguments. It is similar to how data context is passed to block helpers. In a data context visible only to the block helper template.

    TODO: This could be made less hacky. See https://github.com/meteor/meteor/issues/3913

  ###
  @renderComponent: (componentParent) ->

    # setup non reactive lookup of data to prevent over rendering and execution
    Tracker.nonreactive =>
      componentClass = @

      try
        ###

          We check data context in a non-reactive way, because we want just to peek into it and determine if data context contains component arguments or not. And while  component arguments might change through time, the fact that they are there at all or not ("args" template helper was used or not) does not change through time. So we can check that non-reactively.

        ###
        data = Template.currentData()

      catch error
        ###

          The exception can be thrown when there is no current view which happens when there is no data context yet, thus also no arguments were provided through"args" template helper, so we just continue normally.

        ###
        data = null

      if data?.constructor isnt argumentsConstructor
        component = new componentClass()
        return component.renderComponent componentParent

      # Arguments were provided through "args" template helper.

      ###

        We want to reactively depend on the data context for arguments, so we return a function instead of a template. Function will be run inside an autorun, a reactive context.

      ###

      ->
        ###

          We cannot use Template.getData() inside a normal autorun because current view is not defined inside a normal autorun. But we do not really have to depend reactively on the current view, only on the data context of a known (the closest Blaze.With) view. So we get this view by ourselves.

        ###
        currentWith = Blaze.getView "with"

        ###

          By default dataVar in the Blaze.With view uses ReactiveVar with default equality function which sees all objects as different. So invalidations are triggered for every data context assignments even if data has not really changed. This is why we use our own ReactiveVar with EJSON.equals which we keep updated inside an autorun. Because it uses EJSON.equals it will invalidate our function only if really changes. See https://github.com/meteor/meteor/issues/4073

        ###
        reactiveArguments = new ReactiveVar [], EJSON.equals


        ###

          This autorun is nested in the outside autorun so it gets stopped automatically when the outside autorun gets invalidated.

        ###
        Tracker.autorun (computation) ->
          data = currentWith.dataVar.get()

          reactiveArguments.set data._arguments

        ###

          Use arguments for the constructor. Here we register a reactive dependency on our own ReactiveVar.

        ###
        component = new componentClass reactiveArguments.get()...

        template = component.renderComponent componentParent

        ###

          It has to be the first callback so that other callbacks have a correct data context.

        ###
        registerFirstCreatedHook template, ->

          ###

            Arguments were passed in as a data context. Restore original (parent) data context. Same logic as in Blaze._InOuterTemplateScope.

          ###
          @.view.originalParentView = @.view.parentView
          @.view.parentView = @.view.parentView.parentView.parentView

        return template

  renderComponent: (componentParent) ->

    ###

      To make sure we do not introduce any reactive dependency. This is a conscious design decision. Reactivity should be changing data context, but components should be more stable, only changing when structure change in rendered DOM. You can change the component you are including (or pass different arguments) reactively though.

    ###
    Tracker.nonreactive =>
      component = @

      component._internals ?= {}

      componentTemplate = component.componentName()

      # if its a string, load the string
      if _.isString componentTemplate
        templateBase = Template[componentTemplate]
        if not templateBase
          debug "Template '#{componentTemplate}' cannot be found."
          return
      else
        # we have an actual template
        templateBase = componentTemplate

      ###

        Create a new component template based on the Blaze template. We want our own template  because the same Blaze template could be reused between multiple components.

        TODO:
          - Should we cache these templates based on (componentName, templateBase) pair?
          - We could use two levels of ES6 Maps, componentName -> templateBase -> template.
          - What about component arguments changing?

      ###

      template = new Blaze.Template(
        "Component.#{component.componentName() or 'unnamed'}", templateBase.renderFunction
      )

      # We on purpose do not reuse helpers, events, and hooks. Templates are used only for HTML rendering.

      @.component._internals ?= {}

      registerHooks template,


        onCreated: ->
          # @ is a template instance.

          if componentParent

            ###

              component.parent is reactive, so we use
              Tracker.nonreactive just to make sure we do not leak any
              reactivity here.

            ###
            Tracker.nonreactive =>

              ###

                TODO:
                  - Should we support that the same component can be rendered multiple times in parallel?
                  - How could we do that?
                  - For different component parents or only the same one?

              ###

              # We set the parent only when the component is created, not just constructed.
              component.parent componentParent
              componentParent.addChild component


        # Blaze rendered callback
          @.view._onViewRendered =>

            # Attach events the first time template instance renders.
            if @.view.renderCount isnt 1
              return

            addEvents @.view, component



          ###

            Reactive vars are great, but registering them as template helpers
            and setting the default values isn't great yet. Here we attach each var to the component that way it can be gotten via .get and is available in the template as a tag. I'm a little bit worried about polluting the render namespace so should this be kept on the vars object?

          ###
          varList = component.vars()
          if _.isArray varList

            for vars in varList
              for _var, _default of vars

                if component[_var]
                  debug "#{_var} is already a method on #{component.componentName()}"
                  continue

                ###

                  @TODO:
                    - Need to add in way to add reactive comparators
                    - Need to be able to extend vars from parent components

                ###
                component[_var] = new ReactiveVar _default



          ###

            Since meteor 1.1 we can use this.subscribe within the on created function to subscribe to a publications for the lifecycle of the template instance. Here we auto bind them with support for arguments and callbacks

            @TODO:
              - Need to be able to extend subscribes from parent components

          ###
          subscriptionsList = component.subscriptions()
          if _.isArray subscriptionsList

            for subscriptions in subscriptionsList

              if typeof subscriptions is "string"
                @.subscribe method
                continue

              if _.isObject subscriptions

                for _name, method of subscriptions

                  # grab name of subscription
                  subHandle = [_name]

                  # futher args?
                  if method.args?.length
                    subHandle = subHandle.concat method.args

                  # callback?
                  if method.callback
                    subHandle.push method.callback

                  @.subscribe.apply @, subHandle

                  continue


          @.component = component

          ###

            TODO:
              - Should we support that the same component can be rendered multiple times in parallel?
              - How could we do that?
              - For different component parents or only the same one?

          ###
          @.component._internals.templateInstance = @

          # We need to run the onCreated of the child component
          @.component.onCreated()


          @.component._internals.isCreated ?= new ReactiveVar true
          @.component._internals.isCreated.set true

          # Maybe we are re-rendering the component. So let's initialize variables just to be sure.

          @.component._internals.isRendered ?= new ReactiveVar false
          @.component._internals.isRendered.set false

          @.component._internals.isDestroyed ?= new ReactiveVar false
          @.component._internals.isDestroyed.set false

          return

        onRendered: ->

          # @ is a template instance.

          # We need to run the onRendered of the child component
          @.component.onRendered()

          @component._internals.isRendered ?= new ReactiveVar true
          @component._internals.isRendered.set true


        onDestroyed: ->

          # @ is a template instance.
          @.autorun (computation) =>

            # We wait for all children components to be destroyed first.
            # See https://github.com/meteor/meteor/issues/4166
            if @.component.children().length
              return

            computation.stop()

            @component._internals.isCreated.set false

            @component._internals.isRendered ?= new ReactiveVar false
            @component._internals.isRendered.set false

            @component._internals.isDestroyed ?= new ReactiveVar true
            @component._internals.isDestroyed.set true


            # We need to run the onDestroyed of the child component
            @.component.onDestroyed()

            if componentParent
              # The component has been destroyed, clear up the parent.
              component.parent null
              componentParent.removeChild component

            # Remove the reference so that it is clear that template instance is not available anymore.
            delete @.component._internals.templateInstance

            return


      return template

  template: ->
    # You have to override this method with a method which returns a template name or template itself.
    throw new Error "Component method 'template' not overridden."

  onCreated: ->

  onRendered: ->

  onDestroyed: ->

  isCreated: ->
    @._internals ?= {}
    @._internals.isCreated ?= new ReactiveVar false

    return @._internals.isCreated.get()

  isRendered: ->
    @._internals ?= {}
    @._internals.isRendered ?= new ReactiveVar false

    return @._internals.isRendered.get()

  isDestroyed: ->
    @._internals ?= {}
    @._internals.isDestroyed ?= new ReactiveVar false

    return @._internals.isDestroyed.get()


  insertDOMElement: (parent, node, before) ->
    before ?= null

    if parent and node and (node.parentNode isnt parent or node.nextSibling isnt before)

      parent.insertBefore node, before

    return


  moveDOMElement: (parent, node, before) ->
    before ?= null

    if parent and node and (node.parentNode isnt parent or node.nextSibling isnt before)

      parent.insertBefore node, before

    return


  removeDOMElement: (parent, node) ->

    if parent and node and node.parentNode is parent
      parent.removeChild node

    return

  events: ->
    return []

  subscriptions: ->
    return []

  vars: ->
    return []

  # Component-level data context. Reactive. Use this to always get the
  # top-level data context used to render the component.
  # Same as Template.currentData
  data: ->
    return Blaze.getData(@._internals.templateInstance.view) or null

  ###

    Caller-level data context. Reactive. Use this to get in event handlers the data context at the place where event originated (target context). In template helpers the data context where template helpers were called. In onCreated, onRendered, and onDestroyed, the same as @data(). Inside a template this is the same as this.

  ###
  currentData: ->
    Blaze.getData() or null


  # Useful in templates to get a reference to the component.
  component: ->
    return @


  ###

    Caller-level component. In most cases the same as @, but in event handlers it returns the component at the place where event originated (target component).

  ###
  currentComponent: ->
    return Template.instance()?.get("component") or null


  firstNode: ->
    return @._internals.templateInstance.firstNode


  lastNode: ->
    return @._internals.templateInstance.lastNode


  # parentTemplate: (level, includeBlockHelpers) ->
  #   template = @._internals.templateInstance
  #
  #   level or= 1
  #
  #   template = @._internals.templateInstance.__parent(level, includeBlockHelpers)
  #
  #   # keep on climbing if we have a Component
  #   isComponent = template.name?.match(/Component\./)?.length > 0
  #   while isComponent
  #
  #     template = @._internals.templateInstance.__parent(level, includeBlockHelpers)
  #
  #     if not template
  #       return null
  #
  #
  #   return template

# We copy utility methods ($, findAll, autorun, subscribe, etc.) from the template instance prototype.
for methodName, method of Blaze.TemplateInstance::
  do (methodName, method) ->

    # shim for adding juction in
    # if methodName is "$"
    #   Component::[methodName] = junction
    #   return

    Component::[methodName] = (args...) ->
      @._internals.templateInstance[methodName] args...




argumentsConstructor = ->
  # This class should never really be created.
  return false


###

  TODO:
    - Find a way to pass arguments to the component without having to introduce one intermediary data context into the data context hierarchy (in fact two data contexts, because we add one more when restoring the original one)

###
Template.registerHelper "args", ->
  obj = {}
  # We use custom constructor to know that it is not a real data context.
  obj.constructor = argumentsConstructor
  obj._arguments = arguments
  return obj


###

  We make Template.dynamic resolve to the component if component name is
  specified as a template name, and not to the non-component template which
  is probably used only for the content. We simply reuse Blaze._getTemplate.

  TODO:
    - How to pass args?
    - Maybe simply by using Spacebars nested expressions
    (https://github.com/meteor/meteor/pull/4101)?
    - Template.dynamic template="..." data=(args ...)?
    - But this exposes the fact that args are passed as data context.
    - Maybe we should simply override Template.dynamic and add "args" argument?

  TODO:
    - This can be removed once https://github.com/meteor/meteor/pull/4036 is merged in.

###
Template.__dynamicWithDataContext.__helpers.set "chooseTemplate", (name) ->
  Blaze._getTemplate name, =>
    Template.instance()


Apollos.Component = Component
