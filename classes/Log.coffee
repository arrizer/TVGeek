class Log
  LEVELS =
    debug:
      level: 0
      colors: ['blue']
      textColors: ['blackBright']
    info:
      level: 1
      colors: ['cyan']
      textColors: []
    warn:
      level: 2
      colors: ['black','bgYellow']
      textColors: ['yellow']
    error:
      level: 3
      colors: ['red']
      textColors: ['red']
    fatal:
      level: 4
      colors: ['white','bgRedBright']
      textColors: ['red']

  DEFAULT = null

  @Default: ->
    DEFAULT = @Stderr() unless DEFAULT?
    return DEFAULT

  @Stderr: ->
    new Log(process.stderr)
    
  constructor: (@stream) ->
    @colored = yes
    @timestamp = no
    @level = 5
    @prefix = ''
    for level of LEVELS
      do (level) =>
        @[level] = (message, parameters...) =>
          @log(level, message, parameters...)

  colorize: (string, colors...) ->
    return string if !@colored or !colors? or colors.length == 0
    chain = CLIColor
    for color in colors
      chain = chain[color]
    return chain(string)

  log: (level, message, parameters...) ->
    line = ''
    line += @colorize('[' + new Date() + '] ', 'blackBright') if @timestamp
    line += @colorize('[' + level.toUpperCase() + ']', LEVELS[level].colors...)
    line += ' ' + @colorize(sprintf(@prefix + message, parameters...), LEVELS[level].textColors...)
    @stream.write line + "\n", 'utf8'

log = Log.Default()