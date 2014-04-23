class EventEmitter
  on: (event, callback) ->
    @_listeners = {} unless @_listeners?
    @_listeners[event] = [] unless @_listeners[event]?
    @_listeners[event].push callback

  emit: (event, args...) ->
    if @_listeners? and @_listeners[event]?
      callback(args...) for callback in @_listeners[event]
      
  propagate: (emitter, event) ->
    emitter.on event, (=> @emit event)