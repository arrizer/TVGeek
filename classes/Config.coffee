class Config
  DEFAULTS =
    inbox: null
    library: null
    structure: '%show_sortable%/Season %season%/%show% S%season_00%E%episode_00% %title%'
    policy: 'replaceWhenBigger'
    considerExtensions: ["mp4","mkv","avi","mov"]
    deleteExtensions: []

  constructor: (@file) ->
  
  read: (next) ->
    FileSystem.readFile @file, (error, data) =>
      if error?
        next(error)
      else
        @load JSON.parse(data.toString())
        next()

  load: (config) ->
    @config = DEFAULTS
    for key of config
      if key of DEFAULTS
        @config[key] = config[key]
      else
        log.warn 'Unknown option "%s" in configuration file', key
    @config.considerExtensions = @config.considerExtensions.map (extension) -> '.'+extension

  get: ->
    @config