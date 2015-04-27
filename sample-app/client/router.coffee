class ExampleComponent extends Component
  # Register a component so that it can be included in templates. It also
  # gives the component the name. The convention is to use the class name.
  @register "ExampleComponent"

  # Which template to use for this component.
  template: "ExampleComponent"


  # Create reactivevar and expose them to the template as a helper
  vars: -> [

    counter: 0

  ]

  # Mapping between events and their handlers.
  events: -> [
    # You could inline the handler, but the best is to make
    # it a method so that it can be extended later on.
    "click .increment": @.onClick


  ]

  onClick: (event) ->
    @.counter.set @.counter.get() + 1
    console.log @.find(".increment")


  # Any component"s method is available as a template helper in the template.
  customHelper: ->
    if @.counter.get() > 10
      "Too many times"
    else if @.counter.get() is 10
      "Just enough"
    else
      "Click more"


class Foo extends ExampleComponent

  @register "Foo"

  template: "Foo"


  # Create reactivevar and expose them to the template as a helper
  vars: ->

    super.concat

      color: "red"



  onClick: (event) ->
    if @.color.get() is "red"
      @.color.set "blue"
    else
      @.color.set "red"

    super


  # Any component"s method is available as a template helper in the template.
  customHelper: ->
    @.color.get()
